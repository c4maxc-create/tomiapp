import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../accounts/account_controller.dart';

abstract class PushDeviceClient {
  Future<bool> initialize();
  Future<bool> permission({bool request = false});
  Future<String?> token();
  Future<void> deleteToken();
  Stream<String> get tokenChanges;
  Stream<Map<String, dynamic>> get opened;
  Future<Map<String, dynamic>?> initialMessage();
  String get platform;
}

class FirebasePushDeviceClient implements PushDeviceClient {
  Future<bool>? initialization;
  @override
  Future<bool> initialize() => initialization ??= initializeFirebase();
  Future<bool> initializeFirebase() async {
    if (!const bool.fromEnvironment('TOMI_PUSH_CONFIGURED') ||
        kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform))
      return false;
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  String get platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  @override
  Future<bool> permission({bool request = false}) async {
    final s = request
        ? await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
        : await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    if (platform == 'ios' &&
        await FirebaseMessaging.instance.getAPNSToken() == null)
      return null;
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Future<void> deleteToken() async {
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.deleteToken();
  }

  @override
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh;
  @override
  Stream<Map<String, dynamic>> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);
  @override
  Future<Map<String, dynamic>?> initialMessage() async =>
      (await FirebaseMessaging.instance.getInitialMessage())?.data;
}

class PushController extends ChangeNotifier with WidgetsBindingObserver {
  PushController({required this.accounts, PushDeviceClient? client})
    : client = client ?? FirebasePushDeviceClient() {
    accounts.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    accountChanged();
  }
  final AccountController accounts;
  final PushDeviceClient client;
  bool configured = false,
      enabled = true,
      permissionGranted = false,
      busy = false,
      disposed = false;
  String? error, identity, registeredToken;
  int generation = 0;
  bool initialHandled = false;
  StreamSubscription<String>? tokens;
  StreamSubscription<Map<String, dynamic>>? opened;
  Future<void> Function(String threadId, String accountId)? onOpen;
  void notify() {
    if (!disposed) notifyListeners();
  }

  void accountChanged() {
    final next = accounts.phase == AccountPhase.signedIn
        ? '${accounts.user!.id}:${accounts.sessionRevision}'
        : null;
    if (next == identity || disposed) return;
    identity = next;
    generation++;
    configured = false;
    registeredToken = null;
    permissionGranted = false;
    busy = false;
    error = null;
    if (next != null) unawaited(connect());
    notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && identity != null && !busy)
      unawaited(connect());
  }

  Future<void> connect() async {
    if (disposed || identity == null || busy) return;
    final gen = generation;
    busy = true;
    error = null;
    notify();
    try {
      if (!await client.initialize() || disposed || gen != generation) return;
      final settings = await accounts.chatRequest('GET', '/v1/push/settings');
      if (disposed || gen != generation) return;
      configured = settings['configured'] == true;
      enabled = settings['enabled'] == true;
      permissionGranted = await client.permission();
      if (disposed || gen != generation) return;
      tokens ??= client.tokenChanges.listen(
        (t) => unawaited(register(t)),
        onError: (Object _) {
          if (!disposed) {
            error = 'تعذّر تحديث الإشعارات.';
            notify();
          }
        },
      );
      opened ??= client.opened.listen(handleOpen);
      if (configured && enabled && permissionGranted) {
        final token = await client.token().timeout(const Duration(seconds: 15));
        if (disposed || gen != generation) return;
        if (token != null) await register(token);
      }
      if (!initialHandled) {
        initialHandled = true;
        final data = await client.initialMessage();
        if (disposed || gen != generation) return;
        if (data != null) handleOpen(data);
      }
    } catch (_) {
      if (!disposed && gen == generation)
        error = 'تعذّر ربط الإشعارات؛ جرّب مرة ثانية.';
    } finally {
      if (!disposed && gen == generation) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> register(String token) async {
    if (disposed ||
        identity == null ||
        !configured ||
        !enabled ||
        !permissionGranted ||
        token == registeredToken)
      return;
    final gen = generation;
    try {
      await accounts.chatRequest(
        'PUT',
        '/v1/push/device',
        body: {'token': token, 'platform': client.platform},
      );
      if (!disposed && gen == generation) registeredToken = token;
    } catch (_) {
      if (!disposed && gen == generation) {
        error = 'تعذّر ربط هذا الجهاز بالإشعارات.';
        notify();
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    if (busy || disposed || identity == null || !configured) return;
    final gen = generation;
    busy = true;
    error = null;
    notify();
    try {
      if (value) {
        permissionGranted = await client.permission(request: true);
        if (disposed || gen != generation) return;
        if (!permissionGranted) {
          error =
              'الإشعارات مرفوضة من الهاتف؛ تگدر تسمح بيها من إعدادات التطبيق.';
          return;
        }
      }
      final settings = await accounts.chatRequest(
        'PUT',
        '/v1/push/settings',
        body: {'enabled': value},
      );
      if (disposed || gen != generation) return;
      enabled = settings['enabled'] == true;
      if (value) {
        final token = await client.token().timeout(const Duration(seconds: 15));
        if (disposed || gen != generation) return;
        if (token != null) await register(token);
      } else {
        await unregister();
      }
    } catch (_) {
      if (!disposed && gen == generation)
        error = 'تعذّر تغيير إعداد الإشعارات.';
    } finally {
      if (!disposed && gen == generation) {
        busy = false;
        notify();
      }
    }
  }

  Future<void> unregister() async {
    final token = registeredToken;
    registeredToken = null;
    if (token != null && identity != null) {
      try {
        await accounts.chatRequest(
          'DELETE',
          '/v1/push/device',
          body: {'token': token},
        );
      } catch (_) {}
    }
    if (token != null)
      try {
        await client.deleteToken().timeout(const Duration(seconds: 10));
      } catch (_) {}
  }

  void handleOpen(Map<String, dynamic> data) {
    if (disposed ||
        identity == null ||
        data['type'] != 'chat' ||
        data['accountId'] != accounts.user?.id)
      return;
    final thread = data['conversationId'], account = data['accountId'];
    if (thread is! String ||
        account is! String ||
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
        ).hasMatch(thread))
      return;
    final work = onOpen?.call(thread, account);
    if (work != null)
      unawaited(
        work.catchError((Object _) {
          if (!disposed) {
            error = 'تعذّر فتح المحادثة.';
            notify();
          }
        }),
      );
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    accounts.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(tokens?.cancel());
    unawaited(opened?.cancel());
    super.dispose();
  }
}
