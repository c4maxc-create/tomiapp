import '../preferences/network_media_image.dart';
import '../experience/share_code_page.dart';
import '../experience/community_pages.dart';
import '../experience/experience_pages.dart';
import '../preferences/preferences_page.dart';
import '../identity/progress_cards.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../social/feed_controller.dart';
import '../social/social_screens.dart';
import '../social/social_models.dart';
import '../social/social_media.dart';
import '../social/story_screens.dart';
import '../identity/identity_screens.dart';
import '../identity/ranking_screen.dart';
import '../moderation/reports_page.dart';
import '../moderation/report_dialog.dart';
import '../privacy/privacy_screens.dart';
import '../calling/call_screens.dart';
import '../notifications/notification_settings.dart';
import '../messaging/chat_screens.dart';
import '../widgets.dart';
import 'account_controller.dart';
import 'account_models.dart';
import 'account_profile.dart';
import 'account_api.dart';
import 'account_widgets.dart';
import 'avatar_editor.dart';

class SocialProfileView extends StatefulWidget {
  const SocialProfileView({
    super.key,
    required this.accounts,
    required this.initialUser,
    this.own = false,
    this.visible = true,
  });
  final AccountController accounts;
  final AccountUser initialUser;
  final bool own, visible;
  @override
  State<SocialProfileView> createState() => _SocialProfileViewState();
}

