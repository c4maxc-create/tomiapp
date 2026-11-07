import 'dart:async';
import 'external_identity.dart';
import '../social/home_controller.dart';
import '../identity/identity_models.dart';
import '../gaming/game_models.dart';
import '../messaging/chat_controller.dart';
import '../messaging/draft_store.dart';
import '../messaging/chat_connection.dart';
import '../notifications/push_controller.dart';
import '../notifications/mobile_runtime.dart';
import '../calling/call_controller.dart';
import '../calling/call_media.dart';
import '../voice_rooms/room_controller.dart';
import '../voice_rooms/room_audio.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'account_api.dart';
import 'account_models.dart';
import '../social/social_models.dart';

abstract class TokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenVault implements TokenVault {
  SecureTokenVault(String baseUrl) : _key = 'tomi.account.session.v1.$baseUrl';
  final String _key;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

enum AccountPhase { restoring, signedOut, signedIn, connectionError }

class AccountController extends ChangeNotifier {
  AccountController({
    required this.api,
    TokenVault? vault,
    this.realtimeEnabled = true,
    this.roomAudioFactory,
    this.callMediaFactory,
    MobileRuntime? mobile,
    DraftStore? draftStore,
  }) : draftStore = draftStore ?? defaultDraftStore(),
       mobile = mobile ?? NativeMobileRuntime(),
       _vault = vault ?? SecureTokenVault(api.baseUrl);
  final AccountApi api;
  final MobileRuntime mobile;
  final DraftStore draftStore;
  String? get draftSessionFence =>
      _token == null ? null : draftOwner('session', _token!);
  String? get draftOwnerId =>
      user == null ? null : draftOwner(api.baseUrl, user!.id);
  final bool realtimeEnabled;
  final RoomAudio Function()? roomAudioFactory;
  final CallMedia Function()? callMediaFactory;
  VoiceRoomsController? _voiceRooms;
  VoiceRoomsController get voiceRooms => _voiceRooms ??= VoiceRoomsController(
    accounts: this,
    audioFactory: roomAudioFactory,
    autoPoll: realtimeEnabled,
  );
  Object? liveMediaLease;
  bool get voiceRoomActive => _voiceRooms?.inRoom ?? false;
  Future<void> get roomAudioReleased =>
      _voiceRooms?.releaseTail ?? Future.value();
  CallController? _calls;
  CallController get calls => _calls ??= CallController(
    accounts: this,
    mediaFactory: callMediaFactory,
    autoPoll: realtimeEnabled,
  );
  bool get liveAudioBusy =>
      _calls?.active?.ended == false ||
      _voiceRooms?.active != null ||
      liveMediaLease != null;
  HomeController? _home;
  HomeController get home =>
      _home ??= HomeController(this, autoPoll: realtimeEnabled);
  PushController? _push;
  PushController get push => _push ??= PushController(accounts: this);
  ChatController? _chats;
  ChatController get chats => _chats ??= ChatController(
    accounts: this,
    realtimeEnabled: realtimeEnabled,
  );
  int get sessionRevision => _revision;
  Future<Map<String, dynamic>> chatRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => _authenticated(
    (token) => api.chatRequest(token, method, path, body: body, query: query),
  );
  Future<void> saveIdentity(Map<String, dynamic> body) async {
    final d = await chatRequest('PUT', '/v1/me/identity', body: body);
    _user = AccountUser.fromJson(d['user'] as Map<String, dynamic>);
    _notify();
  }

  void applyRoomIdentity(AccountUser member) {
    final own = _user;
    if (own == null || member.id != own.id || !member.identity.available)
      return;
    final clean = Map<String, dynamic>.from(member.identity.data)
      ..remove('roomFrameId')
      ..remove('roomFrameExpiresAt')
      ..remove('roomEntranceId');
    final next = UserIdentity(clean), previous = own.identity;
    if (next.xp < previous.xp ||
        next.revision < previous.revision ||
        next.giftsReceived < previous.giftsReceived ||
        (next.data['roomsCreated'] as num? ?? 0) <
            (previous.data['roomsCreated'] as num? ?? 0))
      return;
    if (previous.available &&
        next.xp == previous.xp &&
        next.revision == previous.revision &&
        next.giftsReceived == previous.giftsReceived &&
        next.data['roomsCreated'] == previous.data['roomsCreated'])
      return;
    _user = own.withIdentity(next);
    _notify();
  }

