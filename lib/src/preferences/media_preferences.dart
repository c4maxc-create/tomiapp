import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class MediaPreferences extends ChangeNotifier {
  static final instance = MediaPreferences();
  bool dataSaver = false,
      autoplay = false,
      smartQuality = true,
      performanceReports = false,
      wifiOnly = false,
      screenPrivacy = false;
  bool loaded = false;
  Future<void>? loading;
  final storage = const FlutterSecureStorage();
  Future<void> restore() {
    if (loaded) return Future.value();
    return loading ??= () async {
      try {
        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          final raw = await storage.read(key: 'tomi.media-preferences.v1');
          if (raw != null) {
            final d = jsonDecode(raw) as Map;
            dataSaver = d['dataSaver'] == true;
            autoplay = d['autoplay'] == true;
            smartQuality = d['smartQuality'] != false;
            performanceReports = d['performanceReports'] == true;
            wifiOnly = d['wifiOnly'] == true;
            screenPrivacy = d['screenPrivacy'] == true;
            await applyPrivacy(screenPrivacy);
          }
        }
      } finally {
        loaded = true;
        applyCacheLimit();
        notifyListeners();
      }
    }();
  }

  void applyCacheLimit() {
    PaintingBinding.instance.imageCache.maximumSizeBytes = dataSaver
        ? 32 * 1024 * 1024
        : 100 * 1024 * 1024;
  }

  Future<void> update({
    bool? saver,
    bool? auto,
    bool? smart,
    bool? reports,
    bool? wifi,
    bool? privacy,
  }) async {
    await restore();
    final next = {
      'dataSaver': saver ?? dataSaver,
      'autoplay': auto ?? autoplay,
      'smartQuality': smart ?? smartQuality,
      'performanceReports': reports ?? performanceReports,
      'wifiOnly': wifi ?? wifiOnly,
      'screenPrivacy': privacy ?? screenPrivacy,
    };
    if (privacy != null) await applyPrivacy(privacy);
    if (!Platform.environment.containsKey('FLUTTER_TEST'))
      await storage.write(
        key: 'tomi.media-preferences.v1',
        value: jsonEncode(next),
      );
    dataSaver = next['dataSaver']!;
    autoplay = next['autoplay']!;
    smartQuality = next['smartQuality']!;
    performanceReports = next['performanceReports']!;
    wifiOnly = next['wifiOnly']!;
    screenPrivacy = next['screenPrivacy']!;
    applyCacheLimit();
    notifyListeners();
  }

  Future<void> applyPrivacy(bool value) async {
    if ((Platform.isAndroid || Platform.isIOS) &&
        !Platform.environment.containsKey('FLUTTER_TEST'))
      await const MethodChannel(
        'tomi/mobile',
      ).invokeMethod<void>('screenPrivacy', {'enabled': value});
  }

  Future<bool> allowNetworkMedia() async {
    await restore();
    if (!wifiOnly) return true;
    final kinds = await Connectivity().checkConnectivity();
    return kinds.contains(ConnectivityResult.wifi) ||
        kinds.contains(ConnectivityResult.ethernet);
  }

  Future<int> previewBytes() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return 0;
    final root = await getTemporaryDirectory(),
        dir = Directory('${root.path}/tomi-media-previews');
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final item in dir.list(recursive: true, followLinks: false)) {
      if (item is File) total += await item.length();
    }
    return total;
  }

  Future<void> clearPreviews() async {
    // This dedicated directory contains disposable previews only, never drafts.
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      final root = await getTemporaryDirectory();
      final dir = Directory('${root.path}/tomi-media-previews');
      if (await dir.exists()) await dir.delete(recursive: true);
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      await for (final entity in root.list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (entity is File &&
            RegExp(
              r'^tomi-(voice|video-repair)-[0-9]+\.(m4a|mp4)$',
            ).hasMatch(name)) {
          if ((await entity.lastModified()).isBefore(cutoff))
            await entity.delete();
        }
      }
    }
    PaintingBinding.instance.imageCache.clear();
  }
}
