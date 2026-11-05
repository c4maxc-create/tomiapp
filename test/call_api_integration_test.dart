import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/calling/call_controller.dart';
import 'account_fakes.dart';
import 'calls_test.dart' show FakeCallMedia;

class LoopbackNetwork extends HttpOverrides {}

class LocalBridge extends http.BaseClient {
  LocalBridge(this.base);
  final Uri base;
  final inner = IOClient(LoopbackNetwork().createHttpClient(null));
  @override
  Future<http.StreamedResponse> send(http.BaseRequest source) async {
    final request = http.Request(
      source.method,
      base
          .resolve(source.url.path)
          .replace(query: source.url.hasQuery ? source.url.query : null),
    );
    request.headers.addAll(source.headers);
    request.bodyBytes = await source.finalize().toBytes();
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'two call controllers complete offer answer ICE and hangup through the real Node API',
    () async {
      final child = await Process.start('node', [
        'server/test/fixtures/calls-client-api.mjs',
      ]);
      final errors = StringBuffer();
      final stderr = child.stderr.transform(utf8.decoder).listen(errors.write);
      addTearDown(() async {
        child.kill(ProcessSignal.sigterm);
        await child.exitCode.timeout(const Duration(seconds: 10));
        await stderr.cancel();
      });
      final first = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 20));
      final d = jsonDecode(first) as Map<String, dynamic>,
          base = Uri.parse(d['base'] as String),
          users = d['users'] as List;
      Future<AccountController> account(int i) async {
        final a = AccountController(
          api: AccountApi(
            'https://contract.tomi.test',
            client: LocalBridge(base),
          ),
          vault: MemoryTokenVault((users[i] as Map)['token'] as String),
          realtimeEnabled: false,
        );
        await a.restore();
        expect(a.phase, AccountPhase.signedIn);
        return a;
      }

      final a = await account(0),
          b = await account(1),
          ma = FakeCallMedia(),
          mb = FakeCallMedia();
      final mediaA = [ma], mediaB = [mb];
      final ca = CallController(
            accounts: a,
            mediaFactory: () => mediaA.last,
            autoPoll: false,
          ),
          cb = CallController(
            accounts: b,
            mediaFactory: () => mediaB.last,
            autoPoll: false,
          );
      addTearDown(() async {
        ca.dispose();
        cb.dispose();
        await ca.releaseTail;
        await cb.releaseTail;
        a.dispose();
        b.dispose();
      });
      final conversation = await a.chatRequest(
        'POST',
        '/v1/chats',
        body: {'userId': b.user!.id},
      );
      await ca.start((conversation['conversation'] as Map)['id'] as String);
      await ca.signalTail;
      expect(ca.error, isNull);
      expect(ca.active!.state, 'ringing');
      await cb.tick();
      expect(cb.active!.incoming, isTrue);
      expect(mb.prepared, isFalse);
      await cb.accept();
      await cb.signalTail;
      expect(cb.error, isNull);
      expect(mb.received, ['offer', 'candidate']);
      await ca.tick();
      expect(ca.error, isNull);
      expect(ma.received, ['answer', 'candidate']);
      ma.bus.add({'type': 'connected'});
      mb.bus.add({'type': 'connected'});
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (ca.active?.state == 'connected' || cb.active?.state == 'connected')
          break;
      }
      await ca.tick();
      await cb.tick();
      expect(ca.active!.state, 'connected');
      expect(cb.active!.state, 'connected');
      final connectedAt = ca.active!.connectedAt;
      // The original callee requests the first upgrade: roles must reverse
      // for this offer/answer round without restarting the audio connection.
      await cb.changeKind(true);
      await ca.tick();
      expect(ma.videoStarts, 0);
      expect(mb.videoStarts, 0);
      expect(ca.active!.mediaChange!.requestedByMe, isFalse);
      await ca.respondToVideo(true);
      for (var i = 0; i < 16; i++) {
        await ca.tick();
        await cb.tick();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (ca.active!.mediaChange!.state == 'applied' &&
            cb.active!.mediaChange!.state == 'applied')
          break;
      }
      expect(ca.active!.mediaChange!.state, 'applied');
      expect(cb.active!.mediaChange!.state, 'applied');
      expect(ca.active!.video, isTrue);
      expect(cb.active!.video, isTrue);
      expect(ma.videoStarts, 1);
      expect(mb.videoStarts, 1);
      expect(ca.active!.connectedAt, connectedAt);
      await ca.changeKind(false);
      await cb.tick();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ca.active!.video, isFalse);
      expect(cb.active!.video, isFalse);
      expect(ma.video, isFalse);
      expect(mb.video, isFalse);
      // Returning to video prompts again; declining must keep audio alive.
      await ca.changeKind(true);
      await cb.tick();
      expect(cb.active!.mediaChange!.pending, isTrue);
      await cb.respondToVideo(false);
      await ca.tick();
      expect(ca.active!.state, 'connected');
      expect(ca.active!.video, isFalse);
      expect(ma.videoStarts, 1);
      await ca.hangup();
      await cb.tick();
      await ca.releaseTail;
      await cb.releaseTail;
      expect(cb.active!.ended, isTrue);
      expect(ma.disposed, isTrue);
      expect(mb.disposed, isTrue);
      final history = await b.chatRequest('GET', '/v1/calls');
      expect((history['calls'] as List).length, 1);
      expect(((history['calls'] as List).first as Map)['reason'], 'ended');
      // Crossing start requests must preserve one caller and one answerer.
      final na = FakeCallMedia(), nb = FakeCallMedia();
      mediaA.add(na);
      mediaB.add(nb);
      final tid = (conversation['conversation'] as Map)['id'] as String;
      await Future.wait([ca.start(tid), cb.start(tid)]);
      for (var i = 0; i < 12; i++) {
        await ca.signalTail;
        await cb.signalTail;
        await ca.tick();
        await cb.tick();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ca.error, isNull);
      expect(cb.error, isNull);
      expect(ca.active!.id, cb.active!.id);
      expect(ca.active!.isCaller, !cb.active!.isCaller);
      expect(ca.active!.incoming, false);
      expect(cb.active!.incoming, false);
      expect(na.received, contains(ca.active!.isCaller ? 'answer' : 'offer'));
      expect(nb.received, contains(cb.active!.isCaller ? 'answer' : 'offer'));
      na.bus.add({'type': 'connected'});
      nb.bus.add({'type': 'connected'});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await ca.tick();
      await cb.tick();
      expect(ca.active!.state, 'connected');
      expect(cb.active!.state, 'connected');
      await ca.hangup();
      await cb.tick();
      final crossedHistory = await b.chatRequest('GET', '/v1/calls');
      expect((crossedHistory['calls'] as List).length, 2);
    },
    skip: Platform.environment['TOMI_CALL_INTEGRATION'] != '1',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