  void applyGameProgress(
    GameProgress value, {
    required String accountId,
    required int session,
  }) {
    if (_user?.id != accountId ||
        _revision != session ||
        value.xp <= _user!.gameProgress.xp)
      return;
    _user = _user!.withGameProgress(value);
    _notify();
  }

  Future<void> saveAvatar(String? uploadId, String requestId) async {
    final d = await chatRequest(
      'PUT',
      '/v1/me/avatar',
      body: {'imageUploadId': uploadId, 'requestId': requestId},
    );
    _user = AccountUser.fromJson(d['user'] as Map<String, dynamic>);
    _notify();
  }

  Future<ChatConnection> openChatConnection() async {
    final token = _token;
    if (token == null)
      throw const AccountFailure('UNAUTHORIZED', 'سجّل دخولك.', status: 401);
    final socket = await api.openChatConnection(token);
    if (_disposed || token != _token) {
      await socket.close();
      throw const AccountFailure('SESSION_CHANGED', 'جلسة الدخول تغيّرت.');
    }
    return socket;
  }

  final TokenVault _vault;
  Future<void> _vaultTail = Future<void>.value();
  Future<void> _mutateVault(Future<void> Function() work) {
    final result = _vaultTail.then((_) => work());
    _vaultTail = result.catchError((Object _) {});
    return result;
  }

  AccountPhase _phase = AccountPhase.restoring;
  AccountUser? _user;
  String? _token;
  String? _error;
  String? _pendingRecoveryCode;
  String? storageWarning;
  int _revision = 0;
  bool _disposed = false;

  AccountPhase get phase => _phase;
  AccountUser? get user => _user;
  String? get error => _error;
  String? get pendingRecoveryCode => _pendingRecoveryCode;

  void acknowledgeRecoveryCode() {
    _pendingRecoveryCode = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    final revision = ++_revision;
    _phase = AccountPhase.restoring;
    _error = null;
    _notify();
    try {
      final token = await _vault.read();
      if (revision != _revision || _disposed) return;
      if (token == null) {
        _token = null;
        _user = null;
        _phase = AccountPhase.signedOut;
      } else {
        final user = await api.me(token);
        if (revision != _revision || _disposed) return;
        _token = token;
        _user = user;
        _phase = AccountPhase.signedIn;
      }
    } on AccountFailure catch (failure) {
      if (revision != _revision || _disposed) return;
      if (failure.status == 401) {
        try {
          await _clearLocal();
        } catch (_) {
          _phase = AccountPhase.connectionError;
          _error = 'تعذّر إنهاء الجلسة القديمة؛ جرّب مرة ثانية.';
        }
      } else {
        // A connection error must never erase a still-valid stored session.
        _phase = AccountPhase.connectionError;
        _error = failure.message;
      }
    } catch (_) {
      if (revision != _revision || _disposed) return;
      _phase = AccountPhase.connectionError;
      _error = 'تعذّر قراءة جلسة الدخول؛ جرّب مرة ثانية.';
    }
    if (revision == _revision) _notify();
  }

  Future<void> _clearLocal() async {
    final revision = _revision;
    try {
      await _mutateVault(_vault.clear);
    } catch (_) {
      throw const AccountFailure(
        'STORAGE',
        'تعذّر إنهاء الجلسة على الجهاز؛ جرّب مرة ثانية.',
      );
    }
    if (revision != _revision || _disposed) return;
    unawaited(ExternalIdentity.signOut());
    _token = null;
    _user = null;
    _pendingRecoveryCode = null;
    _phase = AccountPhase.signedOut;
  }

