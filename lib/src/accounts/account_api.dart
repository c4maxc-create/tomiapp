import '../experience/performance_monitor.dart';
import '../messaging/upload_transfer.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../messaging/chat_connection.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'account_models.dart';
import '../social/social_models.dart';

class AccountFailure implements Exception {
  const AccountFailure(this.code, this.message, {this.status = 0, this.field});
  final String code;
  final String message;
  final int status;
  final String? field;
  @override
  String toString() => message;
}

class AccountApi {
  AccountApi(String baseUrl, {http.Client? client})
    : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
      _client = client ?? http.Client() {
    final uri = Uri.tryParse(this.baseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
        'TOMI_API_URL must be an HTTPS endpoint without credentials.',
      );
    }
  }
  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> publicRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) => _request(method, path, body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final clock = Stopwatch()..start();
    try {
      final request = http.Request(method, uri)
        ..headers['accept'] = 'application/json'
        ..followRedirects = false;
      if (token != null) request.headers['authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.body = jsonEncode(body);
      }
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            Duration(
              seconds:
                  (path.startsWith('/v1/calls') ||
                      path.startsWith('/v1/rooms') ||
                      path.startsWith('/v1/games'))
                  ? 12
                  : (path.startsWith('/v1/chats') ||
                        path.startsWith('/v1/groups'))
                  ? 18
                  : 75,
            ),
          );
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = data['error'] as Map<String, dynamic>?;
        throw AccountFailure(
          error?['code'] as String? ?? 'UNAVAILABLE',
          error?['message'] as String? ?? 'تعذّر إكمال الطلب؛ جرّب مرة ثانية.',
          status: response.statusCode,
          field: error?['field'] as String?,
        );
      }
      return data;
    } on AccountFailure {
      rethrow;
    } on TimeoutException {
      throw const AccountFailure(
        'NETWORK',
        'الاتصال أخذ وقتًا طويلًا؛ جرّب مرة ثانية.',
      );
    } on http.ClientException {
      throw const AccountFailure(
        'NETWORK',
        'تعذّر الاتصال؛ تأكد من الإنترنت وجرّب مرة ثانية.',
      );
    } on FormatException {
      throw const AccountFailure(
        'UNAVAILABLE',
        'الخدمة غير متاحة حاليًا؛ جرّب مرة ثانية.',
      );
    } on TypeError {
      throw const AccountFailure(
        'UNAVAILABLE',
        'تعذّر قراءة البيانات؛ جرّب مرة ثانية.',
      );
    } finally {
      if (!path.startsWith('/v1/diagnostics'))
        PerformanceMonitor.instance.record(
          'api_latency',
          PerformanceMonitor.instance.area(path),
          clock.elapsedMilliseconds,
        );
    }
  }

  Future<void> warmUp() async {
    // One legitimate app-open request helps a sleeping preview server wake up.
    // This request carries no session or credentials and never changes account state.
    try {
      await _request('GET', '/health');
    } catch (_) {}
  }

  Future<AccountGrant> register(
    String username,
    String name,
    String password,
  ) async => AccountGrant.fromJson(
    await _request(
      'POST',
      '/v1/auth/register',
      body: {
        'username': username.trim(),
        'displayName': name.trim(),
        'password': password,
        'policyVersion': '2026-11-06',
      },
    ),
  );

  Future<AccountGrant> federatedLogin(
    String identityToken, {
    String? mfaCode,
  }) async => AccountGrant.fromJson(
    await _request(
      'POST',
      '/v1/auth/federated',
      body: {
        'identityToken': identityToken,
        'policyVersion': '2026-11-06',
        if (mfaCode != null) 'mfaCode': mfaCode,
      },
    ),
  );

  Future<AccountGrant> login(
    String username,
    String password, {
    String? mfaCode,
  }) async => AccountGrant.fromJson(
    await _request(
      'POST',
      '/v1/auth/login',
      body: {
        'username': username.trim(),
        'password': password,
        if (mfaCode != null) 'mfaCode': mfaCode,
      },
    ),
  );

  Future<AccountGrant> recover(
    String username,
    String code,
    String password, {
    String? mfaCode,
  }) async => AccountGrant.fromJson(
    await _request(
      'POST',
      '/v1/auth/recover',
      body: {
        'username': username.trim(),
        'recoveryCode': code.trim(),
        if (mfaCode != null) 'mfaCode': mfaCode,
        'password': password,
      },
    ),
  );

  Future<void> logout(String token) async {
    await _request('POST', '/v1/auth/logout', token: token, body: {});
  }

  Future<AccountUser> me(String token) async => AccountUser.fromJson(
    (await _request('GET', '/v1/me', token: token))['user']
        as Map<String, dynamic>,
  );

  Future<AccountUser> updateProfile(
    String token, {
    required String username,
    required String name,
    required String bio,
    required String avatarPreset,
  }) async => AccountUser.fromJson(
    (await _request(
          'PATCH',
          '/v1/me',
          token: token,
          body: {
            'username': username.trim(),
            'displayName': name.trim(),
            'bio': bio.trim(),
            'avatarPreset': avatarPreset,
          },
        ))['user']
        as Map<String, dynamic>,
  );

  Future<List<AccountUser>> search(String token, String query) async =>
      ((await _request(
                'GET',
                '/v1/users',
                token: token,
                query: {'q': query.trim()},
              ))['users']
              as List)
          .map((user) => AccountUser.fromJson(user as Map<String, dynamic>))
          .toList();

  Future<AccountUser> user(String token, String id) async =>
      AccountUser.fromJson(
        (await _request(
              'GET',
              '/v1/users/${Uri.encodeComponent(id)}',
              token: token,
            ))['user']
            as Map<String, dynamic>,
      );

  Future<FollowResult> follow(String token, String id, bool follow) async {
    final result = await _request(
      'PUT',
      '/v1/users/${Uri.encodeComponent(id)}/follow',
      token: token,
      body: {'follow': follow},
    );
    return FollowResult(
      user: AccountUser.fromJson(result['user'] as Map<String, dynamic>),
      me: AccountUser.fromJson(result['me'] as Map<String, dynamic>),
    );
  }

  Future<AccountGrant> changePassword(
    String token,
    String oldPassword,
    String newPassword, {
    String? identityToken,
  }) async => AccountGrant.fromJson(
    await _request(
      'POST',
      '/v1/auth/password',
      token: token,
      body: {
        'currentPassword': oldPassword,
        'newPassword': newPassword,
        if (identityToken != null) 'identityToken': identityToken,
      },
    ),
  );

  Future<FeedPage> feed(
    String token, {
    String scope = 'all',
    String? cursor,
    String? userId,
  }) async => FeedPage.fromJson(
    await _request(
      'GET',
      '/v1/posts',
      token: token,
      query: {
        'scope': scope,
        if (cursor != null) 'cursor': cursor,
        if (userId != null) 'userId': userId,
      },
    ),
  );
  Future<PublishResult> publishPost(
    String token,
    String text,
    String requestId, {
    String? uploadId,
    videoUploadId,
    attachmentSha256,
    String audience = 'public',
  }) async {
    final d = await _request(
      'POST',
      '/v1/posts',
      token: token,
      body: {
        'text': text.trim(),
        'requestId': requestId,
        'audience': audience,
        if (uploadId != null) 'imageUploadId': uploadId,
        if (videoUploadId != null) 'videoUploadId': videoUploadId,
        if (attachmentSha256 != null) 'attachmentSha256': attachmentSha256,
      },
    );
    return PublishResult(
      post: SocialPost.fromJson(d['post'] as Map<String, dynamic>),
      user: AccountUser.fromJson(d['user'] as Map<String, dynamic>),
    );
  }

  Future<SocialPost> likePost(String token, String id, bool liked) async =>
      SocialPost.fromJson(
        (await _request(
              'PUT',
              '/v1/posts/' + Uri.encodeComponent(id) + '/like',
              token: token,
              body: {'liked': liked},
            ))['post']
            as Map<String, dynamic>,
      );
  Future<AccountUser> deletePost(String token, String id) async =>
      AccountUser.fromJson(
        (await _request(
              'DELETE',
              '/v1/posts/' + Uri.encodeComponent(id),
              token: token,
            ))['user']
            as Map<String, dynamic>,
      );
  Future<CommentPage> comments(
    String token,
    String id, {
    String? cursor,
    bool threaded = false,
    String? parentId,
  }) async => CommentPage.fromJson(
    await _request(
      'GET',
      '/v1/posts/' + Uri.encodeComponent(id) + '/comments',
      token: token,
      query: {
        if (cursor != null) 'cursor': cursor,
        if (threaded) 'threaded': 'true',
        if (parentId != null) 'parentId': parentId,
      },
    ),
  );
  Future<CommentResult> addComment(
    String token,
    String id,
    String text,
    String requestId, {
    String? parentId,
  }) async {
    final d = await _request(
      'POST',
      '/v1/posts/' + Uri.encodeComponent(id) + '/comments',
      token: token,
      body: {
        'text': text.trim(),
        'requestId': requestId,
        if (parentId != null) 'parentId': parentId,
      },
    );
    return CommentResult(
      comment: SocialComment.fromJson(d['comment'] as Map<String, dynamic>),
      post: SocialPost.fromJson(d['post'] as Map<String, dynamic>),
    );
  }

  Future<SocialPost> deleteComment(String token, String id) async =>
      SocialPost.fromJson(
        (await _request(
              'DELETE',
              '/v1/comments/' + Uri.encodeComponent(id),
              token: token,
            ))['post']
            as Map<String, dynamic>,
      );
  Future<ImageUpload> prepareImage(String token, ImageDraft image) async =>
      ImageUpload.fromJson(
        await _request(
          'POST',
          '/v1/media/images',
          token: token,
          body: {
            'contentType': image.contentType,
            'byteLength': image.bytes.length,
            'contentMd5': image.contentMd5,
          },
        ),
      );
  Future<void> uploadResumable(
    String token,
    ImageUpload upload,
    ImageDraft image,
  ) async {
    final path = upload.resumablePath;
    if (path == null ||
        !RegExp(
          r'^/v1/media/resumable/(image_uploads|audio_uploads|video_uploads|private_uploads)/[a-f0-9-]{36}$',
        ).hasMatch(path))
      throw const AccountFailure('INVALID_UPLOAD', 'بيانات استكمال غير صحيحة.');
    final transfer = UploadTransfer.owners[image] ?? UploadTransfer();
    try {
      final plan = await chatRequest(token, 'POST', path, body: {});
      if (plan['completed'] == true) return;
      final chunk = (plan['chunkSize'] as num).toInt(),
          parts = (plan['parts'] as List).cast<Map<String, dynamic>>();
      if (chunk != 5 * 1024 * 1024 ||
          plan['total'] != image.bytes.length ||
          parts.length != (image.bytes.length / chunk).ceil())
        throw const AccountFailure('INVALID_UPLOAD', 'حجم الرفع تغير.');
      int committed = 0;
      for (var i = 0; i < parts.length; i++) {
        if (transfer.cancelled) throw http.RequestAbortedException(upload.url);
        final part = parts[i],
            start = i * chunk,
            end = (start + chunk).clamp(0, image.bytes.length),
            url = Uri.parse(part['url'] as String);
        if (part['number'] != i + 1 ||
            part['size'] != end - start ||
            url.scheme != 'https' ||
            !url.host.endsWith('.r2.cloudflarestorage.com') ||
            url.userInfo.isNotEmpty ||
            url.host != upload.url.host)
          throw const AccountFailure('INVALID_UPLOAD', 'وجهة رفع غير صحيحة.');
        if (part['uploaded'] != true) {
          final bytes = image.bytes.sublist(start, end),
              segment = UploadTransfer();
          void changed() =>
              transfer.update(committed + segment.sent, image.bytes.length);
          segment.addListener(changed);
          unawaited(transfer.abort.future.then((_) => segment.cancel()));
          try {
            final request = ProgressUploadRequest('PUT', url, bytes, segment);
            final r = await _client
                .send(request)
                .then(http.Response.fromStream)
                .timeout(const Duration(minutes: 2));
            if (r.statusCode < 200 || r.statusCode >= 300)
              throw const AccountFailure(
                'IMAGE_UPLOAD',
                'تعذّر رفع الجزء؛ الأجزاء المكتملة محفوظة.',
              );
          } finally {
            segment.removeListener(changed);
          }
        }
        committed = end;
        transfer.update(committed, image.bytes.length);
      }
      if (transfer.cancelled) throw http.RequestAbortedException(upload.url);
      await chatRequest(token, 'POST', path + '/complete', body: {});
    } on http.RequestAbortedException {
      throw const AccountFailure(
        'UPLOAD_CANCELLED',
        'توقف الرفع؛ الأجزاء المكتملة محفوظة وتگدر تكمل.',
      );
    } on TimeoutException {
      transfer.cancel();
      throw const AccountFailure(
        'IMAGE_NETWORK',
        'انقطع الرفع؛ أعد المحاولة لاستكمال الأجزاء المتبقية.',
      );
    } on http.ClientException {
      throw const AccountFailure(
        'IMAGE_NETWORK',
        'انقطع الاتصال؛ الأجزاء المكتملة محفوظة.',
      );
    }
  }

  Future<void> uploadImage(ImageUpload upload, ImageDraft image) async {
    if (upload.url.scheme != 'https' ||
        upload.url.userInfo.isNotEmpty ||
        !upload.url.host.endsWith('.r2.cloudflarestorage.com') ||
        upload.headers['content-type'] != image.contentType ||
        upload.headers['content-md5'] != image.contentMd5 ||
        upload.headers['if-none-match'] != '*')
      throw const AccountFailure(
        'INVALID_UPLOAD',
        'تعذّر تجهيز رفع الصورة؛ جرّب مرة ثانية.',
      );
    try {
      // Do not forward the account Bearer token to R2.
      final transfer = UploadTransfer.owners[image];
      final request = transfer == null
          ? (http.Request('PUT', upload.url)..bodyBytes = image.bytes)
          : ProgressUploadRequest('PUT', upload.url, image.bytes, transfer);
      request
        ..followRedirects = false
        ..headers.addAll({
          'content-type': image.contentType,
          'content-md5': image.contentMd5,
          'if-none-match': '*',
        });
      final r = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(minutes: 2));
      // A create-only retry can return 412 after the first PUT succeeded. Server verification follows.
      if ((r.statusCode < 200 || r.statusCode >= 300) && r.statusCode != 412)
        throw const AccountFailure(
          'IMAGE_UPLOAD',
          'تعذّر رفع الصورة؛ جرّب النشر مرة ثانية.',
        );
    } on http.RequestAbortedException {
      throw const AccountFailure(
        'UPLOAD_CANCELLED',
        'توقف الرفع؛ الملف محفوظ وتگدر تعيد المحاولة.',
      );
    } on TimeoutException {
      UploadTransfer.owners[image]?.cancel();
      throw const AccountFailure(
        'IMAGE_NETWORK',
        'رفع الصورة أخذ وقتًا طويلًا؛ جرّب النشر مرة ثانية.',
      );
    } on http.ClientException {
      throw const AccountFailure(
        'IMAGE_NETWORK',
        'انقطع رفع الصورة؛ تأكد من الإنترنت وجرّب النشر مرة ثانية.',
      );
    }
  }

  Future<Map<String, dynamic>> chatRequest(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => _request(method, path, token: token, body: body, query: query);
  Future<ChatConnection> openChatConnection(String token) async {
    final channel = WebSocketChannel.connect(
      Uri.parse('$baseUrl/v1/chat/socket').replace(scheme: 'wss'),
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 10));
      channel.sink.add(jsonEncode({'type': 'authenticate', 'token': token}));
      return WebChatConnection(channel);
    } catch (_) {
      try {
        await channel.sink.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
      rethrow;
    }
  }

  void close() => _client.close();
}
