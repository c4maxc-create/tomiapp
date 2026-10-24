import 'social/activity_screen.dart';
import 'social/story_screens.dart' show socialBackground;
import 'messaging/chat_screens.dart';
import 'messaging/chat_models.dart';
import 'calling/call_models.dart';
import 'calling/call_screens.dart';
import 'voice_rooms/room_screens.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'chat.dart';
import 'games.dart';
import 'home.dart';
import 'social/social_screens.dart';
import 'model.dart';
import 'profile.dart';
import 'rooms.dart';
import 'widgets.dart';
import 'accounts/account_api.dart';
import 'accounts/account_controller.dart';
import 'accounts/account_profile.dart';
import 'accounts/account_search.dart';
import 'accounts/auth_screen.dart';

class TomiApp extends StatefulWidget {
  const TomiApp({
    super.key,
    this.store,
    this.textScaler,
    this.accounts,
    this.previewMode = const bool.fromEnvironment('TOMI_PREVIEW_MODE'),
    this.apiUrl = const String.fromEnvironment('TOMI_API_URL'),
  });
  final TomiStore? store;
  final TextScaler? textScaler;
  final AccountController? accounts;
  final bool previewMode;
  final String apiUrl;

  @override
  State<TomiApp> createState() => _TomiAppState();
}

class _TomiAppState extends State<TomiApp> {
  late final TomiStore store = widget.store ?? TomiStore();
  final navigator = GlobalKey<NavigatorState>();
  AccountController? accounts;
  String? previousUserId;
  String? previousRecoveryCode;
  String? shownCallId;
  bool previewSelected = false;

  @override
  void initState() {
    super.initState();
    accounts = widget.accounts;
    if (accounts == null &&
        widget.store == null &&
        !widget.previewMode &&
        widget.apiUrl.isNotEmpty) {
      accounts = AccountController(api: AccountApi(widget.apiUrl));
    }
    previousUserId = accounts?.user?.id;
    previousRecoveryCode = accounts?.pendingRecoveryCode;
    accounts?.addListener(accountChanged);
    if (accounts != null) {
      accounts!.calls.onShow = showCall;
      accounts!.push.onOpen = openPushChat;
      accounts!.push.onOpenCall = openPushCall;
      accounts!.push.onOpenActivity = openPushActivity;
    }
    if (accounts?.phase == AccountPhase.restoring)
      unawaited(accounts!.restore());
  }

  void showCall(DirectCall call) {
    final controller = accounts;
    if (controller == null || shownCallId == call.id) return;
    final revision = controller.sessionRevision, userId = controller.user?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          userId == null ||
          controller.user?.id != userId ||
          controller.sessionRevision != revision ||
          shownCallId == call.id)
        return;
      final nav = navigator.currentState;
      if (nav == null) return;
      shownCallId = call.id;
      unawaited(
        nav
            .push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CallPage(calls: controller.calls, initialCall: call),
              ),
            )
            .whenComplete(() {
              if (shownCallId == call.id) shownCallId = null;
            }),
      );
    });
  }

  Future<void> openPushActivity(String accountId) async {
    final a = accounts;
    if (!mounted || a?.user?.id != accountId) return;
    final nav = navigator.currentState;
    if (nav == null) return;
    await nav.push(
      MaterialPageRoute<void>(builder: (_) => ActivityPage(accounts: a!)),
    );
  }

  Future<void> openPushCall(String callId, String accountId) async {
    if (accounts?.user?.id == accountId) await accounts!.calls.open(callId);
  }

  Future<void> openPushChat(String threadId, String accountId) async {
    final controller = accounts;
    if (controller == null || controller.user?.id != accountId) return;
    final revision = controller.sessionRevision;
    final d = await controller.chatRequest('GET', '/v1/chats/$threadId');
    if (!mounted ||
        controller.user?.id != accountId ||
        controller.sessionRevision != revision)
      return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          controller.user?.id == accountId &&
          controller.sessionRevision == revision)
        navigator.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => PrivateChatPage(
              chats: controller.chats,
              conversation: DirectConversation.fromJson(
                d['conversation'] as Map<String, dynamic>,
              ),
            ),
          ),
        );
    });
  }

  void accountChanged() {
    final id = accounts?.user?.id;
    final code = accounts?.pendingRecoveryCode;
    if ((previousUserId != null && previousUserId != id) ||
        (code != null && code != previousRecoveryCode)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) navigator.currentState?.popUntil((route) => route.isFirst);
      });
    }
    previousUserId = id;
    previousRecoveryCode = code;
  }

  Widget accountHome() {
    final controller = accounts;
    if (widget.store != null || widget.previewMode || previewSelected) {
      return TomiShell(
        store: store,
        onExitPreview: !widget.previewMode && widget.store == null
            ? () => setState(() => previewSelected = false)
            : null,
      );
    }
    if (controller == null) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 40),
              const Text(
                'TOMI',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: TomiColors.accent,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'خدمة الحسابات قيد التجهيز',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'تگدر تتصفّح التصميم الآن، وتسجيل الحساب يتفعّل عند اتصال النسخة بالخدمة.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.7, color: TomiColors.muted),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() => previewSelected = true),
                child: const Text('تجربة التصميم'),
              ),
            ],
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.phase == AccountPhase.restoring) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 18),
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'نتحقق من جلسة حسابك…',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (controller.phase == AccountPhase.connectionError) {
          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 40),
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 58,
                    color: TomiColors.accent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    controller.error ?? 'تعذّر الاتصال حاليًا.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.7),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('restore-retry'),
                    onPressed: controller.restore,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        if (controller.phase == AccountPhase.signedOut)
          return AuthScreen(accounts: controller);
        if (controller.pendingRecoveryCode != null) {
          return RecoveryCodeScreen(
            code: controller.pendingRecoveryCode!,
            onSaved: controller.acknowledgeRecoveryCode,
          );
        }
        return AccountShell(
          key: ValueKey(controller.user!.id),
          accounts: controller,
        );
      },
    );
  }

  @override
  void dispose() {
    accounts?.removeListener(accountChanged);
    if (accounts != null) {
      accounts!.push.onOpen = null;
      accounts!.push.onOpenCall = null;
      accounts!.push.onOpenActivity = null;
      accounts!.calls.onShow = null;
    }
    if (widget.accounts == null) accounts?.dispose();
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TOMI',
    navigatorKey: navigator,
    navigatorObservers: [chatRouteObserver],
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => widget.textScaler == null
        ? child!
        : MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: widget.textScaler),
            child: child!,
          ),
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TomiColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TomiColors.accent,
        brightness: Brightness.dark,
        surface: TomiColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TomiColors.background,
        foregroundColor: TomiColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF10131E),
        indicatorColor: Color(0xFF3C305C),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TomiColors.raised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    ),
    home: accountHome(),
  );
}

