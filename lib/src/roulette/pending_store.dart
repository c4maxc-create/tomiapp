import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reuses the installed secure storage plugin; no new native dependencies.
class RoulettePendingStore {
  static const _storage = FlutterSecureStorage();
  static Future<RoulettePendingStore> getInstance() async =>
      RoulettePendingStore();
  Future<String?> getString(String key) => _storage.read(key: key);
  Future<bool> setString(String key, String value) async {
    await _storage.write(key: key, value: value);
    return true;
  }

  Future<void> remove(String key) => _storage.delete(key: key);
}
