import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';

import 'account_fakes.dart';

http.Response reply(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('stored session restores the server profile; the token is scoped to the API', () async {
    final vault = MemoryTokenVault('saved-token');
    final api = AccountApi(
      'https://accounts.example',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/me');
        expect(request.headers['authorization'], 'Bearer saved-token');
        return reply({
          'user': accountJson(username: 'stored_user', name: 'اسم محفوظ'),
        });
      }),
    );
    final accounts = AccountController(
      realtimeEnabled: false,
      api: api,
      vault: vault,
    );
    addTearDown(accounts.dispose);
    await accounts.restore();
    expect(accounts.phase, AccountPhase.signedIn);
    expect(accounts.user!.username, 'stored_user');
    expect(accounts.user!.displayName, 'اسم محفوظ');
  });

  test('network failure keeps the session and retry restores it', () async {
    var offline = true;
    final vault = MemoryTokenVault('still-valid');
    final accounts = AccountController(
      realtimeEnabled: false,
      vault: vault,
      api: AccountApi(
        'https://accounts.example',
        client: MockClient((_) async {
          if (offline) throw http.ClientException('offline');
          return reply({'user': accountJson()});
        }),
      ),
    );
    addTearDown(accounts.dispose);
    await accounts.restore();
    expect(accounts.phase, AccountPhase.connectionError);
    expect(vault.token, 'still-valid');
    offline = false;
    await accounts.restore();
    expect(accounts.phase, AccountPhase.signedIn);
  });

  test('expired session clears secure storage and returns to login', () async {
    final vault = MemoryTokenVault('expired');
    final accounts = AccountController(
      realtimeEnabled: false,
      vault: vault,
      api: AccountApi(
        'https://accounts.example',
        client: MockClient(
          (_) async => reply({
            'error': {'code': 'UNAUTHORIZED', 'message': 'انتهت الجلسة'},
          }, 401),
        ),
      ),
    );
    addTearDown(accounts.dispose);
    await accounts.restore();
    expect(accounts.phase, AccountPhase.signedOut);
    expect(vault.token, isNull);
    expect(accounts.user, isNull);
  });

  test('registration persists the session, preserves passphrase spaces and exposes recovery once', () async {
    final vault = MemoryTokenVault();
    final accounts = AccountController(
      realtimeEnabled: false,
      vault: vault,
      api: AccountApi(
        'https://accounts.example',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/auth/register');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['password'], ' a long passphrase with spaces ');
          return reply({
            'token': 'new-token',
            'user': accountJson(),
            'recoveryCode': 'PRIVATE-CODE',
          }, 201);
        }),
      ),
    );
    addTearDown(accounts.dispose);
    await accounts.register('tolo', 'تولو', ' a long passphrase with spaces ');
    expect(accounts.phase, AccountPhase.signedIn);
    expect(vault.token, 'new-token');
    expect(accounts.pendingRecoveryCode, 'PRIVATE-CODE');
    accounts.acknowledgeRecoveryCode();
    expect(accounts.pendingRecoveryCode, isNull);
  });

  test('follow response updates own counts using server data', () async {
    final accounts = AccountController(
      realtimeEnabled: false,
      vault: MemoryTokenVault('token'),
      api: AccountApi(
        'https://accounts.example',
        client: MockClient((request) async {
          if (request.method == 'GET') return reply({'user': accountJson()});
          expect(request.method, 'PUT');
          expect(jsonDecode(request.body)['follow'], true);
          return reply({
            'user': accountJson(
              id: 'other',
              username: 'ali',
              followers: 1,
              isFollowing: true,
            ),
            'me': accountJson(following: 1),
          });
        }),
      ),
    );
    addTearDown(accounts.dispose);
    await accounts.restore();
    final target = await accounts.follow('other', true);
    expect(target.isFollowing, isTrue);
    expect(accounts.user!.followingCount, 1);
  });

  test('logout revokes the session before clearing storage; late search cannot restore it', () async {
    final response = Completer<http.Response>();
    final vault = MemoryTokenVault('token');
    final accounts = AccountController(
      realtimeEnabled: false,
      vault: vault,
      api: AccountApi(
        'https://accounts.example',
        client: MockClient((request) async {
          if (request.url.path == '/v1/me')
            return reply({'user': accountJson()});
          if (request.url.path == '/v1/users') return response.future;
          expect(request.url.path, '/v1/auth/logout');
          expect(vault.token, 'token');
          return reply({'ok': true});
        }),
      ),
    );
    addTearDown(accounts.dispose);
    await accounts.restore();
    final search = accounts.search('ali');
    final expected = expectLater(search, throwsA(isA<AccountFailure>()));
    await accounts.logout();
    response.complete(
      reply({
        'users': [accountJson(username: 'ali')],
      }),
    );
    await expected;
    expect(vault.token, isNull);
    expect(accounts.user, isNull);
    expect(accounts.phase, AccountPhase.signedOut);
  });

  test(
    'logout failure keeps the valid session so revocation can be retried',
    () async {
      final vault = MemoryTokenVault('token');
      final accounts = AccountController(
        realtimeEnabled: false,
        vault: vault,
        api: AccountApi(
          'https://accounts.example',
          client: MockClient((request) async {
            if (request.url.path == '/v1/me')
              return reply({'user': accountJson()});
            throw http.ClientException('offline');
          }),
        ),
      );
      addTearDown(accounts.dispose);
      await accounts.restore();
      await expectLater(accounts.logout(), throwsA(isA<AccountFailure>()));
      expect(vault.token, 'token');
      expect(accounts.phase, AccountPhase.signedIn);
    },
  );

  test('API refuses cleartext endpoints and credentials in URLs', () {
    expect(() => AccountApi('http://accounts.example'), throwsArgumentError);
    expect(
      () => AccountApi('https://user:password@accounts.example'),
      throwsArgumentError,
    );
    expect(
      () => AccountApi('https://accounts.example?token=secret'),
      throwsArgumentError,
    );
  });
}
