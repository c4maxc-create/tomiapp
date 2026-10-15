import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/notifications/mobile_runtime.dart';
import 'package:tomi_app/src/notifications/push_controller.dart';
import 'package:tomi_app/src/voice_rooms/room_controller.dart';
import 'account_fakes.dart';
import 'calls_test.dart' show CallFakeApi, FakeCallMedia, callId, drain;
import 'chat_test.dart' show threadId;
import 'rooms_test.dart' show RoomFakeApi, FakeRoomAudio, roomId;
import 'media05_test.dart' show FakeDevice;

class FakeMobile implements MobileRuntime {
  bool available = true;
  String? current, binding;
  Completer<void>? gate;
  final starts = <Map<String, dynamic>>[],
      stops = <String>[],
      renews = <String>[],
      cleared = <String>[];
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? pending;
  @override
  bool get supported => true;
  @override
  Stream<Map<String, dynamic>> get actions => bus.stream;
  @override
  Future<bool> startAudio(
    String id,
    String kind, {
    bool microphone = false,
  }) async {
    starts.add({'id': id, 'kind': kind, 'microphone': microphone});
    await gate?.future;
    if (available) current = id;
    return available;
  }

  @override
  Future<void> renewAudio(String id) async {
    renews.add(id);
  }

  @override
  Future<void> stopAudio(String id) async {
    stops.add(id);
    if (current == id) current = null;
  }

  @override
  Future<void> bind(String? account, String? value, bool enabled) async {
    binding = enabled ? value : null;
  }

  @override
  Future<void> clearCall(String id) async {
    cleared.add(id);
  }

  @override
  Future<Map<String, dynamic>?> takeAction() async {
    final d = pending;
    pending = null;
    return d;
  }

  void emit(Map<String, dynamic> d) {
    pending = d;
    bus.add(d);
  }
}

class MobileCallApi extends CallFakeApi {
  bool failRead = false;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/push/settings')
      return {'configured': true, 'enabled': true};
    if (path == '/v1/push/device')
      return {'configured': true, 'bindingId': 'session-binding'};
    if (failRead && method == 'GET' && path == '/v1/calls/$callId')
      throw const AccountFailure('NETWORK', 'offline');
    return super.chatRequest(token, method, path, body: body, query: query);
  }
}

