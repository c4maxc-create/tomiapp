import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/security/secure_store.dart';
import 'account_fakes.dart';

void main() {
  test(
    '42 actual native Olm clients exchange ciphertext through the API, survive local reload and preserve an exact retry',
    () async {
      final process = await Process.start('node', [
        'server/test/fixtures/e2ee-client-api.mjs',
      ]);
      final seed =
          (jsonDecode(
                    await process.stdout
                        .transform(utf8.decoder)
                        .transform(const LineSplitter())
                        .first,
                  )
                  as Map)
              .cast<String, dynamic>();
      final directory = await Directory.systemTemp.createTemp(
        'tomi-secure-test-',
      );
      final real = http.Client();
      addTearDown(() async {
        process.stdin.writeln('stop');
        await process.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            process.kill();
            return 1;
          },
        );
        real.close();
        await directory.delete(recursive: true);
      });
      var dropAck = false;
      final observed = <Map<String, dynamic>>[];
      Future<http.Response> route(http.Request r) async {
        final target = Uri.parse(
          '${seed['url']}${r.url.path}',
        ).replace(query: r.url.hasQuery ? r.url.query : null);
        final request = http.Request(r.method, target)
          ..headers.addAll(r.headers)
          ..bodyBytes = r.bodyBytes;
        final response = await http.Response.fromStream(
          await real.send(request),
        );
        if (r.url.path.endsWith('/secure/messages') && r.method == 'POST') {
          observed.add((jsonDecode(r.body) as Map).cast<String, dynamic>());
          if (dropAck) {
            dropAck = false;
            throw http.ClientException('test lost acknowledgement');
          }
        }
        return response;
      }

      Future<AccountController> account(Map row) async {
        final a = AccountController(
          realtimeEnabled: false,
          vault: MemoryTokenVault(row['token'] as String),
          api: AccountApi(
            'https://secure.example.test',
            client: MockClient(route),
          ),
        );
        addTearDown(a.dispose);
        await a.restore();
        return a;
      }

      final a = await account(seed['a'] as Map),
          b = await account(seed['b'] as Map);
      final keysA = <String, String>{}, keysB = <String, String>{};
      SecureStore store(
        AccountController account,
        String folder,
        Map<String, String> keys,
      ) => SecureStore.forTesting(
        account,
        supportDirectory: Directory('${directory.path}/$folder'),
        readKey: (k) async => keys[k],
        writeKey: (k, v) async {
          keys[k] = v;
        },
      );
      final alice = store(a, 'a', keysA),
          bob = store(b, 'b', keysB),
          tid = seed['thread'] as String,
          pw = seed['password'] as String;
      await alice.enroll({'password': pw});
      await bob.enroll({'password': pw});
      expect((await alice.status())['registered'], true);
      final roster = await alice.roster(tid);
      await alice.trust(tid, roster);
      await bob.trust(tid, await bob.roster(tid));
      await alice.enable(tid);
      const text = 'رسالة خاصة لا يجب أن يقرأها الخادم';
      dropAck = true;
      await expectLater(alice.send(tid, text), throwsA(isA<AccountFailure>()));
      await alice.retry(tid);
      expect(jsonEncode(observed[0]), jsonEncode(observed[1]));
      expect(jsonEncode(observed), isNot(contains(text)));
      var received = await bob.sync(tid);
      expect((received['messages'] as List).single['payload']['text'], text);
      await bob.send(tid, 'رد مشفر');
      received = await alice.sync(tid);
      expect((received['messages'] as List).last['payload']['text'], 'رد مشفر');
      final plain = await a.chatRequest('GET', '/v1/chats/$tid/messages');
      expect(jsonEncode(plain), isNot(contains(text)));
      expect(jsonEncode(plain), contains('رسالة مشفرة'));
      final reloaded = store(b, 'b', keysB);
      expect(
        ((await reloaded.sync(tid))['messages'] as List)
            .first['payload']['text'],
        text,
      );
      final disk = await Directory(
        '${directory.path}/b',
      ).list(recursive: true).where((e) => e is File).cast<File>().first;
      expect(await disk.readAsString(), isNot(contains(text)));
      await expectLater(
        a.chatRequest(
          'POST',
          '/v1/chats/$tid/messages',
          body: {'text': 'plaintext rejected', 'requestId': secureUuid()},
        ),
        throwsA(
          isA<AccountFailure>().having(
            (e) => e.code,
            'code',
            'SECURE_REQUIRED',
          ),
        ),
      );
      final backup = await alice.exportHistory(
        'independent encrypted history passphrase',
      );
      await expectLater(
        bob.importHistory(backup, 'independent encrypted history passphrase'),
        throwsA(isA<AccountFailure>()),
      );
      final a2 = await account(seed['a2'] as Map);
      final secondAlice = store(a2, 'a2', <String, String>{});
      await secondAlice.enroll({'password': pw});
      await expectLater(
        alice.send(tid, 'must require trust'),
        throwsA(isA<SecureTrustRequired>()),
      );
      await alice.trust(tid, await alice.roster(tid));
      await bob.trust(tid, await bob.roster(tid));
      await secondAlice.trust(tid, await secondAlice.roster(tid));
      final beforeRestore = await secondAlice.sync(tid);
      expect((beforeRestore['messages'] as List).first['unavailable'], true);
      await secondAlice.importHistory(
        backup,
        'independent encrypted history passphrase',
      );
      expect(
        ((await secondAlice.sync(tid))['messages'] as List)
            .first['payload']['text'],
        text,
      );
      await bob.send(tid, 'available on both Alice devices');
      for (final client in [alice, secondAlice]) {
        expect(
          ((await client.sync(tid))['messages'] as List)
              .last['payload']['text'],
          'available on both Alice devices',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
