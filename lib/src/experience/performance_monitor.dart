import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../preferences/media_preferences.dart';

class PerformanceMonitor {
  static final instance = PerformanceMonitor();
  final Map<String, int> pending = {};
  Future<void> Function(List<Map<String, dynamic>>)? sender;
  Timer? timer;
  bool installed = false, busy = false;
  static const build = int.fromEnvironment(
    'FLUTTER_BUILD_NUMBER',
    defaultValue: 43,
  );
  Object? bindingOwner;
  void unbind(Object owner) {
    if (identical(bindingOwner, owner)) bind(null);
  }

  void install() {
    if (installed) return;
    installed = true;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record('flutter_error', 'ui', 0);
      previous?.call(details);
    };
    SchedulerBinding.instance.addTimingsCallback((frames) {
      for (final f in frames) {
        if (f.totalSpan.inMilliseconds > 24)
          record('slow_frame', 'ui', f.totalSpan.inMilliseconds);
      }
    });
    MediaPreferences.instance.addListener(preferenceChanged);
    unawaited(MediaPreferences.instance.restore().catchError((Object _) {}));
  }

  void bind(
    Future<void> Function(List<Map<String, dynamic>>)? callback, {
    Object? owner,
  }) {
    bindingOwner = owner;
    sender = callback;
    pending.clear();
    preferenceChanged();
  }

  void preferenceChanged() {
    timer?.cancel();
    timer = null;
    if (!MediaPreferences.instance.performanceReports) {
      pending.clear();
      return;
    }
    if (sender != null)
      timer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(flush()),
      );
  }

  int bucket(int ms) => ms <= 16
      ? 0
      : ms <= 32
      ? 1
      : ms <= 64
      ? 2
      : ms <= 128
      ? 3
      : ms <= 250
      ? 4
      : ms <= 1000
      ? 5
      : 6;
  String area(String path) =>
      path.startsWith('/v1/chats') || path.startsWith('/v1/groups')
      ? 'chat'
      : path.startsWith('/v1/posts') || path.startsWith('/v1/stories')
      ? 'feed'
      : path.startsWith('/v1/games')
      ? 'games'
      : path.startsWith('/v1/calls')
      ? 'calling'
      : path.startsWith('/v1/lives')
      ? 'live'
      : 'ui';
  void record(String kind, String area, int ms) {
    if (!MediaPreferences.instance.performanceReports || sender == null) return;
    final key = '$kind|$area|${bucket(ms)}';
    if (pending.length >= 60 && !pending.containsKey(key)) return;
    pending[key] = ((pending[key] ?? 0) + 1).clamp(0, 1000);
  }

  Future<void> flush() async {
    if (busy ||
        sender == null ||
        !MediaPreferences.instance.performanceReports ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
        pending.isEmpty)
      return;
    final batch = pending.entries.take(30).toList();
    for (final e in batch) pending.remove(e.key);
    busy = true;
    try {
      await sender!(
        batch.map((e) {
          final k = e.key.split('|');
          return {
            'kind': k[0],
            'area': k[1],
            'bucket': int.parse(k[2]),
            'count': e.value,
            'build': build,
          };
        }).toList(),
      );
    } catch (_) {
      /* Best-effort counters; never retry potentially accepted measurements. */
    } finally {
      busy = false;
    }
  }
}
