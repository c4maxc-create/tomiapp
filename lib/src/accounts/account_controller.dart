import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'account_api.dart';
import 'account_models.dart';

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
  AccountController({required this.api, TokenVault? vault})
      : _vault = vault ?? SecureTokenVault(api.baseUrl);
  final AccountApi api;
  final TokenVault _vault;
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

  void _notify() { if (!_disposed) notifyListeners(); }

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
        try { await _clearLocal(); }
        catch (_) {
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
    try { await _vault.clear(); }
    catch (_) { throw const AccountFailure('STORAGE', 'تعذّر إنهاء الجلسة على الجهاز؛ جرّب مرة ثانية.'); }
    _token = null;
    _user = null;
    _pendingRecoveryCode = null;
    _phase = AccountPhase.signedOut;
  }

  Future<String?> _accept(AccountGrant grant) async {
    ++_revision;
    storageWarning = null;
    try { await _vault.write(grant.token); }
    catch (_) { storageWarning = 'دخلت لحسابك، لكن تعذّر حفظ الجلسة على الجهاز؛ قد تحتاج تسجّل دخولك لاحقًا.'; }
    _token = grant.token;
    _user = grant.user;
    _pendingRecoveryCode = grant.recoveryCode;
    _phase = AccountPhase.signedIn;
    _error = null;
    _notify();
    return grant.recoveryCode;
  }

  Future<String?> register(String username, String name, String password) async =>
    _accept(await api.register(username, name, password));

  Future<void> login(String username, String password) async {
    await _accept(await api.login(username, password));
  }

  Future<String?> recover(String username, String code, String password) async =>
    _accept(await api.recover(username, code, password));

  Future<T> _authenticated<T>(Future<T> Function(String token) work) async {
    final token = _token;
    if (token == null) throw const AccountFailure('UNAUTHORIZED', 'سجّل دخولك حتى تكمل.', status: 401);
    try {
      final result = await work(token);
      if (token != _token || _disposed) throw const AccountFailure('SESSION_CHANGED', 'جلسة الدخول تغيّرت.');
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

  Future<void> updateProfile({required String username, required String name,
      required String bio, required String avatarPreset}) async {
    _user = await _authenticated((token) => api.updateProfile(token,
      username: username, name: name, bio: bio, avatarPreset: avatarPreset));
    _notify();
  }

  Future<List<AccountUser>> search(String query) =>
    _authenticated((token) => api.search(token, query));

  Future<AccountUser> userById(String id) =>
    _authenticated((token) => api.user(token, id));

  Future<AccountUser> follow(String id, bool follow) async {
    final result = await _authenticated((token) => api.follow(token, id, follow));
    _user = result.me;
    _notify();
    return result.user;
  }

  Future<String?> changePassword(String oldPassword, String newPassword) async =>
    _accept(await _authenticated((token) => api.changePassword(token, oldPassword, newPassword)));

  Future<void> logout() async {
    final token = _token;
    if (token == null) return;
    try { await api.logout(token); }
    on AccountFailure catch (failure) { if (failure.status != 401) rethrow; }
    ++_revision;
    await _clearLocal();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    api.close();
    super.dispose();
  }
}