  Future<String?> _accept(AccountGrant grant) async {
    final revision = ++_revision;
    storageWarning = null;
    try {
      await _mutateVault(() => _vault.write(grant.token));
    } catch (_) {
      storageWarning =
          'دخلت لحسابك، لكن تعذّر حفظ الجلسة على الجهاز؛ قد تحتاج تسجّل دخولك لاحقًا.';
    }
    if (revision != _revision || _disposed)
      throw const AccountFailure('SESSION_CHANGED', 'جلسة الدخول تغيّرت.');
    _token = grant.token;
    _user = grant.user;
    _pendingRecoveryCode = grant.recoveryCode;
    _phase = AccountPhase.signedIn;
    _error = null;
    _notify();
    return grant.recoveryCode;
  }

  Future<String?> register(
    String username,
    String name,
    String password,
  ) async => _accept(await api.register(username, name, password));

  Future<void> federatedLogin(String token, {String? mfaCode}) async {
    await _accept(await api.federatedLogin(token, mfaCode: mfaCode));
  }

  Future<void> login(
    String username,
    String password, {
    String? mfaCode,
  }) async {
    await _accept(await api.login(username, password, mfaCode: mfaCode));
  }

  Future<String?> recover(
    String username,
    String code,
    String password, {
    String? mfaCode,
  }) async =>
      _accept(await api.recover(username, code, password, mfaCode: mfaCode));

  Future<T> _authenticated<T>(Future<T> Function(String token) work) async {
    final token = _token;
    if (token == null)
      throw const AccountFailure(
        'UNAUTHORIZED',
        'سجّل دخولك حتى تكمل.',
        status: 401,
      );
    try {
      final result = await work(token);
      if (token != _token || _disposed)
        throw const AccountFailure('SESSION_CHANGED', 'جلسة الدخول تغيّرت.');
      return result;
    } on AccountFailure catch (failure) {
      if (failure.status == 401 && token == _token && !_disposed) {
        ++_revision;
        await _clearLocal();
        _notify();
      }
      rethrow;
    }
  }

  Future<void> reloadMe() async {
    _user = await _authenticated(api.me);
    _notify();
  }

  Future<void> updateProfile({
    required String username,
    required String name,
    required String bio,
    required String avatarPreset,
  }) async {
    _user = await _authenticated(
      (token) => api.updateProfile(
        token,
        username: username,
        name: name,
        bio: bio,
        avatarPreset: avatarPreset,
      ),
    );
    _notify();
  }

  Future<List<AccountUser>> search(String query) =>
      _authenticated((token) => api.search(token, query));

  Future<AccountUser> userById(String id) =>
      _authenticated((token) => api.user(token, id));

  Future<AccountUser> follow(String id, bool follow) async {
    final result = await _authenticated(
      (token) => api.follow(token, id, follow),
    );
    _user = result.me;
    _notify();
    return result.user;
  }

  Future<String?> changePassword(
    String oldPassword,
    String newPassword, {
    String? identityToken,
  }) async => _accept(
    await _authenticated(
      (token) => api.changePassword(
        token,
        oldPassword,
        newPassword,
        identityToken: identityToken,
      ),
    ),
  );

  Future<FeedPage> feed({
    String scope = 'all',
    String? cursor,
    String? userId,
  }) => _authenticated(
    (token) => api.feed(token, scope: scope, cursor: cursor, userId: userId),
  );
  Future<SocialPost> publishPost(
    String text,
    String requestId, {
    String? uploadId,
    videoUploadId,
    attachmentSha256,
    String audience = 'public',
  }) async {
    final r = await _authenticated(
      (token) => api.publishPost(
        token,
        text,
        requestId,
        uploadId: uploadId,
        videoUploadId: videoUploadId,
        attachmentSha256: attachmentSha256,
        audience: audience,
      ),
    );
    _user = r.user;
    _notify();
    return r.post;
  }

