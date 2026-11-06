import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:tomi_app/src/preferences/media_preferences.dart';
import 'package:tomi_app/src/preferences/network_media_image.dart';
import 'package:tomi_app/src/messaging/voice_note.dart';

class NetworkStub extends ConnectivityPlatform {
  List<ConnectivityResult> kinds = [ConnectivityResult.mobile];
  final events = StreamController<List<ConnectivityResult>>.broadcast();
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => kinds;
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => events.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Wi-Fi only images do not create a network image until allowed and respond to connectivity changes',
    (t) async {
      final previous = ConnectivityPlatform.instance,
          network = NetworkStub(),
          preferences = MediaPreferences.instance;
      ConnectivityPlatform.instance = network;
      addTearDown(() async {
        ConnectivityPlatform.instance = previous;
        await preferences.update(wifi: false);
        await network.events.close();
      });
      await preferences.update(wifi: true);
      await t.pumpWidget(
        MaterialApp(
          home: NetworkMediaImage(
            'https://example.com/picture.png',
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      network.kinds = [ConnectivityResult.wifi];
      network.events.add(network.kinds);
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      network.kinds = [ConnectivityResult.mobile];
      network.events.add(network.kinds);
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  test(
    'Wi-Fi only voice playback refuses remote audio before allocating a player',
    () async {
      final previous = ConnectivityPlatform.instance,
          network = NetworkStub(),
          preferences = MediaPreferences.instance;
      ConnectivityPlatform.instance = network;
      final playback = VoicePlayback();
      try {
        await preferences.update(wifi: true);
        await playback.toggle(
          'voice',
          () async => Uri.parse('https://example.com/voice.m4a'),
          duration: 1000,
        );
        expect(playback.player, isNull);
        expect(playback.error, contains('Wi-Fi'));
        expect(playback.busy, false);
      } finally {
        playback.dispose();
        ConnectivityPlatform.instance = previous;
        await preferences.update(wifi: false);
        await network.events.close();
      }
    },
  );
}
