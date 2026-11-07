import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/accounts/account_api.dart';
import 'package:tomi_app/src/accounts/account_controller.dart';
import 'package:tomi_app/src/messaging/draft_store.dart';
import 'package:tomi_app/src/privacy/deletion_controller.dart';
import 'package:tomi_app/src/privacy/privacy_screens.dart';
import 'account_fakes.dart';
import 'identity11_test.dart' show IdentityApi;
import 'room_features_test.dart' show roomApp;

class PrivacyApi extends IdentityApi {
  final receipts = <String, Map<String, dynamic>>{},
      sends = <Map<String, dynamic>>[];
  final publicCalls = <String>[];
  bool dropAck = false;
  int applied = 0;
  Completer<void>? replyGate;
  Map<String, dynamic> currentPerson = accountJson();
  @override
  Map<String, dynamic> get person => currentPerson;
  @override
  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (path == '/v1/me/auth/methods') return {'hasPassword': true};
    if (path == '/v1/account/deletion/preview')
      return {'canDelete': true, 'ownerTransferRequired': false};
    if (path == '/v1/account/deletion') {
      sends.add({...body!});
      final id = body['requestId'] as String;
      await replyGate?.future;
      receipts.putIfAbsent(id, () {
        applied++;
        return {
          'requestId': id,
          'accepted': true,
          'personalDataErased': true,
          'state': 'completed',
          'pendingMedia': 0,
          'pendingVoice': 0,
          'message': 'اكتمل حذف بيانات الحساب',
          'receiptExpiresAt': '2026-11-17T00:00:00Z',
        };
      });
      if (dropAck) {
        dropAck = false;
        throw const AccountFailure('NETWORK', 'انقطع التأكيد');
      }
      return receipts[id]!;
    }
    return super.chatRequest(token, method, path, body: body, query: query);
  }

  @override
  Future<Map<String, dynamic>> publicRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    publicCalls.add(path);
    if (path == '/v1/account/deletion/status') {
      final result = receipts[body!['requestId']];
      if (result == null)
        throw const AccountFailure(
          'DELETION_RECEIPT_MISSING',
          'الطلب غير موجود',
          status: 404,
        );
      return result;
    }
    if (path == '/v1/privacy/documents')
      return {
        'version': '2026-10-23',
        'publicationReady': false,
        'documents': [
          for (final title in [
            'سياسة الخصوصية',
            'شروط الاستخدام',
            'قواعد المجتمع',
            'حذف الحساب',
          ])
            {
              'title': title,
              'sections': [
                {'title': 'تفاصيل', 'text': 'وثيقة اختبار خصوصية واضحة'},
              ],
            },
        ],
      };
    throw const AccountFailure('NOT_FOUND', 'المسار غير موجود', status: 404);
  }
}

class FailedReceiptStore extends MemoryDraftStore {
  @override
  Future<bool> write(
    String owner,
    String scope,
    Map<String, dynamic>? data, {
    Map<String, Uint8List> blobs = const {},
    bool Function()? valid,
  }) async {
    throw const DraftStorageFailure('test-only storage failure');
  }
}

class OneFailedVaultClear extends MemoryTokenVault {
  OneFailedVaultClear() : super('old-session');
  bool fail = true;
  @override
  Future<void> clear() async {
    if (fail) {
      fail = false;
      throw StateError('test-only vault failure');
    }
    await super.clear();
  }
}

