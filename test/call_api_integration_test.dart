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
      final ca = CallController(
            accounts: a,
            mediaFactory: () => ma,
            autoPoll: false,
          ),
          cb = CallController(
            accounts: b,
            mediaFactory: () => mb,
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
    },
    skip: Platform.environment['TOMI_CALL_INTEGRATION'] != '1',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