class _SocialProfileViewState extends State<SocialProfileView> {
  late AccountUser user = widget.initialUser;
  late final feed = FeedController(
    accounts: widget.accounts,
    userId: user.id,
    scope: widget.own ? 'mine' : 'all',
  );
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.accounts.addListener(changed);
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(covariant SocialProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) unawaited(refresh());
  }

  void changed() {
    if (!mounted) return;
    if (widget.own && widget.accounts.user != null)
      user = widget.accounts.user!;
    setState(() {});
  }

  Future<void> refresh() async {
    try {
      final fresh = await widget.accounts.userById(user.id);
      if (mounted)
        setState(() {
          user = fresh;
          error = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
    await feed.refresh();
  }

  Future<void> follow() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final next = await widget.accounts.follow(user.id, !user.isFollowing);
      if (mounted) setState(() => user = next);
      await widget.accounts.home.loadStories();
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> menu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: socialSurface,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('profile-menu-settings'),
              leading: const Icon(Icons.settings_outlined),
              title: const Text('الإعدادات'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AccountSettingsPage(accounts: widget.accounts),
                  ),
                );
              },
            ),
            ListTile(
              key: const Key('profile-menu-subscriptions'),
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('الاشتراكات'),
              subtitle: const Text('VIP • الباقة الشهرية • تومبل • يوزر مميز'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SubscriptionsPage(accounts: widget.accounts),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> openPost(SocialPost p) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            SocialPostPage(accounts: widget.accounts, initialPost: p),
      ),
    );
    if (mounted) await refresh();
  }

  @override
  void dispose() {
    widget.accounts.removeListener(changed);
    feed.dispose();
    super.dispose();
  }

  Widget count(int value, String label, {VoidCallback? onTap}) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                compactCount(value),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget identityHeader(BuildContext context) {
    final avatar = StoryAvatar(
      user: user,
      size: 100,
      hasStory: widget.accounts.home.hasStory(user.id) || user.hasStory,
      unseen: widget.accounts.home.hasStory(user.id)
          ? widget.accounts.home.unseen(user.id)
          : true,
      add: widget.own,
      onTap: () => openStoryAvatar(context, widget.accounts, user),
      onAdd: () => composeStory(context, widget.accounts),
    );
    final nameText = Text(
      user.displayName,
      key: widget.own ? const Key('saved-profile-name') : null,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: Colors.white,
      ),
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nameText,
        const SizedBox(height: 6),
        TomiProgressTiles(user: user, compact: true),
      ],
    );
    final stats = Row(
      children: [
        count(
          user.postsCount,
          'منشورات',
          onTap: () {
            if (feed.posts.isNotEmpty) openPost(feed.posts.first);
          },
        ),
        count(
          user.followersCount,
          'متابعون',
          onTap: () => followers('followers'),
        ),
        count(
          user.followingCount,
          'يتابع',
          onTap: () => followers('following'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final compact =
            box.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(16) > 22;
        if (compact)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(child: name),
                ],
              ),
              const SizedBox(height: 8),
              stats,
            ],
          );
        return Row(
          children: [
            avatar,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [name, stats],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> followers(String kind) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            FollowersPage(accounts: widget.accounts, user: user, kind: kind),
      ),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: socialBackground,
    child: AnimatedBuilder(
      animation: Listenable.merge([feed, widget.accounts.home]),
      builder: (c, _) => RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(
          key: PageStorageKey('profile-${user.id}'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [TomiColors.surface, TomiColors.background],
                    ),
                    borderRadius: BorderRadius.circular(TomiRadius.card),
                    border: Border.all(color: TomiColors.border),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!widget.own)
                            IconButton(
                              tooltip: 'رجوع',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back),
                            )
                          else
                            IconButton(
                              tooltip: 'إضافة',
                              onPressed: () async {
                                await showCreateMenu(context, widget.accounts);
                                if (mounted) await refresh();
                              },
                              icon: const Icon(Icons.add, size: 30),
                            ),
                          Expanded(
                            child: Text(
                              user.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (widget.own)
                            IconButton(
                              key: const Key('profile-menu'),
                              tooltip: 'قائمة حسابي',
                              onPressed: menu,
                              icon: const Icon(Icons.menu_rounded, size: 30),
                            )
                          else
                            IconButton(
                              tooltip: 'الإبلاغ عن الحساب',
                              onPressed: () => showReportDialog(
                                context,
                                widget.accounts,
                                targetType: 'account',
                                targetId: user.id,
                                title: 'الإبلاغ عن ${user.displayName}',
                              ),
                              icon: const Icon(Icons.more_vert),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      identityHeader(context),
                      const SizedBox(height: 16),

                      if (user.bio.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 4),
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Text(
                              user.bio,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 17),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: widget.own || user.isFollowing
                                    ? socialSurface
                                    : TomiColors.accent,
                                foregroundColor: widget.own || user.isFollowing
                                    ? TomiColors.text
                                    : TomiColors.background,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 10,
                                ),
                              ),
                              key: widget.own
                                  ? const Key('edit-account')
                                  : const Key('follow-account'),
                              onPressed: busy
                                  ? null
                                  : widget.own
                                  ? () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => EditAccountPage(
                                            accounts: widget.accounts,
                                          ),
                                        ),
                                      );
                                      if (mounted) await refresh();
                                    }
                                  : follow,
                              child: Text(
                                widget.own
                                    ? 'تعديل الملف الشخصي'
                                    : busy
                                    ? 'جارٍ الحفظ…'
                                    : user.isFollowing
                                    ? 'يتابع ▾'
                                    : 'متابعة',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: socialSurface,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: widget.own
                                  ? () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ShareCodePage(
                                            url: 'tomi://profile/${user.id}',
                                            title:
                                                'مشاركة ملف ${user.displayName}',
                                          ),
                                        ),
                                      );
                                    }
                                  : () => openPrivateChat(
                                      context,
                                      widget.accounts,
                                      user.id,
                                    ),
                              child: Text(
                                widget.own ? 'مشاركة الملف الشخصي' : 'مراسلة',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (error != null) AccountErrorMessage(error!),
                      if (widget.accounts.storageWarning != null && widget.own)
                        AccountErrorMessage(widget.accounts.storageWarning!),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Column(
                children: [
                  SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Icon(
                              Icons.grid_on_rounded,
                              size: 25,
                              color: Colors.white,
                            ),
                            SizedBox(height: 12),
                            Divider(
                              height: 2,
                              thickness: 2,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: SizedBox()),
                    ],
                  ),
                  SizedBox(height: 2),
                ],
              ),
            ),
            if (feed.loading && feed.posts.isEmpty)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (feed.error != null)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    AccountErrorMessage(feed.error!),
                    TextButton(
                      onPressed: feed.refresh,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            if (feed.posts.isEmpty && !feed.loading && feed.error == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.photo_camera_outlined, size: 46),
                      SizedBox(height: 12),
                      Text('بعد ماكو منشورات'),
                    ],
                  ),
                ),
              ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate((c, i) {
                final p = feed.posts[i];
                return InkWell(
                  key: ValueKey('profile-post-${p.id}'),
                  onTap: () => openPost(p),
                  child: ColoredBox(
                    color: socialSurface,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (p.image?.url != null)
                          NetworkMediaImage(
                            p.image!.url!,
                            fit: BoxFit.cover,
                            cacheWidth: 450,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          )
                        else if (p.video != null)
                          IgnorePointer(
                            child: InlineSocialVideo(
                              video: p.video!,
                              active: widget.visible,
                              preview: true,
                              source: () async => p.video?.url == null
                                  ? null
                                  : Uri.parse(p.video!.url!),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: Text(
                                p.text,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }, childCount: feed.posts.length),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: .76,
              ),
            ),
            if (feed.nextCursor != null)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: feed.loading ? null : feed.loadMore,
                  child: const Text('عرض المزيد'),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    ),
  );
}