class AccountShell extends StatefulWidget {
  const AccountShell({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<AccountShell> createState() => _AccountShellState();
}

class _AccountShellState extends State<AccountShell> {
  final store = TomiStore();
  @override
  void initState() {
    super.initState();
    synchronize();
    widget.accounts.addListener(synchronize);
  }

  void synchronize() {
    final user = widget.accounts.user;
    if (user != null &&
        (store.username != user.username ||
            store.displayName != user.displayName ||
            store.bio != user.bio)) {
      store.updateProfile(user.displayName, user.username, user.bio);
    }
  }

  @override
  void dispose() {
    widget.accounts.removeListener(synchronize);
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TomiShell(store: store, accounts: widget.accounts);
}

class TomiShell extends StatefulWidget {
  const TomiShell({
    super.key,
    required this.store,
    this.accounts,
    this.onExitPreview,
  });
  final TomiStore store;
  final AccountController? accounts;
  final VoidCallback? onExitPreview;

  @override
  State<TomiShell> createState() => _TomiShellState();
}

class _TomiShellState extends State<TomiShell> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.store,
      if (widget.accounts != null) widget.accounts!.chats,
    ]),
    builder: (context, _) => Scaffold(
      appBar:
          widget.accounts != null &&
              (selected == 0 || selected == 1 || selected == 4)
          ? null
          : AppBar(
              titleSpacing: 18,
              title: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'TOMI',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 23,
                        letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 9),
                    TinyLabel(widget.accounts == null ? 'تجريبي' : '1.1'),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'البحث',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => widget.accounts == null
                          ? SearchPage(store: widget.store)
                          : AccountSearchPage(accounts: widget.accounts!),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'الإشعارات',
                  icon: const Icon(Icons.favorite_border_rounded),
                  onPressed: () => widget.accounts == null
                      ? showInfo(
                          context,
                          'الإشعارات',
                          'أهلًا بيك في معاينة TOMI 💜',
                        )
                      : Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ActivityPage(accounts: widget.accounts!),
                          ),
                        ),
                ),
                if (widget.onExitPreview != null)
                  IconButton(
                    tooltip: 'الرجوع للحسابات',
                    onPressed: widget.onExitPreview,
                    icon: const Icon(Icons.person_outline_rounded),
                  ),
                const SizedBox(width: 7),
              ],
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (widget.accounts != null && selected == 3)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 4, 18, 0),
                child: Text(
                  'هذا القسم معاينة؛ الحساب والمنشورات والتفاعلات فعّالة.',
                  style: TextStyle(
                    color: TomiColors.muted,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  widget.accounts == null
                      ? HomeScreen(store: widget.store)
                      : SocialFeedScreen(
                          accounts: widget.accounts!,
                          visible: selected == 0,
                        ),
                  widget.accounts == null
                      ? ChatsScreen(store: widget.store)
                      : PrivateChatsScreen(accounts: widget.accounts!),
                  widget.accounts == null
                      ? RoomsScreen(store: widget.store)
                      : VoiceRoomsScreen(
                          accounts: widget.accounts!,
                          visible: selected == 2,
                        ),
                  GamesScreen(store: widget.store),
                  widget.accounts == null
                      ? ProfileScreen(store: widget.store)
                      : AccountProfileScreen(
                          accounts: widget.accounts!,
                          visible: selected == 4,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor:
            widget.accounts != null &&
                (selected == 0 || selected == 1 || selected == 4)
            ? socialBackground
            : null,
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            key: Key('nav-home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            key: Key('nav-chats'),
            icon: Badge(
              isLabelVisible: (widget.accounts?.chats.totalUnread ?? 0) > 0,
              label: Text('${widget.accounts?.chats.totalUnread ?? 0}'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'المحادثات',
          ),
          NavigationDestination(
            key: Key('nav-rooms'),
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'الغرف',
          ),
          NavigationDestination(
            key: Key('nav-games'),
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports_rounded),
            label: 'الألعاب',
          ),
          NavigationDestination(
            key: Key('nav-profile'),
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'حسابي',
          ),
        ],
      ),
    ),
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.store});
  final TomiStore store;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final results = widget.store.chats
        .where(
          (chat) => '${chat.name} ${chat.username}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('البحث عن أشخاص')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            autofocus: true,
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: 'اكتب الاسم أو اليوزر',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('ما لقينا نتيجة بهذا الاسم.'),
            ),
          for (final chat in results)
            ListTile(
              leading: Avatar(chat.name),
              title: Text(chat.name),
              subtitle: Text(
                '@${chat.username}',
                textDirection: TextDirection.ltr,
              ),
              onTap: () {
                widget.store.markRead(chat);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ChatPage(store: widget.store, chat: chat),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