Future<AccountController> account(
  AccountApi api,
  FakeMobile mobile, {
  FakeCallMedia? media,
}) async {
  final a = AccountController(
    api: api,
    vault: MemoryTokenVault('session'),
    realtimeEnabled: false,
    mobile: mobile,
    callMediaFactory: media == null ? null : () => media,
  );
  await a.restore();
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'screen off retains active audio and signaling; hangup releases the service',
    () async {
      final api = CallFakeApi(),
          mobile = FakeMobile(),
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          calls = a.calls;
      addTearDown(a.dispose);
      await calls.start(threadId);
      expect(calls.backgroundAudio, isTrue);
      calls.didChangeAppLifecycleState(AppLifecycleState.paused);
      await calls.tick();
      expect(calls.active!.ended, isFalse);
      expect(media.disposed, isFalse);
      expect(mobile.renews, contains(callId));
      await calls.hangup();
      await calls.releaseTail;
      expect(media.disposed, isTrue);
      expect(mobile.stops, contains(callId));
    },
  );
  test(
    'minimized video stops capture and returning never silently enables it',
    () async {
      final api = CallFakeApi(),
          mobile = FakeMobile(),
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          c = a.calls;
      addTearDown(a.dispose);
      await c.start(threadId, video: true);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      await drain();
      expect(media.video, isFalse);
      expect(c.cameraOn, isFalse);
      expect(c.active!.ended, isFalse);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await drain();
      expect(media.video, isFalse);
      await c.toggleCamera();
      expect(media.video, isTrue);
    },
  );
  test(
    'unavailable foreground service keeps the foreground-only fallback',
    () async {
      final api = CallFakeApi(),
          mobile = FakeMobile()..available = false,
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          c = a.calls;
      addTearDown(a.dispose);
      await c.start(threadId);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      await drain();
      expect(c.active!.ended, isTrue);
      expect(media.disposed, isTrue);
    },
  );
  test(
    'a service start completing after logout cannot revive capture or signaling',
    () async {
      final api = CallFakeApi(),
          mobile = FakeMobile()..gate = Completer<void>(),
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          c = a.calls;
      addTearDown(a.dispose);
      final work = c.start(threadId);
      await drain();
      expect(mobile.starts, isNotEmpty);
      await a.logout();
      mobile.gate!.complete();
      await work;
      await c.releaseTail;
      expect(c.active, isNull);
      expect(media.disposed, isTrue);
      expect(mobile.current, isNull);
      expect(api.signals, isEmpty);
    },
  );
  test(
    'room listener keeps heartbeat when locked without starting a microphone',
    () async {
      final api = RoomFakeApi(),
          mobile = FakeMobile(),
          a = await account(api, mobile),
          audio = FakeRoomAudio(),
          c = VoiceRoomsController(
            accounts: a,
            audioFactory: () => audio,
            autoPoll: false,
          );
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      expect(await c.join(roomId), isTrue);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      await c.tick();
      expect(c.active, isNotNull);
      expect(audio.enables, 0);
      expect(mobile.starts.single['microphone'], isFalse);
      expect(mobile.renews, isNotEmpty);
      await c.leave();
      expect(mobile.stops, contains('my-identity'));
    },
  );
  test(
    'background moderation revokes an already open room microphone',
    () async {
      final api = RoomFakeApi()
            ..seat = 0
            ..allowed = true,
          mobile = FakeMobile(),
          a = await account(api, mobile),
          audio = FakeRoomAudio()..canPublish = true,
          c = VoiceRoomsController(
            accounts: a,
            audioFactory: () => audio,
            autoPoll: false,
          );
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      await c.join(roomId);
      await c.toggleMicrophone();
      expect(audio.micEnabled, isTrue);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(audio.micEnabled, isTrue);
      api.allowed = false;
      api.version++;
      await c.tick();
      expect(audio.micEnabled, isFalse);
      expect(c.active, isNotNull);
    },
  );
  test(
    'a permission result after minimizing cannot enable an untyped background microphone',
    () async {
      final api = RoomFakeApi()
            ..seat = 0
            ..allowed = true,
          mobile = FakeMobile(),
          a = await account(api, mobile),
          audio = FakeRoomAudio()
            ..canPublish = true
            ..micGate = Completer<void>(),
          c = VoiceRoomsController(
            accounts: a,
            audioFactory: () => audio,
            autoPoll: false,
          );
      addTearDown(() {
        c.dispose();
        a.dispose();
      });
      await c.join(roomId);
      final work = c.toggleMicrophone();
      await drain();
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      audio.micGate!.complete();
      await work;
      expect(audio.micEnabled, isFalse);
      expect(mobile.starts.where((s) => s['microphone'] == true), isEmpty);
    },
  );
  test(
    'notification actions require the account, session binding and a fresh live call',
    () async {
      final api = MobileCallApi()..resetCall(incoming: true),
          mobile = FakeMobile(),
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          device = FakeDevice()..allowed = true,
          push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await drain();
      await push.connect();
      await drain();
      expect(push.registeredBinding, 'session-binding');
      Map<String, dynamic> data({
        String? user,
        String binding = 'session-binding',
      }) => {
        'type': 'call',
        'action': 'decline',
        'callId': callId,
        'accountId': user ?? a.user!.id,
        'bindingId': binding,
      };
      mobile.emit(data(user: 'another-account'));
      await drain();
      mobile.emit(data(binding: 'previous-session'));
      await drain();
      expect(
        api.requests.where((r) => r['path'].toString().endsWith('/decline')),
        isEmpty,
      );
      api.failRead = true;
      mobile.emit(data());
      await drain();
      expect(
        api.requests.where((r) => r['path'].toString().endsWith('/decline')),
        isEmpty,
      );
      api.failRead = false;
      mobile.emit(data());
      await drain();
      expect(
        api.requests
            .where((r) => r['path'].toString().endsWith('/decline'))
            .length,
        1,
      );
      expect(media.prepared, isFalse);
    },
  );
  test('an expired ring action cannot start capture', () async {
    final api = MobileCallApi()..resetCall(incoming: true),
        mobile = FakeMobile(),
        media = FakeCallMedia(),
        a = await account(api, mobile, media: media),
        device = FakeDevice()..allowed = true,
        push = PushController(accounts: a, client: device);
    addTearDown(() async {
      push.dispose();
      a.dispose();
      await device.close();
    });
    await drain();
    await push.connect();
    await drain();
    api.call['state'] = 'ended';
    mobile.emit({
      'type': 'call',
      'action': 'answer',
      'callId': callId,
      'accountId': a.user!.id,
      'bindingId': 'session-binding',
    });
    await drain();
    expect(media.prepared, isFalse);
    expect(
      api.requests.where((r) => r['path'].toString().endsWith('/accept')),
      isEmpty,
    );
  });
  test(
    'an answer action fetches the live call and accepts once with explicit microphone preparation',
    () async {
      final api = MobileCallApi()..resetCall(incoming: true),
          mobile = FakeMobile(),
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          device = FakeDevice()..allowed = true,
          push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await drain();
      await push.connect();
      await drain();
      final data = {
        'type': 'call',
        'action': 'answer',
        'callId': callId,
        'accountId': a.user!.id,
        'bindingId': 'session-binding',
      };
      mobile.emit(data);
      await drain();
      mobile.emit(data);
      await drain();
      expect(media.prepared, isTrue);
      expect(
        api.requests
            .where((r) => r['path'].toString().endsWith('/accept'))
            .length,
        1,
      );
      expect(a.calls.backgroundAudio, isTrue);
      mobile.bus.add({
        'type': 'control',
        'action': 'end',
        'callId': callId,
        'accountId': a.user!.id,
      });
      await drain();
      expect(a.calls.active!.ended, isTrue);
      expect(media.disposed, isTrue);
    },
  );
  test(
    'a video permission finishing after screen lock rolls back to audio',
    () async {
      final api = CallFakeApi(),
          mobile = FakeMobile(),
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          c = a.calls;
      addTearDown(a.dispose);
      await c.start(threadId);
      api.call['state'] = 'connected';
      api.call['mediaChange'] = {
        'requestId': '55555555-5555-4555-8555-555555555555',
        'kind': 'video',
        'state': 'accepted',
        'revision': 1,
        'requestedByMe': true,
      };
      media.videoGate = Completer<void>();
      await c.tick();
      // apply() starts camera acquisition asynchronously while syncSignals sees
      // the same in-flight consent revision.
      await drain();
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      media.videoGate!.complete();
      await drain();
      expect(media.video, isFalse);
      expect(c.cameraOn, isFalse);
      expect(c.active!.ended, isFalse);
      expect(
        api.requests.where(
          (r) =>
              r['path'].toString().endsWith('/media-ready') &&
              (r['body'] as Map)['ready'] == true,
        ),
        isEmpty,
      );
    },
  );
  test(
    'native service loss ends the matching call but cannot end a newer session',
    () async {
      final api = MobileCallApi(),
          mobile = FakeMobile(),
          media = FakeCallMedia(),
          a = await account(api, mobile, media: media),
          device = FakeDevice(),
          push = PushController(accounts: a, client: device);
      addTearDown(() async {
        push.dispose();
        a.dispose();
        await device.close();
      });
      await a.calls.start(threadId);
      mobile.bus.add({
        'type': 'audioStopped',
        'callId': '44444444-4444-4444-8444-444444444444',
      });
      await drain();
      expect(a.calls.active!.ended, isFalse);
      mobile.bus.add({'type': 'audioStopped', 'callId': callId});
      await drain();
      expect(a.calls.active!.ended, isTrue);
    },
  );
}