class PausedReceiptStore extends MemoryDraftStore {
  final entered = Completer<void>(), gate = Completer<void>();
  @override
  Future<bool> write(
    String owner,
    String scope,
    Map<String, dynamic>? data, {
    Map<String, Uint8List> blobs = const {},
    bool Function()? valid,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return super.write(owner, scope, data, blobs: blobs, valid: valid);
  }
}

Future<AccountController> account(
  PrivacyApi api,
  MemoryTokenVault vault,
  DraftStore store,
) async {
  final a = AccountController(
    api: api,
    vault: vault,
    draftStore: store,
    realtimeEnabled: false,
  );
  await a.restore();
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'accepted deletion retries failed local vault and draft cleanup using the original session fence',
    () async {
      final api = PrivacyApi(),
          store = MemoryDraftStore(),
          vault = OneFailedVaultClear(),
          a = await account(api, vault, store);
      addTearDown(a.dispose);
      final owner = a.draftOwnerId!, c = AccountDeletionController(a);
      addTearDown(c.dispose);
      await c.restore();
      await store.write(owner, 'chat', {'text': 'private draft'});
      await c.send('secret', 'حذف حسابي');
      expect(c.accepted, true);
      expect(a.user, isNull);
      expect(c.localError, isNotNull);
      expect(vault.token, 'old-session');
      await c.cleanLocal();
      expect(c.localError, isNull);
      expect(vault.token, isNull);
      expect(await store.read(owner, 'chat'), isNull);
      expect(api.applied, 1);
    },
  );
  test(
    'deletion proof is persisted before send; lost ACK is checked after recreating the controller without a second delete',
    () async {
      final api = PrivacyApi()..dropAck = true,
          vault = MemoryTokenVault('old-session'),
          store = MemoryDraftStore();
      final a = await account(api, vault, store);
      addTearDown(a.dispose);
      final owner = a.draftOwnerId!;
      await store.write(owner, 'chat', {'text': 'private local draft'});
      final first = AccountDeletionController(a);
      await first.restore();
      await first.send('private test password', 'حذف حسابي');
      expect(api.applied, 1);
      expect(first.accepted, false);
      final saved = await store.read(first.receiptOwner, 'pending');
      expect(jsonEncode(saved).contains('private test password'), false);
      expect((saved!['receiptToken'] as String).length, 43);
      first.dispose();
      final resumed = AccountDeletionController(a);
      addTearDown(resumed.dispose);
      await resumed.restore();
      await resumed.check();
      expect(resumed.accepted, true);
      expect(api.sends.length, 1);
      expect(a.user, isNull);
      expect(vault.token, isNull);
      expect(await store.read(owner, 'chat'), isNull);
      expect(await store.read(resumed.receiptOwner, 'pending'), isNotNull);
    },
  );
  test('failed durable receipt write prevents irreversible HTTP', () async {
    final api = PrivacyApi(),
        a = await account(
          api,
          MemoryTokenVault('session'),
          FailedReceiptStore(),
        );
    addTearDown(a.dispose);
    final c = AccountDeletionController(a);
    addTearDown(c.dispose);
    await c.restore();
    await c.send('secret', 'حذف حسابي');
    expect(api.sends, isEmpty);
    expect(a.user, isNotNull);
    expect(c.error, isNotNull);
  });
  test(
    'logout while receipt storage waits cannot send a deletion against a changed session',
    () async {
      final api = PrivacyApi(),
          store = PausedReceiptStore(),
          a = await account(api, MemoryTokenVault('session'), store);
      addTearDown(a.dispose);
      final c = AccountDeletionController(a);
      addTearDown(c.dispose);
      await c.restore();
      final sending = c.send('secret', 'حذف حسابي');
      await store.entered.future;
      await a.logout();
      store.gate.complete();
      await sending;
      expect(api.sends, isEmpty);
      expect(c.error, isNotNull);
    },
  );
  test(
    'late accepted deletion clears only old-account drafts and never a newer login vault',
    () async {
      final api = PrivacyApi(),
          store = MemoryDraftStore(),
          vault = MemoryTokenVault('old-session'),
          a = await account(api, vault, store);
      addTearDown(a.dispose);
      final oldOwner = a.draftOwnerId!, c = AccountDeletionController(a);
      addTearDown(c.dispose);
      await c.restore();
      await store.write(oldOwner, 'chat', {'text': 'old private draft'});
      final gate = api.replyGate = Completer<void>(),
          sending = c.send('secret', 'حذف حسابي');
      while (api.sends.isEmpty) await Future<void>.delayed(Duration.zero);
      await a.logout();
      api.currentPerson = accountJson(
        id: '22222222-2222-4222-8222-222222222222',
        username: 'other',
      );
      vault.token = 'new-session';
      await a.restore();
      final newOwner = a.draftOwnerId!;
      await store.write(newOwner, 'chat', {'text': 'new private draft'});
      gate.complete();
      await sending;
      expect(c.accepted, true);
      expect(a.user!.username, 'other');
      expect(vault.token, 'new-session');
      expect(await store.read(oldOwner, 'chat'), isNull);
      expect(
        (await store.read(newOwner, 'chat'))!['text'],
        'new private draft',
      );
    },
  );
  test(
    'disk erasure removes account metadata and blobs while preserving another account',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tomi-erasure-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileDraftStore(directory: () async => directory),
          one = draftOwner('origin', 'one'),
          two = draftOwner('origin', 'two');
      final blob = Uint8List.fromList([1, 2, 3]),
          key = sha256.convert(blob).toString();
      await store.write(one, 'draft', {'mediaKey': key}, blobs: {key: blob});
      await store.write(two, 'draft', {'text': 'preserved'});
      await store.erase(one);
      expect(await store.read(one, 'draft'), isNull);
      expect((await store.list(one)).isEmpty, true);
      expect((await store.read(two, 'draft'))!['text'], 'preserved');
      await expectLater(
        store.bytes(one, key),
        throwsA(isA<DraftStorageFailure>()),
      );
    },
  );
  testWidgets(
    'Arabic privacy and irreversible deletion controls fit a small enlarged-text display',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PrivacyApi(),
          a = await account(
            api,
            MemoryTokenVault('session'),
            MemoryDraftStore(),
          );
      addTearDown(a.dispose);
      await tester.pumpWidget(
        roomApp(PrivacyCenterPage(accounts: a), scale: 1.4),
      );
      await tester.pumpAndSettle();
      expect(find.text('سياسة الخصوصية'), findsOneWidget);
      final open = find.byKey(const Key('open-account-deletion'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      final pass = find.byKey(const Key('deletion-password')),
          confirm = find.byKey(const Key('deletion-confirmation'));
      await tester.ensureVisible(pass);
      await tester.enterText(pass, 'test password');
      await tester.ensureVisible(confirm);
      await tester.enterText(confirm, 'حذف حسابي');
      final send = find.byKey(const Key('send-account-deletion'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(api.applied, 1);
      expect(a.user, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'signed-out users can read policies and open deletion tracking without sending credentials',
    (tester) async {
      final api = PrivacyApi(),
          a = await account(api, MemoryTokenVault(), MemoryDraftStore());
      addTearDown(a.dispose);
      await tester.pumpWidget(roomApp(PrivacyCenterPage(accounts: a)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-account-deletion')), findsOneWidget);
      expect(api.sends, isEmpty);
      expect(api.publicCalls, ['/v1/privacy/documents']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
