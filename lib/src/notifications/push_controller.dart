import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
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
  Future<bool> initialize() async {
    final attempt = initialization ??= initializeFirebase();
    final ready = await attempt;
    // A temporary native initialization failure must be retryable.
    if (!ready && identical(initialization, attempt)) initialization = null;
    return ready;
  }

  Future<bool> initializeFirebase() async {
    // Native Firebase is available only on the actual phone platform; a
    // desktop renderer can emulate Android's theme without native plugins.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      if (Firebase.apps.isEmpty)
        await Firebase.initializeApp().timeout(const Duration(seconds: 10));
      if (defaultTargetPlatform == TargetPlatform.iOS)
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            );
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
    final existing = await FirebaseMessaging.instance.getNotificationSettings();
    // Request once while the app is visible. A refusal is respected on resume.
    final shouldRequest =
        request ||
        existing.authorizationStatus == AuthorizationStatus.notDetermined;
    final s = shouldRequest
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
    nativeActions = accounts.mobile.actions.listen(nativeEvent);
    accountChanged();
  }
  final AccountController accounts;
  final PushDeviceClient client;
  bool configured = false,
      clientReady = false,
      checked = false,
      enabled = true,
      permissionGranted = false,
      busy = false,
      disposed = false;
  String? error, identity, registeredToken;
  int generation = 0;
  bool initialHandled = false, draining = false, drainAgain = false;
  String? registeredBinding;
  StreamSubscription<Map<String, dynamic>>? nativeActions;
  StreamSubscription<RemoteMessage>? foreground;
  static const notificationChannel = MethodChannel('tomi/mobile');
  StreamSubscription<String>? tokens;
  StreamSubscription<Map<String, dynamic>>? opened;
  Future<void> Function(String threadId, String accountId)? onOpen;
  Future<void> Function(String callId, String accountId)? onOpenCall;
  Future<void> Function(String accountId)? onOpenActivity;
  Future<void> Function(String accountId, String noticeId)? onOpenNotice;
  Future<void> Function(String accountId, String url)? onOpenTomiLink;
  Future<void> Function(String accountId, String activityId)?
  onOpenActivityItem;
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
    clientReady = false;
    checked = false;
    registeredToken = null;
    registeredBinding = null;
    unawaited(
      accounts.mobile
          .bind(accounts.user?.id, null, false)
          .catchError((Object _) {}),
    );
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
    if (state == AppLifecycleState.resumed) unawaited(drainActions());
  }

  Future<void> connect() async {
    if (disposed || identity == null || busy) return;
    final gen = generation;
    busy = true;
    error = null;
    notify();
    try {
      final settings = await accounts.chatRequest('GET', '/v1/push/settings');
      if (disposed || gen != generation) return;
      configured = settings['configured'] == true;
      enabled = settings['enabled'] == true;
      final initialized = await client.initialize();
      if (disposed || gen != generation) return;
      clientReady = initialized;
      checked = true;
      if (!initialized) {
        error =
            'إعداد إشعارات هذه النسخة غير مكتمل. حدّث التطبيق بعد تفعيل خدمة إشعارات الهاتف.';
        await unregister();
        await drainActions();
        return;
      }
      if (!configured)
        error =
            'خدمة إشعارات الخادم غير مفعّلة حاليًا. أعد التحديث بعد تفعيلها.';
      permissionGranted = configured && enabled
          ? await client.permission()
          : false;
      if (disposed || gen != generation) return;
      if (!configured || !enabled || !permissionGranted) {
        await unregister();
        if (disposed || gen != generation) return;
      }
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
      if (client is FirebasePushDeviceClient)
        foreground ??= FirebaseMessaging.onMessage.listen((message) {
          if (disposed ||
              !enabled ||
              !permissionGranted ||
              message.data['accountId'] != accounts.user?.id)
            return;
          if (message.data['type'] == 'activity')
            unawaited(accounts.home.loadActivity());
          if (defaultTargetPlatform == TargetPlatform.android &&
              ['chat', 'activity', 'notice'].contains(message.data['type'])) {
            unawaited(
              notificationChannel
                  .invokeMethod<void>('presentNotification', {
                    'data': message.data,
                  })
                  .catchError((Object _) {}),
            );
          }
        });
      if (configured && enabled && permissionGranted) {
        final token = await client.token().timeout(const Duration(seconds: 15));
        if (disposed || gen != generation) return;
        if (token != null)
          await register(token);
        else
          error = 'تعذّر الحصول على رمز إشعارات الهاتف؛ جرّب التحديث بعد قليل.';
      }
      await drainActions();
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
        !clientReady ||
        !enabled ||
        !permissionGranted ||
        token == registeredToken)
      return;
    final gen = generation;
    try {
      final d = await accounts.chatRequest(
        'PUT',
        '/v1/push/device',
        body: {
          'token': token,
          'platform': client.platform,
          if (client.platform == 'android') 'callProtocol': 2,
        },
      );
      if (!disposed && gen == generation) {
        if (d['configured'] != true) {
          configured = false;
          error = 'خدمة إشعارات الخادم غير مفعّلة حاليًا.';
          await accounts.mobile.bind(accounts.user?.id, null, false);
          return;
        }
        registeredToken = token;
        registeredBinding = d['bindingId'] as String?;
        await accounts.mobile.bind(
          accounts.user?.id,
          registeredBinding,
          enabled && permissionGranted,
        );
        if (!disposed && gen == generation) await drainActions();
      }
    } catch (_) {
      if (!disposed && gen == generation) {
        error = 'تعذّر ربط هذا الجهاز بالإشعارات.';
        notify();
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    if (busy || disposed || identity == null) return;
    if (value && (!configured || !clientReady)) {
      await connect();
      if (disposed || identity == null || !configured || !clientReady) return;
    }
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
        if (token != null)
          await register(token);
        else
          error = 'تعذّر الحصول على رمز إشعارات الهاتف؛ جرّب التحديث بعد قليل.';
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

  Future<void> openSystemSettings() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await notificationChannel.invokeMethod<void>('notificationSettings');
      } catch (_) {
        error = 'افتح إعدادات الهاتف ← التطبيقات ← TOMI ← الإشعارات.';
        notify();
      }
    }
  }

  Future<void> unregister() async {
    final token = registeredToken;
    registeredToken = null;
    registeredBinding = null;
    await accounts.mobile.bind(accounts.user?.id, null, false);
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

  Future<void> drainDeepLink() async {
    if (!accounts.mobile.supported ||
        disposed ||
        identity == null ||
        onOpenTomiLink == null)
      return;
    final gen = generation, account = accounts.user?.id;
    try {
      final url = await notificationChannel.invokeMethod<String>(
        'takeDeepLink',
      );
      if (url != null && !disposed && gen == generation && account != null)
        unawaited(onOpenTomiLink?.call(account, url).catchError((Object _) {}));
    } catch (_) {}
  }

  Future<void> drainNotification() async {
    if (!accounts.mobile.supported || disposed || identity == null) return;
    try {
      final raw = await notificationChannel.invokeMethod<Map>(
        'takeNotification',
      );
      if (raw != null && !disposed) handleOpen(Map<String, dynamic>.from(raw));
    } catch (_) {}
  }

  void nativeEvent(Map<String, dynamic> data) {
    if (disposed || identity == null) return;
    if (data['type'] == 'deepLink') {
      unawaited(drainDeepLink());
      return;
    }
    if (data['type'] == 'notification') {
      unawaited(drainNotification());
      return;
    }
    final id = data['callId'];
    if (data['type'] == 'audioStopped' || data['type'] == 'control') {
      if (data['type'] == 'control' && data['accountId'] != accounts.user?.id)
        return;
      if (id != null && accounts.calls.audioLease == id)
        unawaited(accounts.calls.hangup());
      if (id != null && accounts.voiceRooms.audioLease == id)
        unawaited(accounts.voiceRooms.leave());
    } else {
      unawaited(drainActions());
    }
  }

  Future<void> drainActions() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (disposed ||
        identity == null ||
        lifecycle != null && lifecycle != AppLifecycleState.resumed)
      return;
    if (draining) {
      drainAgain = true;
      return;
    }
    draining = true;
    final gen = generation;
    try {
      await drainDeepLink();
      await drainNotification();
      final data = await accounts.mobile.takeAction();
      if (data == null ||
          disposed ||
          gen != generation ||
          data['accountId'] != accounts.user?.id)
        return;
      final id = data['callId'];
      if (id is! String ||
          !RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
          ).hasMatch(id))
        return;
      final action = data['action'];
      if (action == 'end') {
        if (accounts.calls.active?.id == id && accounts.calls.backgroundAudio)
          await accounts.calls.hangup();
        return;
      }
      if (action == 'leave') {
        if (accounts.voiceRooms.identity == id &&
            accounts.voiceRooms.backgroundAudio)
          await accounts.voiceRooms.leave();
        return;
      }
      if (registeredBinding == null ||
          data['bindingId'] != registeredBinding ||
          !['open', 'answer', 'decline'].contains(action))
        return;
      final calls = accounts.calls;
      if (!await calls.open(id) ||
          disposed ||
          gen != generation ||
          calls.active?.id != id)
        return;
      await accounts.mobile.clearCall(id);
      if (!calls.active!.incoming || !calls.active!.canControl) return;
      if (action == 'answer') await calls.accept();
      if (action == 'decline') await calls.decline();
    } catch (_) {
      if (!disposed && gen == generation) {
        error = 'تعذّر تنفيذ زر المكالمة؛ افتح التطبيق وتحقق من الاتصال.';
        notify();
      }
    } finally {
      draining = false;
      if (drainAgain) {
        drainAgain = false;
        unawaited(drainActions());
      }
    }
  }

  void handleOpen(Map<String, dynamic> data) {
    if (!disposed &&
        identity != null &&
        data['type'] == 'notice' &&
        data['accountId'] == accounts.user?.id) {
      final id = data['noticeId'];
      if (id is String && RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
        final work = onOpenNotice?.call(accounts.user!.id, id);
        if (work != null) unawaited(work.catchError((Object _) {}));
      }
      return;
    }

    if (!disposed &&
        identity != null &&
        data['type'] == 'activity' &&
        data['accountId'] == accounts.user?.id) {
      final activity = data['activityId'];
      final work =
          activity is String &&
              RegExp(r'^[a-f0-9-]{36}$').hasMatch(activity) &&
              onOpenActivityItem != null
          ? onOpenActivityItem!(accounts.user!.id, activity)
          : onOpenActivity?.call(accounts.user!.id);
      if (work != null) unawaited(work.catchError((Object _) {}));
      return;
    }
    if (!disposed &&
        identity != null &&
        data['type'] == 'call' &&
        data['accountId'] == accounts.user?.id) {
      final id = data['callId'], account = data['accountId'];
      if (id is String &&
          account is String &&
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
          ).hasMatch(id)) {
        final work = onOpenCall?.call(id, account);
        if (work != null)
          unawaited(
            work.catchError((Object _) {
              if (!disposed) {
                error = 'تعذّر فتح المكالمة.';
                notify();
              }
            }),
          );
      }
      return;
    }

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
    unawaited(foreground?.cancel());
    unawaited(nativeActions?.cancel());
    unawaited(
      accounts.mobile.bind(null, null, false).catchError((Object _) {}),
    );
    super.dispose();
  }
}
