import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'chat.dart';
import 'games.dart';
import 'home.dart';
import 'model.dart';
import 'profile.dart';
import 'rooms.dart';
import 'widgets.dart';

class TomiApp extends StatefulWidget {
  const TomiApp({super.key, this.store, this.textScaler});
  final TomiStore? store;
  final TextScaler? textScaler;

  @override
  State<TomiApp> createState() => _TomiAppState();
}

class _TomiAppState extends State<TomiApp> {
  late final TomiStore store = widget.store ?? TomiStore();

  @override
  void dispose() {
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TOMI',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => widget.textScaler == null ? child! : MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: widget.textScaler), child: child!),
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TomiColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: TomiColors.accent,
        brightness: Brightness.dark, surface: TomiColors.surface),
      appBarTheme: const AppBarTheme(backgroundColor: TomiColors.background,
        foregroundColor: TomiColors.text, elevation: 0, scrolledUnderElevation: 0),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF10131E), indicatorColor: Color(0xFF3C305C),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: TomiColors.raised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    ),
    home: TomiShell(store: store),
  );
}

class TomiShell extends StatefulWidget {
  const TomiShell({super.key, required this.store});
  final TomiStore store;

  @override
  State<TomiShell> createState() => _TomiShellState();
}

class _TomiShellState extends State<TomiShell> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('TOMI', textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 23, letterSpacing: 2.8, fontWeight: FontWeight.w900)),
          SizedBox(width: 9),
          TinyLabel('تجريبي'),
        ])),
        actions: [
          IconButton(tooltip: 'البحث', icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => SearchPage(store: widget.store)))),
          IconButton(tooltip: 'الإشعارات', icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => showInfo(context, 'الإشعارات',
              'أهلًا بيك في معاينة TOMI 💜\nكل الأسماء والأرصدة والرسائل هنا تجريبية.\nتغييراتك تبقى خلال جلسة تشغيل التطبيق فقط.')),
          const SizedBox(width: 7),
        ],
      ),
      body: SafeArea(bottom: false, child: IndexedStack(index: selected, children: [
        HomeScreen(store: widget.store),
        ChatsScreen(store: widget.store),
        RoomsScreen(store: widget.store),
        GamesScreen(store: widget.store),
        ProfileScreen(store: widget.store),
      ])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(key: Key('nav-home'), icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(key: Key('nav-chats'), icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'المحادثات'),
          NavigationDestination(key: Key('nav-rooms'), icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded), label: 'الغرف'),
          NavigationDestination(key: Key('nav-games'), icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports_rounded), label: 'الألعاب'),
          NavigationDestination(key: Key('nav-profile'), icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded), label: 'حسابي'),
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
    final results = widget.store.chats.where((chat) =>
      '${chat.name} ${chat.username}'.toLowerCase().contains(query.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('البحث عن أشخاص')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        TextField(autofocus: true, onChanged: (value) => setState(() => query = value),
          decoration: const InputDecoration(hintText: 'اكتب الاسم أو اليوزر', prefixIcon: Icon(Icons.search))),
        const SizedBox(height: 16),
        if (results.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('ما لقينا نتيجة بهذا الاسم.')),
        for (final chat in results) ListTile(
          leading: Avatar(chat.name), title: Text(chat.name),
          subtitle: Text('@${chat.username}', textDirection: TextDirection.ltr),
          onTap: () {
            widget.store.markRead(chat);
            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChatPage(store: widget.store, chat: chat)));
          },
        ),
      ]),
    );
  }
}
