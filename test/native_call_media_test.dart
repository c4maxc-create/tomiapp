import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tomi_app/src/calling/call_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('FlutterWebRTC.Method');
  const events = MethodChannel('FlutterWebRTC/peerConnectionEventnative-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final video in [false, true]) {
    test(
      'native ${video ? 'video' : 'audio'} offer and answer override the plugin video default',
      () async {
        final constraints = <Map>[];
        WebRTC.initialized = false;
        messenger.setMockMethodCallHandler(events, (_) async => null);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'createPeerConnection')
            return {'peerConnectionId': 'native-test'};
          if (call.method == 'createOffer' || call.method == 'createAnswer') {
            // Model the platform's generated m-lines from the REAL plugin
            // arguments. Calling createOffer() without options uses its video
            // default and makes this audio regression fail.
            final options = (call.arguments as Map)['constraints'] as Map;
            constraints.add(options);
            final receiveVideo =
                (options['mandatory'] as Map)['OfferToReceiveVideo'] == true;
            return {
              'type': call.method == 'createOffer' ? 'offer' : 'answer',
              'sdp':
                  'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=fingerprint:sha-256 00:11\r\n'
                  '${receiveVideo ? 'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n' : ''}',
            };
          }
          return null;
        });
        final engine = NativeCallMedia()
          ..peer = await createPeerConnection({'iceServers': []})
          ..videoEnabled = video;
        try {
          final offer = await engine.offer(), answer = await engine.answer();
          expect(offer.contains('m=video'), video);
          expect(answer.contains('m=video'), video);
          expect(constraints, hasLength(2));
          for (final options in constraints) {
            expect(
              (options['mandatory'] as Map)['OfferToReceiveAudio'],
              isTrue,
            );
          }
        } finally {
          await engine.dispose();
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMethodCallHandler(events, null);
        }
      },
    );
  }
}