  Future<SocialPost> likePost(String id, bool liked) =>
      _authenticated((token) => api.likePost(token, id, liked));
  Future<void> deletePost(String id) async {
    _user = await _authenticated((token) => api.deletePost(token, id));
    _notify();
  }

  Future<CommentPage> comments(
    String id, {
    String? cursor,
    bool threaded = false,
    String? parentId,
  }) => _authenticated(
    (token) => api.comments(
      token,
      id,
      cursor: cursor,
      threaded: threaded,
      parentId: parentId,
    ),
  );
  Future<CommentResult> addComment(
    String id,
    String text,
    String requestId, {
    String? parentId,
  }) => _authenticated(
    (token) => api.addComment(token, id, text, requestId, parentId: parentId),
  );
  Future<SocialPost> deleteComment(String id) =>
      _authenticated((token) => api.deleteComment(token, id));
  Future<ImageUpload> preparePostMedia(
    ImageDraft media,
    String requestId,
  ) async => ImageUpload.fromJson(
    await chatRequest(
      'POST',
      media is VideoDraft ? '/v1/media/videos' : '/v1/media/images',
      body: {
        'contentType': media.contentType,
        'byteLength': media.bytes.length,
        'contentMd5': media.contentMd5,
        'contentSha256': media.contentSha256,
        'requestId': requestId,
      },
    ),
  );
  Future<ImageUpload> prepareImage(ImageDraft image) =>
      _authenticated((token) => api.prepareImage(token, image));
  Future<void> uploadImage(ImageUpload upload, ImageDraft image) async {
    if (image is VideoDraft && image.poster != null) {
      try {
        await chatRequest(
          'PUT',
          '/v1/media/videos/${upload.id}/poster',
          body: {'poster': image.poster},
        );
      } on AccountFailure catch (e) {
        if (e.status != 404 && e.status != 409) rethrow;
      }
    }
    await _authenticated(
      (token) => upload.resumablePath == null
          ? api.uploadImage(upload, image)
          : api.uploadResumable(token, upload, image),
    );
  }

  Future<void> logout() async {
    final token = _token;
    if (token == null) return;
    try {
      await _voiceRooms?.leave();
      await _calls?.hangup();
      await _push?.unregister();
      await api.logout(token);
    } on AccountFailure catch (failure) {
      if (failure.status != 401) rethrow;
    }
    ++_revision;
    await _clearLocal();
    _notify();
  }

  Future<Map<String, dynamic>> requestAccountDeletion(
    Map<String, dynamic> body,
    String userId,
    int revision,
  ) {
    final token = _token;
    if (_disposed ||
        token == null ||
        _user?.id != userId ||
        revision != _revision)
      throw const AccountFailure(
        'SESSION_CHANGED',
        'جلسة الحساب تغيّرت؛ لم نرسل طلب حذف جديد.',
      );
    // An accepted deletion can revoke this session before its ACK arrives.
    return api.chatRequest(token, 'POST', '/v1/account/deletion', body: body);
  }

  Future<void> finishDeletedAccount(
    String userId, {
    String? sessionFence,
  }) async {
    final owner = draftOwner(api.baseUrl, userId);
    final expectedFence =
        sessionFence ?? (_user?.id == userId ? draftSessionFence : null);
    if (_user?.id == userId) {
      ++_revision;
      _token = null;
      _user = null;
      _pendingRecoveryCode = null;
      _phase = AccountPhase.signedOut;
      // Listeners release microphones, sockets and cached account views now.
      _notify();
    }
    if (expectedFence != null)
      await _mutateVault(() async {
        final stored = await _vault.read();
        if (stored != null && draftOwner('session', stored) == expectedFence)
          await _vault.clear();
      });
    await draftStore.erase(owner);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    _voiceRooms?.dispose();
    _calls?.dispose();
    _chats?.dispose();
    _push?.dispose();
    _home?.dispose();
    api.close();
    super.dispose();
  }
}
