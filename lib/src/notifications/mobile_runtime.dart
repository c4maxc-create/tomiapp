import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android owns only presentation/lifetime. Authentication and call consent
/// stay in the existing session-bound API controllers.
abstract class MobileRuntime {
  Future<bool> startAudio(String id, String kind, {bool microphone = false});
  Future<void> renewAudio(String id);
  Future<void> stopAudio(String id);
  Future<void> bind(String? account, String? binding, bool enabled);
  Future<void> clearCall(String id);
  Future<Map<String, dynamic>?> takeAction();
  Stream<Map<String, dynamic>> get actions;
  bool get supported;
}

class NativeMobileRuntime implements MobileRuntime {
  static const channel = MethodChannel('tomi/mobile');
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  bool attached = false;
  @override
  bool get supported =>
      !kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!supported) return null;
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Stream<Map<String, dynamic>> get actions {
    if (supported && !attached) {
      attached = true;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'action' && call.arguments is Map)
          bus.add(Map<String, dynamic>.from(call.arguments as Map));
      });
    }
    return bus.stream;
  }

  @override
  Future<bool> startAudio(
    String id,
    String kind, {
    bool microphone = false,
  }) async =>
      await invoke<bool>('startAudio', {
        'id': id,
        'kind': kind,
        'microphone': microphone,
      }) ==
      true;
  @override
  Future<void> renewAudio(String id) async =>
      invoke<void>('renewAudio', {'id': id});
  @override
  Future<void> stopAudio(String id) async =>
      invoke<void>('stopAudio', {'id': id});
  @override
  Future<void> bind(String? account, String? binding, bool enabled) async =>
      invoke<void>('bind', {
        'accountId': account,
        'bindingId': binding,
        'enabled': enabled,
      });
  @override
  Future<void> clearCall(String id) async =>
      invoke<void>('clearCall', {'id': id});
  @override
  Future<Map<String, dynamic>?> takeAction() async {
    final d = await invoke<Map>('takeAction');
    return d == null ? null : Map<String, dynamic>.from(d);
  }
}
