import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/experience/camera_check_page.dart';
import 'account_fakes.dart';
import 'chat_test.dart' as chats;

class CameraStub extends ImagePickerPlatform {
  CameraStub(this.file);
  final String file;
  int calls = 0;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    expect(source, ImageSource.camera);
    calls++;
    return XFile(file);
  }
}

void main() {
  testWidgets(
    'camera diagnostics waits for user consent, keeps preview local and removes its cached capture',
    (t) async {
      final directory = (await t.runAsync(
            () => Directory.systemTemp.createTemp('tomi-camera37-'),
          ))!,
          file = File('${directory.path}/camera.png');
      await t.runAsync(
        () => file.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jftkAAAAASUVORK5CYII=',
          ),
        ),
      );
      addTearDown(() => t.runAsync(() => directory.delete(recursive: true)));
      final previous = ImagePickerPlatform.instance,
          fake = CameraStub(file.path);
      ImagePickerPlatform.instance = fake;
      addTearDown(() => ImagePickerPlatform.instance = previous);
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final account = AccountController(
        api: chats.ChatFakeApi(),
        vault: MemoryTokenVault('token'),
        realtimeEnabled: false,
      );
      await account.restore();
      addTearDown(account.dispose);
      await t.pumpWidget(MaterialApp(home: CameraCheckPage(accounts: account)));
      await t.pumpAndSettle();
      expect(fake.calls, 0);
      await t.runAsync(() async {
        await t.tap(find.text('فتح الكاميرا'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(fake.calls, 1);
      expect(find.byType(Image), findsOneWidget);
      expect(await t.runAsync(file.exists), false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
