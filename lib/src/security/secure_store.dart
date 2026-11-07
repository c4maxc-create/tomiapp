import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tomi_secure/tomi_secure.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';

String secureUuid() {
  final b = List.generate(16, (_) => Random.secure().nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class SecureTrustRequired implements Exception {
  const SecureTrustRequired();
}

class SecureStore {
  SecureStore._(this.accounts)
    : user = accounts.user!.id,
      revision = accounts.sessionRevision {
    accounts.addListener(changed);
  }
  SecureStore.forTesting(
    this.accounts, {
    required Directory supportDirectory,
    required Future<String?> Function(String) readKey,
    required Future<void> Function(String, String) writeKey,
  }) : user = accounts.user!.id,
       revision = accounts.sessionRevision {
    _supportOverride = supportDirectory;
    _readKey = readKey;
    _writeKey = writeKey;
    accounts.addListener(changed);
  }
  Directory? _supportOverride;
  Future<String?> Function(String)? _readKey;
  Future<void> Function(String, String)? _writeKey;
  static final Map<String, SecureStore> _instances = {};
  static final Map<String, Future<void>> _queues = {};
  static SecureStore forAccount(AccountController a) {
    final key = '${a.api.baseUrl}|${a.user!.id}|${a.sessionRevision}';
    return _instances.putIfAbsent(key, () => SecureStore._(a));
  }

  final AccountController accounts;
  final String user;
  final int revision;
  Map<String, dynamic>? _state, _checkpoint;
  String? _master;
  Directory? _root;
  final _vault = const FlutterSecureStorage();
  String get _scope =>
      sha256.convert(utf8.encode('${accounts.api.baseUrl}|$user')).toString();
  String get deviceId => _state?['device'] as String? ?? '';
  bool get supported => NativeCrypto.supported;
  void changed() {
    if (accounts.user?.id != user || accounts.sessionRevision != revision) {
      accounts.removeListener(changed);
      _state = null;
      _checkpoint = null;
      _master = null;
      _instances.removeWhere((k, v) => identical(v, this));
    }
  }

  void check() {
    if (accounts.user?.id != user ||
        accounts.sessionRevision != revision ||
        accounts.phase != AccountPhase.signedIn)
      throw const AccountFailure('SESSION_CHANGED', 'تغيّرت الجلسة.');
  }

  Future<T> locked<T>(Future<T> Function() work) {
    final c = Completer<T>();
    final q = (_queues[_scope] ?? Future<void>.value()).catchError((_) {}).then(
      (_) async {
        try {
          check();
          await load();
          final value = await work();
          check();
          c.complete(value);
        } catch (e, st) {
          if (_checkpoint != null)
            _state = (jsonDecode(jsonEncode(_checkpoint)) as Map)
                .cast<String, dynamic>();
          c.completeError(e, st);
        }
      },
    );
    _queues[_scope] = q;
    return c.future;
  }

  Future<Map<String, dynamic>> crypto(
    String op, [
    Map<String, dynamic> data = const {},
  ]) async {
    check();
    final r = await NativeCrypto.run({
      'op': op,
      if (_state?['pickleKey'] != null) 'key': _state!['pickleKey'],
      ...data,
    });
    check();
    return r;
  }

  Future<void> load() async {
    if (_state != null) return;
    if (!supported)
      throw const AccountFailure(
        'SECURE_PLATFORM',
        'هذه النسخة لا تدعم التشفير الأصلي.',
      );
    final support = _supportOverride ?? await getApplicationSupportDirectory();
    check();
    _root = Directory('${support.path}/tomi-secure/$_scope');
    await _root!.create(recursive: true);
    await for (final entry in _root!.list(followLinks: false)) {
      if (entry is File) {
        final name = entry.uri.pathSegments.last;
        if (name.startsWith('view-') ||
            name.startsWith('download-') ||
            name.startsWith('file-') ||
            name.endsWith('.tmp'))
          await entry.delete();
      }
    }
    final file = File('${_root!.path}/state.enc');
    _master = _readKey == null
        ? await _vault.read(key: 'tomi.secure.master.$_scope')
        : await _readKey!('tomi.secure.master.$_scope');
    check();
    if (await file.exists()) {
      if (_master == null)
        throw const AccountFailure(
          'SECURE_KEY_LOST',
          'مفتاح التخزين المحلي غير متاح؛ لا نستبدله تلقائياً. استعد نسخة السجل أو أعد تسجيل جهاز جديد.',
        );
      final r = await NativeCrypto.run({
        'op': 'open',
        'key': _master,
        'aad': 'TOMI_LOCAL_V1|$user|$_scope',
        'data': await file.readAsString(),
      });
      check();
      _state =
          (jsonDecode(utf8.decode(base64Decode(r['data'] as String))) as Map)
              .cast<String, dynamic>();
      if (_state!['user'] != user || _state!['v'] != 1)
        throw const AccountFailure('SECURE_STATE', 'سجل التشفير غير مطابق.');
    } else {
      _master ??= (await NativeCrypto.run({'op': 'random'}))['key'] as String;
      if (_writeKey == null) {
        await _vault.write(key: 'tomi.secure.master.$_scope', value: _master);
      } else {
        await _writeKey!('tomi.secure.master.$_scope', _master!);
      }
      check();
      final key = (await NativeCrypto.run({'op': 'random'}))['key'] as String,
          archive = (await NativeCrypto.run({'op': 'random'}))['key'] as String,
          id = secureUuid();
      final a = await NativeCrypto.run({
        'op': 'new',
        'key': key,
        'user': user,
        'device': id,
      });
      check();
      _state = {
        'v': 1,
        'user': user,
        'device': id,
        'pickleKey': key,
        'archiveKey': archive,
        'account': a['account'],
        'signingKey': a['signingKey'],
        'identityKey': a['identityKey'],
        'pendingKeys': a['prekeys'],
        'pendingFallback': a['fallback'],
        'sessions': <String, dynamic>{},
        'trusted': <String, dynamic>{},
        'trustedRosters': <String, dynamic>{},
        'messages': <String, dynamic>{},
        'cursors': <String, dynamic>{},
        'outbox': <String, dynamic>{},
      };
      await persist();
    }
    _checkpoint = (jsonDecode(jsonEncode(_state)) as Map)
        .cast<String, dynamic>();
  }

  Future<void> persist() async {
    check();
    final bytes = utf8.encode(jsonEncode(_state));
    if (bytes.length > 24 * 1024 * 1024)
      throw const AccountFailure(
        'SECURE_STORAGE_FULL',
        'سجل التشفير المحلي كبير؛ صدّر نسخة قبل إدارة السجل.',
      );
    final encrypted = await NativeCrypto.run({
      'op': 'seal',
      'key': _master,
      'aad': 'TOMI_LOCAL_V1|$user|$_scope',
      'data': base64Encode(bytes),
    });
    check();
    await NativeCrypto.run({
      'op': 'save_state',
      'path': '${_root!.path}/state.enc',
      'data': encrypted['data'],
    });
    check();
    _checkpoint = (jsonDecode(jsonEncode(_state)) as Map)
        .cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    check();
    final r = await accounts.chatRequest(
      method,
      path,
      body: body,
      query: query,
    );
    check();
    return r;
  }

  Future<Map<String, dynamic>> status() => locked(() async {
    final d = await request('GET', '/v1/me/secure/devices');
    final rows = (d['devices'] as List).cast<Map>();
    return {
      'registered': rows.any(
        (r) =>
            r['id'] == deviceId && r['current'] == true && r['revoked'] != true,
      ),
      'deviceId': deviceId,
      'devices': rows,
    };
  });
  Future<void> enroll(Map<String, dynamic> credential) => locked(() async {
    final d = await request('POST', '/v1/me/secure/challenge', body: {}),
        nonce = d['challenge'] as String;
    final proof =
        'TOMI_DEVICE_V1|$user|$deviceId|${_state!['signingKey']}|${_state!['identityKey']}|$nonce';
    final signature = (await crypto('sign', {
      'account': _state!['account'],
      'data': proof,
    }))['signature'];
    await request(
      'POST',
      '/v1/me/secure/devices',
      body: {
        'id': deviceId,
        'signingKey': _state!['signingKey'],
        'identityKey': _state!['identityKey'],
        'label': Platform.isIOS ? 'TOMI iPhone' : 'TOMI Android',
        'challenge': nonce,
        'signature': signature,
        'prekeys': _state!['pendingKeys'] ?? [],
        'fallback': _state!['pendingFallback'],
        ...credential,
      },
    );
    _state!['pendingKeys'] = [];
    _state!['pendingFallback'] = null;
    await persist();
  });
  Future<Map<String, dynamic>> roster(String tid) => locked(() => _roster(tid));
  Future<Map<String, dynamic>> _roster(String tid) async {
    final d = await request('GET', '/v1/chats/$tid/secure/devices');
    final rows =
        (d['devices'] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final hash = sha256
        .convert(
          utf8.encode(
            jsonEncode(
              rows
                  .map(
                    (r) => [
                      r['id'],
                      r['userId'],
                      r['identityKey'],
                      r['signingKey'],
                    ],
                  )
                  .toList(),
            ),
          ),
        )
        .toString();
    if (hash != d['rosterHash'])
      throw const AccountFailure('SECURE_ROSTER', 'قائمة الأجهزة غير متطابقة.');
    final own = rows.where((r) => r['id'] == deviceId).firstOrNull;
    if (own != null &&
        (own['identityKey'] != _state!['identityKey'] ||
            own['signingKey'] != _state!['signingKey'] ||
            own['userId'] != user))
      throw const AccountFailure(
        'SECURE_IDENTITY',
        'هوية الجهاز المعروضة غير متطابقة.',
      );
    return {...d, 'devices': rows};
  }

  Future<void> trust(String tid, Map<String, dynamic> shown) =>
      locked(() async {
        final current = await _roster(tid);
        if (current['rosterHash'] != shown['rosterHash'])
          throw const SecureTrustRequired();
        final trusted = _state!['trusted'] as Map;
        for (final d in current['devices'] as List) {
          final values = [d['userId'], d['identityKey'], d['signingKey']],
              old = trusted[d['id']];
          if (old != null && jsonEncode(old) != jsonEncode(values))
            throw const AccountFailure(
              'SECURE_IDENTITY',
              'تغيرت مفاتيح جهاز معروف؛ أوقف الإرسال وراجع صاحب الحساب.',
            );
          trusted[d['id']] = values;
        }
        (_state!['trustedRosters'] as Map)[tid] = current['rosterHash'];
        await persist();
      });
  Future<void> enable(String tid) => locked(() async {
    final r = await _roster(tid);
    if ((_state!['trustedRosters'] as Map)[tid] != r['rosterHash'])
      throw const SecureTrustRequired();
    final signature = (await crypto('sign', {
      'account': _state!['account'],
      'data': 'TOMI_ENABLE_V1|$user|$deviceId|$tid|${r['rosterHash']}',
    }))['signature'];
    await request(
      'POST',
      '/v1/chats/$tid/secure/enable',
      body: {
        'deviceId': deviceId,
        'rosterHash': r['rosterHash'],
        'signature': signature,
      },
    );
  });
  List<Map<String, dynamic>> _sessions(String device) =>
      ((_state!['sessions'] as Map)[device] as List? ?? [])
          .map((v) => (v as Map).cast<String, dynamic>())
          .toList();
  void _session(String device, Map<String, dynamic> result) {
    final rows = _sessions(device)
      ..removeWhere((r) => r['id'] == result['sessionId']);
    rows.insert(0, {'id': result['sessionId'], 'pickle': result['session']});
    (_state!['sessions'] as Map)[device] = rows.take(8).toList();
  }

  Future<Map<String, dynamic>> _file(
    String tid,
    String req,
    XFile source,
  ) async {
    final size = await source.length();
    if (size > 24 * 1024 * 1024)
      throw const AccountFailure('SECURE_FILE_SIZE', 'حد الملف المشفر 24MB.');
    final k = (await crypto('random'))['key'] as String,
        aad = 'TOMI_FILE_V1|$tid|$req';
    final path = '${_root!.path}/file-${secureUuid()}.enc';
    await crypto('seal_file', {
      'key': k,
      'aad': aad,
      'source': source.path,
      'output': path,
    });
    final file = File(path);
    try {
      final hash = (await sha256.bind(file.openRead()).first).toString(),
          md5Value = (await md5.bind(file.openRead()).first).toString();
      final md5Bytes = [
        for (var i = 0; i < md5Value.length; i += 2)
          int.parse(md5Value.substring(i, i + 2), radix: 16),
      ];
      final prepared = await request(
        'POST',
        '/v1/chats/$tid/secure/uploads',
        body: {
          'deviceId': deviceId,
          'byteLength': await file.length(),
          'contentMd5': base64Encode(md5Bytes),
          'contentSha256': hash,
        },
      );
      final url = Uri.parse(prepared['uploadUrl'] as String);
      if (url.scheme != 'https' || url.userInfo.isNotEmpty)
        throw const AccountFailure('SECURE_UPLOAD', 'عنوان رفع غير آمن.');
      final client = http.Client();
      try {
        final upload = http.StreamedRequest('PUT', url)
          ..followRedirects = false
          ..contentLength = await file.length();
        upload.headers.addAll(
          (prepared['headers'] as Map).cast<String, String>(),
        );
        final reply = await (() async {
          final response = client.send(upload);
          await upload.sink.addStream(file.openRead());
          await upload.sink.close();
          final result = await response;
          await result.stream.drain<void>();
          return result;
        })().timeout(const Duration(minutes: 2));
        if (reply.statusCode < 200 || reply.statusCode >= 300)
          throw const AccountFailure(
            'SECURE_UPLOAD',
            'تعذّر رفع الملف المشفر.',
          );
      } finally {
        client.close();
      }
      check();
      return {
        'uploadId': prepared['uploadId'],
        'key': k,
        'aad': aad,
        'sha256': hash,
        'name': source.name
            .replaceAll(
              RegExp(r'[\\/\x00-\x1f\u202a-\u202e\u2066-\u2069]'),
              '_',
            )
            .substring(0, min(120, source.name.length)),
        'bytes': size,
      };
    } finally {
      await file.delete().catchError((_) => file);
    }
  }

  Future<void> send(String tid, String text, {XFile? file}) => locked(() async {
    if ((_state!['outbox'] as Map).containsKey(tid))
      throw const AccountFailure(
        'SECURE_PENDING',
        'أعد محاولة الإرسال المعلّق أولاً.',
      );
    if (text.trim().isEmpty && file == null) return;
    if (text.runes.length > 2000)
      throw const AccountFailure('SECURE_LENGTH', 'حد الرسالة 2000 حرف.');
    final r = await _roster(tid);
    if ((_state!['trustedRosters'] as Map)[tid] != r['rosterHash'])
      throw const SecureTrustRequired();
    final req = secureUuid();
    final attachment = file == null ? null : await _file(tid, req, file);
    final payload = {
      'v': 1,
      'threadId': tid,
      'requestId': req,
      'senderId': user,
      'senderDevice': deviceId,
      'rosterHash': r['rosterHash'],
      'text': text.trim(),
      'file': attachment,
    };
    final encoded = jsonEncode(payload), boxes = <Map<String, dynamic>>[];
    for (final d in r['devices'] as List) {
      final remote = d['id'] as String;
      if (remote == deviceId) {
        final b = await crypto('seal', {
          'key': _state!['archiveKey'],
          'aad': 'TOMI_ARCHIVE_V1|$tid|$req',
          'data': base64Encode(utf8.encode(encoded)),
        });
        boxes.add({'deviceId': remote, 'type': 2, 'body': b['data']});
        continue;
      }
      final sessions = _sessions(remote);
      String? prekey;
      if (sessions.isEmpty) {
        final nonce = secureUuid();
        final proof = 'TOMI_CLAIM_V1|$user|$deviceId|$tid|$remote|$nonce';
        final sig = (await crypto('sign', {
          'account': _state!['account'],
          'data': proof,
        }))['signature'];
        final p = await request(
          'POST',
          '/v1/chats/$tid/secure/claim/$remote',
          body: {'deviceId': deviceId, 'requestId': nonce, 'signature': sig},
        );
        await crypto('verify', {
          'publicKey': d['signingKey'],
          'signature': p['signature'],
          'data':
              'TOMI_PREKEY_V1|${d['userId']}|$remote|${p['id']}|${p['key']}',
        });
        prekey = p['key'] as String;
      }
      final encrypted = await crypto('encrypt', {
        'account': _state!['account'],
        'identity': d['identityKey'],
        if (prekey != null) 'prekey': prekey,
        if (sessions.isNotEmpty) 'session': sessions.first['pickle'],
        'plaintext': encoded,
      });
      _session(remote, encrypted);
      final m = encrypted['message'] as Map;
      boxes.add({'deviceId': remote, 'type': m['type'], 'body': m['body']});
    }
    boxes.sort(
      (a, b) => (a['deviceId'] as String).compareTo(b['deviceId'] as String),
    );
    final hash = sha256.convert(utf8.encode(jsonEncode(boxes))).toString();
    final signature = (await crypto('sign', {
      'account': _state!['account'],
      'data':
          'TOMI_PACKET_V1|$user|$deviceId|$tid|$req|${r['rosterHash']}|$hash',
    }))['signature'];
    final body = {
      'deviceId': deviceId,
      'requestId': req,
      'rosterHash': r['rosterHash'],
      'boxes': boxes,
      'signature': signature,
      if (attachment != null) 'uploadId': attachment['uploadId'],
    };
    (_state!['outbox'] as Map)[tid] = {'body': body, 'payload': payload};
    await persist();
    await _retry(tid);
  });
  Future<void> retry(String tid) => locked(() => _retry(tid));
  Future<void> discardPending(String tid) => locked(() async {
    // Never rewind ratchets: an earlier request may already have reached its peer.
    (_state!['outbox'] as Map).remove(tid);
    await persist();
  });
  Future<void> _retry(String tid) async {
    final pending = (_state!['outbox'] as Map)[tid] as Map?;
    if (pending == null) return;
    final response = await request(
      'POST',
      '/v1/chats/$tid/secure/messages',
      body: (pending['body'] as Map).cast<String, dynamic>(),
    );
    final rows =
        (_state!['messages'] as Map).putIfAbsent(tid, () => <String, dynamic>{})
            as Map;
    rows[response['id']] = {
      'id': response['id'],
      'sequence': response['sequence'],
      'senderId': user,
      'payload': pending['payload'],
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    (_state!['outbox'] as Map).remove(tid);
    await persist();
  }

  Future<List<Map<String, dynamic>>> snapshot(String tid) => locked(
    () async =>
        ((_state!['messages'] as Map)[tid] as Map? ?? {}).values
            .map((v) => (v as Map).cast<String, dynamic>())
            .toList()
          ..sort(
            (a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num),
          ),
  );
  Future<Map<String, dynamic>> sync(String tid) => locked(() async {
    final r = await _roster(tid);
    final trustChanged =
        (_state!['trustedRosters'] as Map)[tid] != r['rosterHash'];
    final rows =
        (_state!['messages'] as Map).putIfAbsent(tid, () => <String, dynamic>{})
            as Map;
    bool more = true;
    var batches = 0;
    while (more && batches++ < 10) {
      final data = await request(
        'GET',
        '/v1/chats/$tid/secure/messages',
        query: {
          'deviceId': deviceId,
          'after': '${(_state!['cursors'] as Map)[tid] ?? 0}',
        },
      );
      more = data['more'] == true;
      for (final raw in data['messages'] as List) {
        final m = (raw as Map).cast<String, dynamic>();
        final box = m['box'] as Map?;
        Map<String, dynamic>? payload;
        Map<String, dynamic>? decrypted;
        if (m['deleted'] == true) {
          rows[m['id']] = {...m, 'deleted': true};
        } else if (box == null) {
          rows.putIfAbsent(m['id'], () => {...m, 'unavailable': true});
        } else if (rows[m['id']]?['payload'] != null) {
          /* Already committed together with ratchet advancement. */
        } else {
          final trusted = (_state!['trusted'] as Map)[m['senderDevice']];
          if (trusted == null ||
              jsonEncode(trusted) !=
                  jsonEncode([
                    m['senderId'],
                    m['identityKey'],
                    m['signingKey'],
                  ]))
            throw const SecureTrustRequired();
          try {
            if (box['type'] == 2) {
              if (m['senderDevice'] != deviceId || m['senderId'] != user)
                throw const AccountFailure(
                  'SECURE_AUTH',
                  'غلاف الرسالة غير مطابق.',
                );
              final result = await crypto('open', {
                'key': _state!['archiveKey'],
                'aad': 'TOMI_ARCHIVE_V1|$tid|${m['requestId']}',
                'data': box['body'],
              });
              payload =
                  (jsonDecode(
                            utf8.decode(base64Decode(result['data'] as String)),
                          )
                          as Map)
                      .cast<String, dynamic>();
            } else {
              final sessions = _sessions(m['senderDevice'] as String);
              decrypted = await crypto('decrypt', {
                'account': _state!['account'],
                'identity': m['identityKey'],
                'sessions': sessions.map((s) => s['pickle']).toList(),
                'message': box,
              });
              payload = (jsonDecode(decrypted['plaintext'] as String) as Map)
                  .cast<String, dynamic>();
            }
            if (payload['v'] != 1 ||
                payload['threadId'] != tid ||
                payload['requestId'] != m['requestId'] ||
                payload['senderId'] != m['senderId'] ||
                payload['senderDevice'] != m['senderDevice'] ||
                payload['rosterHash'] != m['rosterHash'])
              throw const AccountFailure(
                'SECURE_CONTEXT',
                'فشل التحقق من سياق الرسالة؛ لم نعرض محتواها.',
              );
            if (payload['text'] is! String ||
                (payload['text'] as String).runes.length > 2000 ||
                (payload['file'] != null && payload['file'] is! Map)) {
              throw const FormatException('Invalid encrypted payload');
            }
            final f = payload['file'] as Map?;
            if (f != null) {
              if (f['name'] is! String ||
                  (f['name'] as String).length > 160 ||
                  f['bytes'] is! int ||
                  (f['bytes'] as int) < 0 ||
                  (f['bytes'] as int) > 24 * 1024 * 1024 ||
                  f['uploadId'] is! String ||
                  !RegExp(
                    r'^[a-f0-9-]{36}$',
                  ).hasMatch(f['uploadId'] as String) ||
                  f['key'] is! String ||
                  base64Decode(f['key'] as String).length != 32 ||
                  f['sha256'] is! String ||
                  !RegExp(r'^[a-f0-9]{64}$').hasMatch(f['sha256'] as String) ||
                  f['aad'] != 'TOMI_FILE_V1|$tid|${m['requestId']}') {
                throw const FormatException('Invalid encrypted attachment');
              }
            }
            if (decrypted != null) {
              _state!['account'] = decrypted['account'];
              _session(m['senderDevice'] as String, decrypted);
            }
            rows[m['id']] = {...m, 'payload': payload};
          } on SecureNativeException catch (e) {
            if (!const {
              'DECRYPT_FAILED',
              'BAD_MESSAGE',
              'BAD_UTF8',
              'BAD_CIPHERTEXT',
              'AUTHENTICATION_FAILED',
            }.contains(e.code))
              rethrow;
            rows[m['id']] = {...m, 'securityError': true};
          } on FormatException {
            rows[m['id']] = {...m, 'securityError': true};
          } on TypeError {
            rows[m['id']] = {...m, 'securityError': true};
          } on AccountFailure catch (e) {
            if (e.code != 'SECURE_CONTEXT') rethrow;
            rows[m['id']] = {...m, 'securityError': true};
          }
        }
        (_state!['cursors'] as Map)[tid] = m['sequence'];
        await persist();
      }
    }
    final sorted =
        rows.values.map((v) => (v as Map).cast<String, dynamic>()).toList()
          ..sort(
            (a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num),
          );
    if (sorted.isNotEmpty) {
      final ids = sorted.reversed.take(200).map((r) => r['id']).toList();
      final changes = await request(
        'POST',
        '/v1/chats/$tid/secure/status',
        body: {'deviceId': deviceId, 'ids': ids},
      );
      for (final id in changes['deletedIds'] as List? ?? []) {
        if (rows[id] != null)
          rows[id] = {
            'id': id,
            'sequence': rows[id]['sequence'],
            'senderId': rows[id]['senderId'],
            'deleted': true,
          };
      }
      await persist();
    }
    return {
      'messages':
          rows.values.map((v) => (v as Map).cast<String, dynamic>()).toList()
            ..sort(
              (a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num),
            ),
      'pending': (_state!['outbox'] as Map).containsKey(tid),
      'enabled': r['enabled'],
      'trustRequired': trustChanged,
    };
  });
  Future<File> decryptAttachment(
    String tid,
    Map<String, dynamic> attachment,
  ) => locked(() async {
    final info = await request(
      'GET',
      '/v1/chats/$tid/secure/uploads/${attachment['uploadId']}',
      query: {'deviceId': deviceId},
    );
    final uri = Uri.parse(info['url'] as String);
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty)
      throw const AccountFailure('SECURE_FILE', 'عنوان الملف غير آمن.');
    final encrypted = File('${_root!.path}/download-${secureUuid()}.enc'),
        client = http.Client();
    final sink = encrypted.openWrite();
    try {
      final req = http.Request('GET', uri)..followRedirects = false;
      final res = await client.send(req).timeout(const Duration(seconds: 45));
      if (res.statusCode != 200)
        throw const AccountFailure('SECURE_FILE', 'تعذّر تنزيل الملف.');
      var bytes = 0;
      await for (final part in res.stream.timeout(
        const Duration(seconds: 30),
      )) {
        bytes += part.length;
        if (bytes > 25 * 1024 * 1024 || bytes > (info['byteLength'] as num))
          throw const AccountFailure('SECURE_FILE', 'حجم الملف تغيّر.');
        sink.add(part);
      }
      await sink.close();
      final hash = (await sha256.bind(encrypted.openRead()).first).toString();
      if (hash != attachment['sha256'])
        throw const AccountFailure('SECURE_FILE', 'بصمة الملف غير مطابقة.');
      final raw = '${attachment['name']}'.replaceAll(
            RegExp(r'[\\/\x00-\x1f\u202a-\u202e\u2066-\u2069]'),
            '_',
          ),
          name = raw.isEmpty ? 'file' : raw.substring(0, min(120, raw.length));
      final out = File('${_root!.path}/view-${secureUuid()}-$name');
      await crypto('open_file', {
        'key': attachment['key'],
        'aad': attachment['aad'],
        'source': encrypted.path,
        'output': out.path,
      });
      return out;
    } finally {
      await sink.close().catchError((_) {});
      client.close();
      await encrypted.delete().catchError((_) => encrypted);
    }
  });
  Future<File> exportHistory(String password) => locked(() async {
    final data = base64Encode(
      utf8.encode(
        jsonEncode({'v': 1, 'user': user, 'messages': _state!['messages']}),
      ),
    );
    final result = await crypto('backup_export', {
      'password': password,
      'data': data,
      'aad': 'TOMI_HISTORY_V1|$user',
    });
    final output = File('${_root!.path}/history-${secureUuid()}.tomibak');
    await output.writeAsString(
      jsonEncode({'format': 'TOMI_E2EE_HISTORY1', 'user': user, ...result}),
      flush: true,
    );
    return output;
  });
  Future<void> importHistory(File file, String password) => locked(() async {
    if (await file.length() > 32 * 1024 * 1024)
      throw const AccountFailure('SECURE_BACKUP', 'النسخة أكبر من المسموح.');
    final d = jsonDecode(await file.readAsString()) as Map;
    if (d['format'] != 'TOMI_E2EE_HISTORY1' || d['user'] != user)
      throw const AccountFailure('SECURE_BACKUP', 'هذه النسخة تخص حساباً آخر.');
    final result = await crypto('backup_import', {
      'password': password,
      'salt': d['salt'],
      'data': d['data'],
      'aad': 'TOMI_HISTORY_V1|$user',
    });
    final recovered =
        jsonDecode(utf8.decode(base64Decode(result['data'] as String))) as Map;
    if (recovered['v'] != 1 || recovered['user'] != user)
      throw const AccountFailure('SECURE_BACKUP', 'نسخة غير مطابقة.');
    for (final entry in (recovered['messages'] as Map).entries) {
      final current =
          (_state!['messages'] as Map).putIfAbsent(
                entry.key,
                () => <String, dynamic>{},
              )
              as Map;
      for (final m in (entry.value as Map).entries) {
        final old = current[m.key] as Map?;
        if (old == null || (old['deleted'] != true && old['payload'] == null)) {
          current[m.key] = m.value;
        }
      }
    }
    await persist();
  });
}
