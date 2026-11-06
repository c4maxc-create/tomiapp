import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:tomi_app/src/messaging/voice_note.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'microphone diagnostic starts only on request and returns no sendable recording',
    (t) async {
      final old = RecordPlatform.instance, fake = RecorderStub(-20);
      RecordPlatform.instance = fake;
      addTearDown(() => RecordPlatform.instance = old);
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => '/tmp');
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
      Object? result = 'not closed';
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<Object?>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const VoiceRecorderSheet(diagnostic: true),
                  );
                },
                child: const Text('فحص'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('فحص'));
      await t.pumpAndSettle();
      expect(fake.config, isNull);
      await t.tap(find.text('بدء التسجيل'));
      for (var i = 0; i < 8; i++)
        await t.pump(const Duration(milliseconds: 200));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 550)),
      );
      await t.tap(find.byKey(const Key('voice-stop')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('إنهاء الفحص'));
      await t.tap(find.text('إنهاء الفحص'));
      await t.pumpAndSettle();
      expect(result, isNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
    },
  );
  for (final db in [-120.0, -20.0])
    testWidgets(
      'voice recorder uses microphone input and ${db < -80 ? "warns before sending a silent capture" : "allows a capture with detected speech"}',
      (t) async {
        final old = RecordPlatform.instance, fake = RecorderStub(db);
        RecordPlatform.instance = fake;
        addTearDown(() => RecordPlatform.instance = old);
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(paths, (_) async => '/tmp');
        addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
        await t.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: VoiceRecorderSheet(autoStart: true)),
          ),
        );
        for (var i = 0; i < 8; i++)
          await t.pump(const Duration(milliseconds: 200));
        expect(fake.config?.androidConfig.audioSource, AndroidAudioSource.mic);
        expect(find.byKey(const Key('voice-stop')), findsOneWidget);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 550)),
        );
        expect(
          t.widget<FilledButton>(find.byKey(const Key('voice-stop'))).onPressed,
          isNotNull,
        );
        await t.tap(find.byKey(const Key('voice-stop')));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pumpAndSettle();
        expect(fake.recording, false);
        final button = t.widget<FilledButton>(
          find.byKey(const Key('voice-confirm')),
        );
        if (db < -80) {
          expect(
            find.text('لم نرصد صوتًا واضحًا. راجع المايك أو أعد التسجيل.'),
            findsOneWidget,
          );
          expect(button.onPressed, isNull);
        } else {
          expect(button.onPressed, isNotNull);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump();
      },
    );
}

class RecorderStub extends RecordPlatform {
  RecorderStub(this.db);
  final double db;
  final states = StreamController<RecordState>.broadcast();
  RecordConfig? config;
  String? path;
  bool recording = false;
  @override
  Future<void> create(String id) async {}
  @override
  Future<bool> hasPermission(String id, {bool request = true}) async => true;
  @override
  Future<void> start(
    String id,
    RecordConfig config, {
    required String path,
  }) async {
    this.config = config;
    this.path = path;
    recording = true;
    states.add(RecordState.record);
  }

  @override
  Stream<RecordState> onStateChanged(String id) => states.stream;
  @override
  void setOnConfigChanged(String id, void Function(RecordConfig)? handler) {}
  @override
  Future<bool> isRecording(String id) async => recording;
  @override
  Future<Amplitude> getAmplitude(String id) async =>
      Amplitude(current: db, max: db);
  @override
  Future<String?> stop(String id) async {
    recording = false;
    states.add(RecordState.stop);
    return path;
  }

  @override
  Future<void> cancel(String id) async {
    recording = false;
  }

  @override
  Future<void> dispose(String id) async {
    await states.close();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
