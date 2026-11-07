import '../messaging/video_media.dart' show readPickedVideo;
import '../preferences/network_media_image.dart';
import '../experience/experience_pages.dart';
import '../design/async_content.dart';
import 'post_share_screens.dart';
import '../identity/charisma_badge.dart';
import '../messaging/voice_note.dart' show voiceTime;
import 'story_screens.dart';
import 'social_media.dart';
import 'activity_screen.dart';

import 'package:flutter/services.dart';

import '../messaging/gallery_intent.dart';
import 'post_draft_controller.dart';
import '../messaging/chat_screens.dart';
import '../messaging/chat_models.dart';

import 'dart:async';

import '../moderation/report_dialog.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_profile.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import '../accounts/avatar_editor.dart';
import 'feed_controller.dart';
import 'social_models.dart';

const maximumImageBytes = 10 * 1024 * 1024;
String? imageContentType(Uint8List b) {
  if (b.length < 13) return null;
  if (b[0] == 255 && b[1] == 216 && b[2] == 255) return 'image/jpeg';
  if (listEquals(b.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]))
    return 'image/png';
  final gif = String.fromCharCodes(b.take(6));
  if (gif == 'GIF87a' || gif == 'GIF89a') return 'image/gif';
  if (String.fromCharCodes(b.take(4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP')
    return 'image/webp';
  return null;
}

bool pickedVideo(XFile file) =>
    (file.mimeType?.startsWith('video/') ?? false) ||
    ['.mp4', '.m4v', '.mov', '.webm'].any(file.name.toLowerCase().endsWith);

Future<ImageDraft> readPickedImage(XFile file) async {
  if (await file.length() > maximumImageBytes)
    throw const AccountFailure(
      'IMAGE_SIZE',
      'حجم الصورة أكبر من 10 MB؛ اختَر صورة أصغر.',
    );
  final b = await file.readAsBytes(), type = imageContentType(b);
  if (type == null || b.length > maximumImageBytes)
    throw const AccountFailure(
      'IMAGE_TYPE',
      'اختَر صورة JPG أو PNG أو WebP أو GIF.',
    );
  return ImageDraft(b, type);
}

String relativeTime(DateTime time) {
  final age = DateTime.now().difference(time);
  if (age.inMinutes < 1) return 'الآن';
  if (age.inHours < 1) return 'قبل ' + age.inMinutes.toString() + ' د';
  if (age.inDays < 1) return 'قبل ' + age.inHours.toString() + ' س';
  return 'قبل ' + age.inDays.toString() + ' يوم';
}

Future<void> openAuthor(
  BuildContext c,
  AccountController a,
  PostAuthor author,
) async {
  try {
    final user = await a.userById(author.id);
    if (c.mounted)
      await Navigator.push(
        c,
        MaterialPageRoute<void>(
          builder: (_) => user.id == a.user?.id
              ? Scaffold(
                  backgroundColor: socialBackground,
                  body: SafeArea(child: AccountProfileScreen(accounts: a)),
                )
              : UserAccountPage(accounts: a, initialUser: user),
        ),
      );
  } on AccountFailure catch (f) {
    if (c.mounted) showNote(c, f.message);
  }
}

class SocialFeedScreen extends StatefulWidget {
  const SocialFeedScreen({
    super.key,
    required this.accounts,
    this.userId,
    this.title,
    this.visible = true,
    this.initialScope = 'explore',
  });
  final AccountController accounts;
  final String? userId, title;
  final bool visible;
  final String initialScope;
  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen> {
  late final feed = FeedController(
    accounts: widget.accounts,
    userId: widget.userId,
    scope: widget.initialScope,
  );
  final scroll = ScrollController();
  Timer? newestTimer;
  @override
  void initState() {
    super.initState();
    scroll.addListener(maybeMore);
    newestTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (widget.visible &&
          widget.userId == null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
          (!scroll.hasClients || scroll.offset < 80)) {
        unawaited(feed.refresh(quiet: true));
      }
    });
    unawaited(feed.refresh());
    if (widget.userId == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android)
      unawaited(recoverPicker());
  }

  void maybeMore() {
    if (scroll.hasClients &&
        scroll.position.extentAfter < 600 &&
        feed.nextCursor != null &&
        !feed.loading &&
        feed.error == null)
      unawaited(feed.loadMore());
  }

  Future<void> refresh() async {
    await Future.wait([
      feed.refresh(),
      if (widget.userId == null) widget.accounts.home.refresh(),
    ]);
  }

  Future<void> recoverPicker() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      final destination = await GalleryIntent.take();
      if (!mounted ||
          lost.files?.isNotEmpty != true ||
          destination == null ||
          destination['baseUrl'] != widget.accounts.api.baseUrl ||
          destination['userId'] != widget.accounts.user?.id)
        return;
      final id = destination['conversationId'];
      if (id is String) {
        final d = await widget.accounts.chatRequest('GET', '/v1/chats/$id');
        if (mounted)
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PrivateChatPage(
                chats: widget.accounts.chats,
                conversation: DirectConversation.fromJson(
                  d['conversation'] as Map<String, dynamic>,
                ),
                initialWallpaper: destination['purpose'] == 'chat-wallpaper'
                    ? lost.files!.first
                    : null,
                initialImage:
                    destination['purpose'] == 'chat-video' ||
                        destination['purpose'] == 'chat-wallpaper'
                    ? null
                    : lost.files!.first,
                initialVideo: destination['purpose'] == 'chat-video'
                    ? lost.files!.first
                    : null,
              ),
            ),
          );
      } else if (destination['purpose'] == 'story' ||
          destination['purpose'] == 'story-video' ||
          destination['purpose'] == 'story-media') {
        await composeStory(
          context,
          widget.accounts,
          initialImage:
              destination['purpose'] == 'story' ||
                  destination['purpose'] == 'story-media' &&
                      !pickedVideo(lost.files!.first)
              ? lost.files!.first
              : null,
          initialVideo:
              destination['purpose'] == 'story-video' ||
                  destination['purpose'] == 'story-media' &&
                      pickedVideo(lost.files!.first)
              ? lost.files!.first
              : null,
        );
      } else if (destination['purpose'] == 'avatar') {
        if (mounted)
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AvatarEditorPage(
                accounts: widget.accounts,
                initialImage: lost.files!.first,
              ),
            ),
          );
      } else if (destination['purpose'] == null ||
          destination['purpose'] == 'feed' ||
          destination['purpose'] == 'feed-video' ||
          destination['purpose'] == 'feed-media') {
        await compose(
          initialImage:
              destination['purpose'] == 'feed-video' ||
                  destination['purpose'] == 'feed-media' &&
                      pickedVideo(lost.files!.first)
              ? null
              : lost.files!.first,
          initialVideo:
              destination['purpose'] == 'feed-video' ||
                  destination['purpose'] == 'feed-media' &&
                      pickedVideo(lost.files!.first)
              ? lost.files!.first
              : null,
        );
      }
    } catch (_) {
      /* No pending selection on this platform. */
    }
  }

  Future<void> compose({XFile? initialImage, XFile? initialVideo}) async {
    if (initialImage == null && initialVideo == null) {
      try {
        await GalleryIntent.remember(
          widget.accounts.api.baseUrl,
          widget.accounts.user!.id,
          purpose: 'feed-media',
        );
        final file = await ImagePicker().pickMedia();
        await GalleryIntent.clear();
        if (!mounted) return;
        if (file != null) {
          final name = file.name.toLowerCase();
          if (['.mp4', '.mov', '.m4v', '.webm'].any(name.endsWith)) {
            initialVideo = file;
          } else {
            initialImage = file;
          }
        }
      } catch (_) {
        if (mounted)
          showNote(
            context,
            'تعذّر فتح الاستوديو؛ تگدر تختار الملف من نافذة النشر.',
          );
      }
    }
    final p = await showModalBottomSheet<SocialPost>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => SocialComposer(
        accounts: widget.accounts,
        imageEnabled: initialImage != null || feed.imageUploadEnabled,
        initialImage: initialImage,
        initialVideo: initialVideo,
        videoEnabled: feed.videoUploadEnabled,
      ),
    );
    if (mounted && p != null) {
      feed.add(p);
      showNote(context, 'تم نشر منشورك 💜');
    }
  }

  Future<void> mutate(Future<void> Function() work) async {
    try {
      await work();
    } on AccountFailure catch (f) {
      if (mounted) showNote(context, f.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر حفظ التغيير؛ جرّب مرة ثانية.');
    }
  }

  @override
  void dispose() {
    newestTimer?.cancel();
    scroll.dispose();
    feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: socialBackground,
    child: AnimatedBuilder(
      animation: Listenable.merge([feed, widget.accounts.home]),
      builder: (context, _) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView.builder(
          controller: scroll,
          key: PageStorageKey('social-${widget.userId ?? 'home'}'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: feed.posts.length + 2,
          itemBuilder: (c, index) {
            if (index == 0)
              return Column(
                children: [
                  if (widget.userId == null) ...[
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(5, 3, 7, 5),
                        child: Row(
                          children: [
                            IconButton(
                              key: const Key('compose-post'),
                              tooltip: 'إضافة',
                              onPressed: () => compose(),
                              icon: const Icon(
                                Icons.add,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'TOMI',
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                  color: TomiColors.text,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'البحث',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => UnifiedSearchPage(
                                    accounts: widget.accounts,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.search_rounded),
                            ),
                            IconButton(
                              tooltip: 'الإشعارات',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ActivityPage(accounts: widget.accounts),
                                ),
                              ),
                              icon: Badge(
                                isLabelVisible:
                                    widget.accounts.home.unreadCount > 0,
                                smallSize: 7,
                                child: const Icon(
                                  Icons.favorite_border_rounded,
                                  size: 29,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    StoriesStrip(accounts: widget.accounts),
                  ] else
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        widget.title ?? 'المنشورات',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (widget.userId == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'following',
                            label: Text('أتابعهم'),
                          ),
                          ButtonSegment(
                            value: 'explore',
                            label: Text('استكشاف'),
                          ),
                        ],
                        selected: {
                          feed.scope == 'following' ? 'following' : 'explore',
                        },
                        onSelectionChanged: (v) => feed.select(v.first),
                      ),
                    ),
                  if (feed.loading && feed.posts.isEmpty)
                    const TomiSkeleton(rows: 2),
                  if (feed.posts.isEmpty && !feed.loading && feed.error == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 60,
                        horizontal: 24,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            size: 48,
                            color: Colors.white70,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'بعد ماكو منشورات هنا',
                            style: TextStyle(fontSize: 17),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'شارك لحظة أو تابع أصدقاءك حتى تظهر منشوراتهم.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            if (index == feed.posts.length + 1)
              return Column(
                children: [
                  if (feed.error != null) ...[
                    AccountErrorMessage(feed.error!),
                    TextButton(
                      key: const Key('feed-retry'),
                      onPressed: feed.loading
                          ? null
                          : feed.nextCursor == null
                          ? feed.refresh
                          : feed.loadMore,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                  if (feed.loading && feed.posts.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(),
                    ),
                  if (feed.nextCursor != null && !feed.loading)
                    TextButton(
                      onPressed: feed.loadMore,
                      child: const Text('عرض المزيد'),
                    ),
                ],
              );
            final p = feed.posts[index - 1];
            return RealPostCard(
              key: ValueKey(p.id),
              accounts: widget.accounts,
              post: p,
              active: widget.visible,
              busy: feed.busyPosts.contains(p.id),
              onLike: () => mutate(() => feed.like(p)),
              onDelete: () => mutate(() => feed.delete(p)),
              onUpdated: feed.replace,
            );
          },
        ),
      ),
    ),
  );
}

Future<void> showCreateMenu(
  BuildContext context,
  AccountController accounts, {
  Future<void> Function()? onPost,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: socialSurface,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.grid_on_outlined),
            title: const Text('منشور جديد'),
            onTap: () => Navigator.pop(c, 'post'),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('ستوري جديدة'),
            onTap: () => Navigator.pop(c, 'story'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'story') {
    await composeStory(context, accounts);
  } else if (action == 'post') {
    if (onPost != null) {
      await onPost();
      return;
    }
    try {
      final d = await accounts.chatRequest('GET', '/v1/media/status');
      if (!context.mounted) return;
      await showModalBottomSheet<SocialPost>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: true,
        builder: (_) => SocialComposer(
          accounts: accounts,
          imageEnabled: d['imageUploadEnabled'] == true,
          videoEnabled: d['videoUploadEnabled'] == true,
        ),
      );
    } on AccountFailure catch (e) {
      if (context.mounted) showNote(context, e.message);
    }
  }
}

class RealPostCard extends StatelessWidget {
  const RealPostCard({
    super.key,
    required this.accounts,
    required this.post,
    required this.busy,
    required this.onLike,
    required this.onDelete,
    required this.onUpdated,
    this.active = true,
  });
  final AccountController accounts;
  final SocialPost post;
  final bool busy, active;
  final VoidCallback onLike, onDelete;
  final ValueChanged<SocialPost> onUpdated;
  Future<void> confirmDelete(BuildContext c) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('حذف المنشور؟'),
        content: const Text('راح ينحذف المنشور وتعليقاته.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true && c.mounted) onDelete();
  }

  Future<void> editPost(BuildContext c) async {
    final input = TextEditingController(text: post.text);
    String audience = post.audience;
    final yes = await showDialog<bool>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('تعديل المنشور'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: input,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'الوصف'),
                ),
                DropdownButton<String>(
                  isExpanded: true,
                  value: audience,
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('عام')),
                    DropdownMenuItem(
                      value: 'followers',
                      child: Text('للمتابعين بالرئيسية'),
                    ),
                  ],
                  onChanged: (v) => set(() => audience = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (yes == true) {
      try {
        final d = await accounts.chatRequest(
          'PUT',
          '/v1/posts/${post.id}',
          body: {
            'text': input.text,
            'audience': audience,
            'expectedRevision': post.revision,
          },
        );
        onUpdated(SocialPost.fromJson(d['post'] as Map<String, dynamic>));
      } on AccountFailure catch (e) {
        if (c.mounted) showNote(c, e.message);
      }
    }
    input.dispose();
  }

  Future<void> save(BuildContext c) async {
    try {
      final d = await accounts.chatRequest(
        'PUT',
        '/v1/posts/${post.id}/save',
        body: {'saved': !post.saved},
      );
      onUpdated(SocialPost.fromJson(d['post'] as Map<String, dynamic>));
    } on AccountFailure catch (e) {
      if (c.mounted) showNote(c, e.message);
    }
  }

  void comments(BuildContext c) => showModalBottomSheet<void>(
    context: c,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) =>
        RealCommentsSheet(accounts: accounts, post: post, onUpdated: onUpdated),
  );
  Future<void> share(BuildContext c) =>
      showPostShareSheet(c, accounts, post.id);
  @override
  Widget build(BuildContext c) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
    decoration: BoxDecoration(
      color: TomiColors.surface,
      borderRadius: BorderRadius.circular(TomiRadius.card),
      border: Border.all(color: TomiColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: accounts.home,
                    builder: (c, _) => StoryAvatar(
                      user: post.author.avatarUser,
                      size: 38,
                      hasStory:
                          post.author.hasStory ||
                          accounts.home.hasStory(post.author.id),
                      unseen: accounts.home.hasStory(post.author.id)
                          ? accounts.home.unseen(post.author.id)
                          : true,
                      onTap: () =>
                          openStoryAvatar(c, accounts, post.author.avatarUser),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: InkWell(
                      onTap: () => openAuthor(c, accounts, post.author),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.author.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            post.author.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          CharismaBadge(post.author.identity),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'تخصيص الاستكشاف',
                    icon: const Icon(Icons.tune),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'post',
                        child: Text('مو مهتم بهذا المنشور'),
                      ),
                      PopupMenuItem(
                        value: 'user',
                        child: Text('إخفاء هذا الحساب من الاستكشاف'),
                      ),
                    ],
                    onSelected: (kind) async {
                      try {
                        await accounts.chatRequest(
                          'PUT',
                          '/v1/me/explore-hidden',
                          body: {
                            'type': kind,
                            'id': kind == 'post' ? post.id : post.author.id,
                          },
                        );
                        if (c.mounted)
                          showNote(
                            c,
                            'تم إخفاؤه من الاستكشاف؛ اسحب لتحديث القائمة.',
                          );
                      } on AccountFailure catch (f) {
                        if (c.mounted) showNote(c, f.message);
                      } catch (_) {
                        if (c.mounted) showNote(c, 'تعذّر الحفظ.');
                      }
                    },
                  ),
                  IconButton(
                    key: post.isMine
                        ? Key('delete-post-${post.id}')
                        : ValueKey('report-post-${post.id}'),
                    tooltip: post.isMine ? 'حذف المنشور' : 'إبلاغ الإدارة',
                    onPressed: busy
                        ? null
                        : () => post.isMine
                              ? confirmDelete(c)
                              : showReportDialog(
                                  c,
                                  accounts,
                                  targetType: 'post',
                                  targetId: post.id,
                                  title:
                                      'الإبلاغ عن منشور ${post.author.displayName}',
                                ),
                    icon: const Icon(Icons.more_horiz, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          if (post.video != null)
            InlineSocialVideo(
              video: post.video!,
              active: active && !accounts.liveAudioBusy,
              source: () async {
                final d = await accounts.chatRequest(
                  'GET',
                  '/v1/posts/${post.id}',
                );
                final p = SocialPost.fromJson(
                  d['post'] as Map<String, dynamic>,
                );
                final url = await p.video?.playbackUrl();
                return url == null ? null : Uri.parse(url);
              },
            ),
          if (post.image != null)
            GestureDetector(
              onDoubleTap: busy || post.liked ? null : onLike,
              onTap: () => Navigator.push(
                c,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(
                      backgroundColor: Colors.black,
                      title: Text(post.author.username),
                    ),
                    body: Center(
                      child: InteractiveViewer(
                        child: NetworkMediaImage(
                          post.image!.url ?? '',
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Text('تعذّر تحميل الصورة'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: AspectRatio(
                aspectRatio: (post.image!.width / post.image!.height)
                    .clamp(.8, 1.91)
                    .toDouble(),
                child: post.image!.url == null
                    ? const ColoredBox(
                        color: socialSurface,
                        child: Icon(Icons.image_not_supported_outlined),
                      )
                    : NetworkMediaImage(
                        post.image!.url!,
                        fit: BoxFit.cover,
                        cacheWidth: 1200,
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : const ColoredBox(
                                color: socialSurface,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: socialSurface,
                          child: Center(
                            child: Text('تعذّر تحميل الصورة؛ اسحب للتحديث.'),
                          ),
                        ),
                      ),
              ),
            ),
          if (post.image == null && post.video == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
              child: Text(
                post.text,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.65,
                  color: Colors.white,
                ),
              ),
            ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Row(
                children: [
                  IconButton(
                    key: Key('like-${post.id}'),
                    tooltip: post.liked ? 'إلغاء الإعجاب' : 'إعجاب',
                    onPressed: busy ? null : onLike,
                    icon: Icon(
                      post.liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 27,
                      color: post.liked
                          ? const Color(0xFFFF345F)
                          : Colors.white,
                    ),
                  ),
                  IconButton(
                    key: Key('comments-${post.id}'),
                    tooltip: 'التعليقات',
                    onPressed: () => comments(c),
                    icon: const Icon(
                      Icons.mode_comment_outlined,
                      size: 25,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: 'مشاركة المنشور',
                    onPressed: () => share(c),
                    icon: const Icon(
                      Icons.send_outlined,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  if (post.isMine)
                    IconButton(
                      key: Key('edit-post-${post.id}'),
                      tooltip: 'تعديل المنشور',
                      onPressed: busy ? null : () => editPost(c),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  if (post.saved)
                    IconButton(
                      tooltip: 'أضف إلى مجموعة',
                      icon: const Icon(Icons.create_new_folder_outlined),
                      onPressed: () => Navigator.push(
                        c,
                        MaterialPageRoute<void>(
                          builder: (_) => SavedCollectionsPage(
                            accounts: accounts,
                            postId: post.id,
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    key: Key('save-${post.id}'),
                    tooltip: post.saved ? 'إلغاء الحفظ' : 'حفظ المنشور',
                    onPressed: busy ? null : () => save(c),
                    icon: Icon(
                      post.saved ? Icons.bookmark : Icons.bookmark_border,
                      size: 27,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${post.likesCount} إعجاب',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                if (post.text.isNotEmpty &&
                    (post.image != null || post.video != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${post.author.username}  ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: post.text),
                        ],
                      ),
                      style: const TextStyle(
                        height: 1.5,
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (post.commentsCount > 0)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      foregroundColor: Colors.white54,
                    ),
                    onPressed: () => comments(c),
                    child: Text(
                      'عرض التعليقات (${post.commentsCount})',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                Text(
                  relativeTime(post.createdAt),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> shareSocialText(BuildContext c, String text) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await const MethodChannel(
        'tomi/mobile',
      ).invokeMethod<void>('shareText', {'text': text});
      return;
    } catch (_) {}
  }
  await Clipboard.setData(ClipboardData(text: text));
  if (c.mounted) showNote(c, 'تم النسخ للمشاركة');
}

class SocialPostPage extends StatefulWidget {
  const SocialPostPage({
    super.key,
    required this.accounts,
    required this.initialPost,
    this.showComments = false,
  });
  final AccountController accounts;
  final SocialPost initialPost;
  final bool showComments;
  @override
  State<SocialPostPage> createState() => _SocialPostPageState();
}

class _SocialPostPageState extends State<SocialPostPage> {
  late SocialPost post = widget.initialPost;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.showComments)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => RealCommentsSheet(
              accounts: widget.accounts,
              post: post,
              onUpdated: (p) {
                if (mounted) setState(() => post = p);
              },
            ),
          );
      });
  }

  Future<void> mutate(bool delete) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (delete) {
        await widget.accounts.deletePost(post.id);
        if (mounted) Navigator.pop(context);
      } else {
        final next = await widget.accounts.likePost(post.id, !post.liked);
        if (mounted) setState(() => post = next);
      }
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: socialBackground,
    appBar: AppBar(
      backgroundColor: socialBackground,
      title: Text(post.author.username),
    ),
    body: SingleChildScrollView(
      child: RealPostCard(
        accounts: widget.accounts,
        post: post,
        busy: busy,
        onLike: () => mutate(false),
        onDelete: () => mutate(true),
        onUpdated: (p) => setState(() => post = p),
      ),
    ),
  );
}

class SocialComposer extends StatefulWidget {
  const SocialComposer({
    super.key,
    required this.accounts,
    required this.imageEnabled,
    this.initialImage,
    this.initialVideo,
    this.videoEnabled = false,
  });
  final AccountController accounts;
  final bool imageEnabled, videoEnabled;
  final XFile? initialImage, initialVideo;
  @override
  State<SocialComposer> createState() => _SocialComposerState();
}

class _SocialComposerState extends State<SocialComposer> {
  final text = TextEditingController();
  late final draft = PostDraftController(widget.accounts);
  bool picking = false, closing = false;
  String? pickerError, videoPath;
  @override
  void initState() {
    super.initState();
    draft.addListener(changed);
    unawaited(initialize());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> initialize() async {
    await draft.restored;
    if (!mounted) return;
    text.text = draft.item.text;
    if (widget.initialImage != null) await load(widget.initialImage!, false);
    if (widget.initialVideo != null) await load(widget.initialVideo!, true);
    changed();
  }

  Future<void> load(XFile file, bool video) async {
    if (draft.locked) {
      pickerError =
          'توجد مسودة تنتظر التحقق؛ أعد المحاولة أو ألغِ إعادة محاولتها قبل استبدالها.';
      changed();
      return;
    }
    if (mounted) setState(() => picking = true);
    try {
      final media = video
          ? await readPickedVideo(file)
          : await readPickedImage(file);
      if (!mounted || !draft.current) return;
      await draft.attachment(media);
      videoPath = null;
      pickerError = null;
    } on AccountFailure catch (e) {
      pickerError = e.message;
    } catch (_) {
      pickerError = 'تعذّر فتح المرفق أو حفظه على الجهاز.';
    } finally {
      if (mounted) setState(() => picking = false);
    }
    changed();
  }

  Future<void> pick({bool video = false}) async {
    if (draft.locked || picking) return;
    setState(() {
      picking = true;
      pickerError = null;
    });
    try {
      await GalleryIntent.remember(
        widget.accounts.api.baseUrl,
        widget.accounts.user!.id,
        purpose: video ? 'feed-video' : 'feed',
      );
      final file = video
          ? await ImagePicker().pickVideo(source: ImageSource.gallery)
          : await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 2400,
              maxHeight: 2400,
              imageQuality: 90,
              requestFullMetadata: false,
            );
      await GalleryIntent.clear();
      if (file != null && mounted && draft.current) await load(file, video);
    } catch (_) {
      pickerError = 'تعذّر فتح المعرض.';
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> close() async {
    if (draft.busy || picking || closing) return;
    try {
      await draft.persist();
      if (!mounted) return;
      closing = true;
      Navigator.pop(context);
    } catch (_) {
      pickerError = 'تعذّر حفظ المسودة؛ أبقِ الصفحة مفتوحة وأعد المحاولة.';
      changed();
    }
  }

  Future<void> publish() async {
    final prior = draft.item.requestId;
    final post = await draft.publish();
    if (mounted && post == null && draft.item.requestId != prior)
      text.text = draft.item.text;
    if (mounted && post != null) {
      closing = true;
      Navigator.pop(context, post);
    }
  }

  Future<void> discard() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إلغاء إعادة المحاولة؟'),
        content: const Text(
          'تُزال المسودة من الجهاز. إذا سبق أن نجح النشر، يبقى المنشور في صفحتك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إزالة المسودة'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await draft.clear();
      if (mounted) {
        text.clear();
        changed();
      }
    } catch (_) {
      pickerError = 'تعذّر إزالة المسودة.';
      changed();
    }
  }

  @override
  void dispose() {
    draft.removeListener(changed);
    draft.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final media = draft.item.media, locked = draft.locked || picking;
    return PopScope(
      canPop: closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(close());
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'شارك لحظتك',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'حفظ وإغلاق',
                      onPressed: draft.busy || picking ? null : close,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (draft.loading) const LinearProgressIndicator(),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('post-input'),
                  controller: text,
                  enabled: !locked,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  onChanged: draft.editText,
                  decoration: InputDecoration(
                    labelText: media is VideoDraft
                        ? 'وصف الفيديو'
                        : 'وصف المنشور',
                    hintText: 'شنو تحب تشارك اليوم؟',
                  ),
                ),
                if (media is VideoDraft)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: videoPath == null
                        ? Column(
                            children: [
                              if (media.posterBytes != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(
                                    media.posterBytes!,
                                    height: 180,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              Text('🎬 فيديو • ${voiceTime(media.durationMs)}'),
                            ],
                          )
                        : InlineSocialVideo(
                            key: ValueKey(videoPath),
                            video: PostVideo({
                              'width': media.width,
                              'height': media.height,
                              'durationMs': media.durationMs,
                            }),
                            source: () async => Uri.file(videoPath!),
                            preview: true,
                          ),
                  )
                else if (media != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      media.bytes,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('تعذّر عرض معاينة الصورة'),
                    ),
                  ),
                if (media != null)
                  TextButton.icon(
                    onPressed: locked
                        ? null
                        : () => draft.attachment(null).catchError((Object _) {
                            pickerError = 'تعذّر إزالة المرفق.';
                            changed();
                          }),
                    icon: const Icon(Icons.close),
                    label: const Text('إزالة المرفق'),
                  ),
                OutlinedButton.icon(
                  key: const Key('pick-post-image'),
                  onPressed: locked || !widget.imageEnabled
                      ? null
                      : () => pick(),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(picking ? 'جارٍ تجهيز الملف…' : 'إضافة صورة'),
                ),
                if (widget.videoEnabled)
                  OutlinedButton.icon(
                    key: const Key('pick-post-video'),
                    onPressed: locked ? null : () => pick(video: true),
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('إضافة فيديو'),
                  ),
                const Text(
                  'المسودة تُحفظ على هذا الجهاز.',
                  style: TextStyle(fontSize: 11, color: TomiColors.muted),
                ),
                if (pickerError ?? draft.error case final String error)
                  AccountErrorMessage(error),
                if (draft.busy) ...[
                  LinearProgressIndicator(
                    value: draft.transfer?.active == true
                        ? draft.transfer?.progress
                        : null,
                  ),
                  if (draft.transfer?.active == true)
                    TextButton.icon(
                      onPressed: draft.cancelUpload,
                      icon: const Icon(Icons.close),
                      label: Text(
                        'إيقاف الرفع • ${((draft.transfer?.progress ?? 0) * 100).round()}%',
                      ),
                    ),
                  const Text(
                    'جارٍ التحقق والرفع والنشر…',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: draft.audience,
                  decoration: const InputDecoration(labelText: 'جمهور المنشور'),
                  items: const [
                    DropdownMenuItem(
                      value: 'public',
                      child: Text(
                        'عام • للجميع',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'followers',
                      child: Text(
                        'للمتابعين',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: draft.locked
                      ? null
                      : (v) => draft.selectAudience(v!),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'اختيار المتابعين يحدد ظهوره بالرئيسية، وليس خصوصية الحساب الشخصي.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('publish-post'),
                  onPressed:
                      draft.loading ||
                          draft.busy ||
                          picking ||
                          !draft.storageReady
                      ? null
                      : publish,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    draft.busy
                        ? 'جارٍ النشر…'
                        : draft.item.commitAttempted
                        ? 'إعادة المحاولة والتحقق'
                        : 'نشر',
                  ),
                ),
                if (draft.item.commitAttempted)
                  TextButton(
                    onPressed: draft.busy ? null : discard,
                    child: const Text('إلغاء إعادة المحاولة'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RealCommentsSheet extends StatefulWidget {
  const RealCommentsSheet({
    super.key,
    required this.accounts,
    required this.post,
    required this.onUpdated,
  });
  final AccountController accounts;
  final SocialPost post;
  final ValueChanged<SocialPost> onUpdated;
  @override
  State<RealCommentsSheet> createState() => _RealCommentsSheetState();
}

class _RealCommentsSheetState extends State<RealCommentsSheet> {
  final text = TextEditingController();
  List<SocialComment> comments = [];
  SocialComment? replying;
  String? replyingRoot;
  final focus = FocusNode();
  final expanded = <String>{}, replyLoading = <String>{};
  final replies = <String, List<SocialComment>>{};
  final replyCursors = <String, String?>{};
  final replyEpoch = <String, int>{};
  bool threaded = false;
  String rootOf(SocialComment value) {
    if (value.rootId != null) return value.rootId!;
    final map = {for (final item in comments) item.id: item};
    var current = value;
    final visited = <String>{};
    while (current.parentId != null &&
        map.containsKey(current.parentId) &&
        visited.add(current.id))
      current = map[current.parentId]!;
    return current.id;
  }

  List<SocialComment> childrenOf(String id) => threaded
      ? (replies[id] ?? [])
      : comments.where((c) => c.id != id && rootOf(c) == id).toList();
  void replyTo(SocialComment value, String root) {
    setState(() {
      replying = value;
      replyingRoot = root;
      requestId = newRequestId();
    });
    focus.requestFocus();
  }

  Future<void> loadReplies(
    String id, {
    bool more = false,
    bool reset = false,
  }) async {
    if (!threaded || (!reset && replyLoading.contains(id))) return;
    replyLoading.add(id);
    final generation = replyEpoch[id] = (replyEpoch[id] ?? 0) + 1;
    setState(() => expanded.add(id));
    try {
      final page = await widget.accounts.comments(
        widget.post.id,
        parentId: id,
        threaded: true,
        cursor: more ? replyCursors[id] : null,
      );
      if (mounted && replyEpoch[id] == generation)
        setState(() {
          final merged = {
            for (final c
                in reset ? <SocialComment>[] : replies[id] ?? <SocialComment>[])
              c.id: c,
            for (final c in page.comments) c.id: c,
          };
          replies[id] = merged.values.toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          replyCursors[id] = page.nextCursor;
          if (page.root != null)
            comments = comments
                .map((c) => c.id == id ? page.root! : c)
                .toList();
        });
    } on AccountFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحميل الردود؛ أعد المحاولة.');
    } finally {
      if (mounted && replyEpoch[id] == generation)
        setState(() => replyLoading.remove(id));
    }
  }

  String? cursor, error;
  String requestId = newRequestId();
  bool loading = false, sending = false;
  final deleting = <String>{};
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
      final p = await widget.accounts.comments(
        widget.post.id,
        cursor: more ? cursor : null,
        threaded: true,
      );
      if (mounted)
        setState(() {
          threaded = p.threaded;
          final seen = comments.map((v) => v.id).toSet();
          comments = more
              ? [...comments, ...p.comments.where((v) => !seen.contains(v.id))]
              : p.comments;
          cursor = p.nextCursor;
        });
    } on AccountFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر تحميل التعليقات؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    if (sending || text.text.trim().isEmpty) return;
    setState(() {
      sending = true;
      error = null;
    });
    final root = replyingRoot;
    try {
      final r = await widget.accounts.addComment(
        widget.post.id,
        text.text,
        requestId,
        parentId: replying?.id,
      );
      if (mounted) {
        setState(() {
          if (root == null || !threaded)
            comments = [
              r.comment,
              ...comments.where((c) => c.id != r.comment.id),
            ];
          else {
            replies[root] = [...replies[root] ?? <SocialComment>[], r.comment]
                .fold<List<SocialComment>>([], (all, c) {
                  if (!all.any((v) => v.id == c.id)) all.add(c);
                  return all;
                });
            expanded.add(root);
          }
        });
        text.clear();
        replying = null;
        replyingRoot = null;
        if (root != null && threaded) unawaited(loadReplies(root));
        requestId = newRequestId();
        widget.onUpdated(r.post);
      }
    } on AccountFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر إرسال التعليق؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> remove(SocialComment v, {String? threadRoot}) async {
    if (v.replyCount > 0 || childrenOf(v.id).isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('حذف التعليق وردوده؟'),
          content: const Text('تنحذف الردود التابعة لهذا التعليق أيضاً.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!deleting.add(v.id)) return;
    setState(() {});
    try {
      final p = await widget.accounts.deleteComment(v.id);
      if (mounted) {
        setState(() {
          comments.removeWhere((c) => c.id == v.id);
          replies.remove(v.id);
          expanded.remove(v.id);
          for (final list in replies.values)
            list.removeWhere((c) => c.id == v.id || c.parentId == v.id);
          if (replying?.id == v.id || replyingRoot == v.id) {
            replying = null;
            replyingRoot = null;
          }
        });
        if (v.parentId != null && threadRoot != null)
          unawaited(loadReplies(threadRoot, reset: true));
        widget.onUpdated(p);
      }
    } on AccountFailure catch (f) {
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر حذف التعليق؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => deleting.remove(v.id));
    }
  }

  Widget commentRow(SocialComment value, String root, {bool nested = false}) =>
      Padding(
        key: ValueKey('comment-row-${value.id}'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccountAvatar(value.author.avatarUser, size: nested ? 26 : 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.author.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (value.replyToUsername != null)
                          TextSpan(
                            text: '@${value.replyToUsername} ',
                            style: const TextStyle(color: TomiColors.accent),
                          ),
                        TextSpan(text: value.text),
                      ],
                    ),
                    style: const TextStyle(height: 1.5),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        relativeTime(value.createdAt),
                        style: const TextStyle(
                          color: TomiColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      TextButton(
                        key: ValueKey('reply-comment-${value.id}'),
                        onPressed: sending ? null : () => replyTo(value, root),
                        child: const Text('رد'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (value.isMine || widget.post.isMine)
              IconButton(
                tooltip: 'حذف التعليق',
                onPressed: deleting.contains(value.id)
                    ? null
                    : () => remove(value, threadRoot: root),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
          ],
        ),
      );

  @override
  void dispose() {
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(c).height * .82,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          16 + MediaQuery.viewInsetsOf(c).bottom,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: SizedBox(
              height: constraints.maxHeight.clamp(
                MediaQuery.textScalerOf(c).scale(280).clamp(360.0, 840.0),
                double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'التعليقات',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'تحديث',
                        onPressed: loading ? null : load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (replying != null)
                    ListTile(
                      dense: true,
                      title: Text(
                        'رد على ${replying!.author.displayName}',
                        maxLines: 1,
                      ),
                      trailing: IconButton(
                        onPressed: () => setState(() {
                          replying = null;
                          replyingRoot = null;
                          requestId = newRequestId();
                        }),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  if (loading || sending) const TomiSkeleton(rows: 2),
                  Expanded(
                    child: ListView(
                      children: [
                        if (error != null) AccountErrorMessage(error!),
                        if (comments.isEmpty && !loading && error == null)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'كن أول من يعلّق 💜',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final v in comments.where(
                          (c) => threaded || rootOf(c) == c.id,
                        ))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              commentRow(v, v.id),
                              if (v.replyCount > 0 ||
                                  childrenOf(v.id).isNotEmpty ||
                                  expanded.contains(v.id))
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 44,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TextButton(
                                        key: ValueKey('toggle-replies-${v.id}'),
                                        onPressed: () => setState(() {
                                          if (!expanded.remove(v.id)) {
                                            expanded.add(v.id);
                                            if (threaded &&
                                                !replies.containsKey(v.id))
                                              unawaited(loadReplies(v.id));
                                          }
                                        }),
                                        child: Text(
                                          expanded.contains(v.id)
                                              ? 'إخفاء الردود'
                                              : 'عرض الردود (${v.replyCount > childrenOf(v.id).length ? v.replyCount : childrenOf(v.id).length})',
                                        ),
                                      ),
                                      if (expanded.contains(v.id)) ...[
                                        for (final reply in childrenOf(v.id))
                                          commentRow(reply, v.id, nested: true),
                                        if (replyLoading.contains(v.id))
                                          const LinearProgressIndicator(),
                                        if (replyCursors[v.id] != null)
                                          TextButton(
                                            onPressed:
                                                replyLoading.contains(v.id)
                                                ? null
                                                : () => loadReplies(
                                                    v.id,
                                                    more: true,
                                                  ),
                                            child: const Text('عرض ردود أكثر'),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        if (cursor != null)
                          TextButton(
                            onPressed: loading ? null : () => load(more: true),
                            child: const Text('تعليقات أقدم'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('comment-input'),
                          focusNode: focus,
                          controller: text,
                          enabled: !sending,
                          minLines: 1,
                          maxLines: 3,
                          maxLength: 500,
                          onChanged: (_) => requestId = newRequestId(),
                          decoration: const InputDecoration(
                            hintText: 'اكتب تعليقك',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const Key('send-comment'),
                        tooltip: 'إرسال التعليق',
                        onPressed: sending ? null : send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
