import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GalleryIntent {
  static const storage = FlutterSecureStorage();
  static const key = 'tomi.gallery.destination.v1';
  static Future<void> remember(
    String baseUrl,
    String userId, {
    String? conversationId,
    String purpose = 'feed',
  }) => storage.write(
    key: key,
    value: jsonEncode({
      'baseUrl': baseUrl,
      'userId': userId,
      'conversationId': conversationId,
      'purpose': purpose,
      'time': DateTime.now().millisecondsSinceEpoch,
    }),
  );
  static Future<Map<String, dynamic>?> take() async {
    final raw = await storage.read(key: key);
    await clear();
    if (raw == null) return null;
    final d = jsonDecode(raw) as Map<String, dynamic>;
    if (DateTime.now().millisecondsSinceEpoch - (d['time'] as num) > 86400000)
      return null;
    return d;
  }

  static Future<void> clear() => storage.delete(key: key);
}