String compactCount(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M'
    : n >= 10000
    ? '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K'
    : n.toString();

class FollowersPage extends StatefulWidget {
  const FollowersPage({
    super.key,
    required this.accounts,
    required this.user,
    required this.kind,
  });
  final AccountController accounts;
  final AccountUser user;
  final String kind;
  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  List<AccountUser> users = [];
  String? next, error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/users/${widget.user.id}/${widget.kind}',
        query: {if (more && next != null) 'cursor': next!},
      );
      if (mounted)
        setState(() {
          final seen = users.map((x) => x.id).toSet();
          final fresh = (d['users'] as List).map(
            (x) => AccountUser.fromJson(x as Map<String, dynamic>),
          );
          users = more
              ? [...users, ...fresh.where((x) => !seen.contains(x.id))]
              : fresh.toList();
          next = d['nextCursor'] as String?;
        });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: socialBackground,
    appBar: AppBar(
      backgroundColor: socialBackground,
      title: Text(widget.kind == 'followers' ? 'المتابعون' : 'يتابع'),
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final u in users)
            ListTile(
              leading: StoryAvatar(
                user: u,
                size: 46,
                hasStory: u.hasStory,
                onTap: () => openStoryAvatar(context, widget.accounts, u),
              ),
              title: Text(u.username, textDirection: TextDirection.ltr),
              subtitle: Text(u.displayName),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => UserAccountPage(
                    accounts: widget.accounts,
                    initialUser: u,
                  ),
                ),
              ),
            ),
          if (error != null) AccountErrorMessage(error!),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            TextButton(onPressed: load, child: const Text('إعادة المحاولة')),
          if (!loading && error == null && users.isEmpty)
            const ListTile(title: Text('القائمة فارغة حاليًا')),
          if (next != null)
            TextButton(
              onPressed: loading ? null : () => load(more: true),
              child: const Text('عرض المزيد'),
            ),
        ],
      ),
    ),
  );
}

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key, required this.accounts});
  final AccountController accounts;
  void page(BuildContext c, Widget child) =>
      Navigator.push(c, MaterialPageRoute<void>(builder: (_) => child));
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: socialBackground,
    appBar: AppBar(
      backgroundColor: socialBackground,
      title: const Text('الإعدادات'),
    ),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ListTile(
          key: const Key('community-tools'),
          leading: const Icon(Icons.dashboard_customize_outlined),
          title: const Text('أدوات TOMI والدعم'),
          onTap: () => page(context, CommunityToolsPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('session-security'),
          leading: const Icon(Icons.devices),
          title: const Text('الأجهزة وأمان الحساب'),
          onTap: () => page(context, SessionSecurityPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('saved-collections'),
          leading: const Icon(Icons.folder_outlined),
          title: const Text('مجموعات المحفوظات'),
          onTap: () => page(context, SavedCollectionsPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('contact-media-settings'),
          leading: const Icon(Icons.tune),
          title: const Text('التواصل وتوفير البيانات'),
          onTap: () => page(context, PreferencesPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('saved-posts-settings'),
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('المنشورات المحفوظة'),
          onTap: () => page(
            context,
            SocialFeedScreen(
              accounts: accounts,
              initialScope: 'saved',
              title: 'المحفوظات',
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('تغيير الاسم واليوزر والبايو'),
          onTap: () => page(context, EditAccountPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('edit-avatar'),
          leading: const Icon(Icons.account_circle_outlined),
          title: const Text('تغيير الصورة الشخصية'),
          onTap: () => page(context, AvatarEditorPage(accounts: accounts)),
        ),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('تغيير كلمة المرور'),
          onTap: () => page(context, ChangePasswordPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('notification-settings'),
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('الإشعارات'),
          onTap: () => page(
            context,
            NotificationSettingsPage(controller: accounts.push),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('المنشورات المحفوظة'),
          onTap: () => page(
            context,
            SocialFeedScreen(accounts: accounts, initialScope: 'saved'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('الهوية والمظهر'),
          onTap: () => page(context, IdentityStudioPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('open-community-ranking'),
          leading: const Icon(Icons.leaderboard_outlined),
          title: const Text('نجوم تومي'),
          onTap: () =>
              page(context, ContributionRankingPage(accounts: accounts)),
        ),
        ListTile(
          key: const Key('call-history'),
          leading: const Icon(Icons.history),
          title: const Text('سجل المكالمات'),
          onTap: () => page(context, CallHistoryPage(calls: accounts.calls)),
        ),
        ModerationSettingsEntry(accounts: accounts),
        ListTile(
          key: const Key('privacy-center'),
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('الخصوصية وحذف الحساب'),
          onTap: () => page(context, PrivacyCenterPage(accounts: accounts)),
        ),
        const Divider(),
        ListTile(
          key: const Key('logout-account'),
          leading: const Icon(Icons.logout),
          title: const Text('تسجيل الخروج'),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('تسجيل الخروج؟'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('خروج'),
                  ),
                ],
              ),
            );
            if (ok != true) return;
            try {
              await accounts.logout();
              if (context.mounted)
                Navigator.popUntil(context, (r) => r.isFirst);
            } on AccountFailure catch (e) {
              if (context.mounted) showNote(context, e.message);
            }
          },
        ),
      ],
    ),
  );
}

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  List<Map<String, dynamic>> services = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/subscriptions/catalog',
      );
      if (mounted)
        setState(
          () => services = (d['services'] as List).cast<Map<String, dynamic>>(),
        );
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: socialBackground,
    appBar: AppBar(
      backgroundColor: socialBackground,
      title: const Text('الاشتراكات'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'خدمات TOMI',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('راح تتوفر التفاصيل والمزايا والأسعار عند إطلاق كل خدمة.'),
        const SizedBox(height: 20),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          AccountErrorMessage(error!),
          TextButton(onPressed: load, child: const Text('إعادة المحاولة')),
        ],
        for (final service in services)
          Card(
            color: socialSurface,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Icon(
                service['id'] == 'username'
                    ? Icons.alternate_email
                    : Icons.workspace_premium_outlined,
                color: const Color(0xFFF5CD77),
              ),
              title: Text(
                service['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(service['description'] as String),
              trailing: const Text('قريبًا'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SubscriptionDetailsPage(
                    accounts: widget.accounts,
                    service: service,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class SubscriptionDetailsPage extends StatefulWidget {
  const SubscriptionDetailsPage({
    super.key,
    required this.accounts,
    required this.service,
  });
  final AccountController accounts;
  final Map<String, dynamic> service;
  @override
  State<SubscriptionDetailsPage> createState() =>
      _SubscriptionDetailsPageState();
}

class _SubscriptionDetailsPageState extends State<SubscriptionDetailsPage> {
  final name = TextEditingController();
  bool busy = false;
  String? message;
  Future<void> check() async {
    if (busy) return;
    final validation = usernameError(name.text);
    if (validation != null) {
      setState(() => message = validation);
      return;
    }
    setState(() => busy = true);
    try {
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/subscriptions/usernames',
        query: {'username': name.text.trim()},
      );
      if (mounted) setState(() => message = d['message'] as String);
    } on AccountFailure catch (e) {
      if (mounted) setState(() => message = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: socialBackground,
    appBar: AppBar(
      backgroundColor: socialBackground,
      title: Text(widget.service['name'] as String),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(
          Icons.workspace_premium_outlined,
          size: 70,
          color: Color(0xFFF5CD77),
        ),
        const SizedBox(height: 24),
        Text(
          widget.service['name'] as String,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        const Text(
          'الخدمة قيد التجهيز. راح تنضاف التفاصيل والأسعار وطريقة الاشتراك عند الإطلاق.',
          textAlign: TextAlign.center,
        ),
        if (widget.service['id'] == 'username') ...[
          const SizedBox(height: 28),
          TextField(
            controller: name,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'اليوزر المطلوب',
              prefixText: '@',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : check,
            child: Text(busy ? 'جارٍ التحقق…' : 'فحص توفر اليوزر'),
          ),
          const Text(
            'فحص التوفر لا يحجز اليوزر ولا ينفّذ عملية شراء.',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(message!),
            ),
        ],
      ],
    ),
  );
}
