import '../messaging/gallery_intent.dart';
import '../messaging/chat_screens.dart';
import '../messaging/chat_models.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_profile.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
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
                  appBar: AppBar(title: const Text('حسابي')),
                  body: AccountProfileScreen(accounts: a),
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
  });
  final AccountController accounts;
  final String? userId, title;
  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen> {
  late final feed = FeedController(
    accounts: widget.accounts,
    userId: widget.userId,
  );
  @override
  void initState() {
    super.initState();
    unawaited(feed.refresh());
    if (widget.userId == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android)
      unawaited(recoverPicker());
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
                initialImage: lost.files!.first,
              ),
            ),
          );
      } else {
        await compose(initialImage: lost.files!.first);
      }
    } catch (_) {
      /* No pending selection on this platform. */
    }
  }

  Future<void> compose({XFile? initialImage}) async {
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
    feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: feed,
    builder: (context, _) => RefreshIndicator(
      onRefresh: feed.refresh,
      child: ListView(
        key: PageStorageKey('social-' + (widget.userId ?? 'home')),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title ?? 'لحظاتك أقرب',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'شارك لحظتك مع مجتمع TOMI',
                      style: TextStyle(color: TomiColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (widget.userId == null)
                IconButton.filledTonal(
                  key: const Key('compose-post'),
                  tooltip: 'منشور جديد',
                  onPressed: compose,
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (widget.userId == null) ...[
            const TomiCard(
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: TomiColors.gold),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'كلمة، صورة، أو لحظة حلوة… شاركها ويانا 💜',
                      style: TextStyle(height: 1.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in {
                  'all': 'عام',
                  'following': 'متابعاتي',
                  'mine': 'منشوراتي',
                }.entries)
                  ChoiceChip(
                    key: Key('feed-' + e.key),
                    label: Text(e.value),
                    selected: feed.scope == e.key,
                    onSelected: (_) => feed.select(e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (feed.loading) const LinearProgressIndicator(minHeight: 2),
          if (feed.error != null) ...[
            AccountErrorMessage(feed.error!),
            OutlinedButton.icon(
              key: const Key('feed-retry'),
              onPressed: feed.loading ? null : feed.refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
          if (feed.posts.isEmpty && !feed.loading && feed.error == null)
            TomiCard(
              child: Column(
                children: [
                  const Icon(
                    Icons.forum_outlined,
                    size: 38,
                    color: TomiColors.accent,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    feed.scope == 'following'
                        ? 'تابع أشخاص حتى تشوف منشوراتهم هنا.'
                        : 'بعد ماكو منشورات… شارك أول لحظة 💜',
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.7),
                  ),
                ],
              ),
            ),
          for (final p in feed.posts)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: RealPostCard(
                key: ValueKey(p.id),
                accounts: widget.accounts,
                post: p,
                busy: feed.busyPosts.contains(p.id),
                onLike: () => mutate(() => feed.like(p)),
                onDelete: () => mutate(() => feed.delete(p)),
                onUpdated: feed.replace,
              ),
            ),
          if (feed.nextCursor != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: OutlinedButton(
                onPressed: feed.loading ? null : feed.loadMore,
                child: const Text('عرض المزيد'),
              ),
            ),
        ],
      ),
    ),
  );
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
  });
  final AccountController accounts;
  final SocialPost post;
  final bool busy;
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

  @override
  Widget build(BuildContext c) => TomiCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => openAuthor(c, accounts, post.author),
              child: AccountAvatar(post.author.avatarUser, size: 44),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => openAuthor(c, accounts, post.author),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.author.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '@' + post.author.username,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TomiColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      relativeTime(post.createdAt),
                      style: const TextStyle(
                        color: TomiColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (post.isMine)
              IconButton(
                key: Key('delete-post-' + post.id),
                tooltip: 'حذف المنشور',
                onPressed: busy ? null : () => confirmDelete(c),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
          ],
        ),
        if (post.text.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(post.text, style: const TextStyle(height: 1.7, fontSize: 15)),
        ],
        if (post.image != null) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: (post.image!.width / post.image!.height)
                  .clamp(.7, 1.8)
                  .toDouble(),
              child: post.image!.url == null
                  ? const Center(
                      child: Icon(Icons.image_not_supported_outlined),
                    )
                  : InkWell(
                      onTap: () => showDialog<void>(
                        context: c,
                        builder: (d) => Dialog(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Align(
                                alignment: Alignment.topLeft,
                                child: IconButton(
                                  tooltip: 'إغلاق',
                                  onPressed: () => Navigator.pop(d),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ),
                              Flexible(
                                child: InteractiveViewer(
                                  child: Image.network(
                                    post.image!.url!,
                                    errorBuilder: (_, _, _) => const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('تعذّر تحميل الصورة'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      child: Image.network(
                        post.image!.url!,
                        fit: BoxFit.cover,
                        cacheWidth: 1200,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  color: TomiColors.muted,
                                ),
                              ),
                        errorBuilder: (_, _, _) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'تعذّر تحميل الصورة؛ حدّث المنشورات.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              key: Key('like-' + post.id),
              onPressed: busy ? null : onLike,
              icon: Icon(
                post.liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: post.liked ? TomiColors.pink : TomiColors.muted,
              ),
              label: Text(post.likesCount.toString()),
            ),
            TextButton.icon(
              key: Key('comments-' + post.id),
              onPressed: () => showModalBottomSheet<void>(
                context: c,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => RealCommentsSheet(
                  accounts: accounts,
                  post: post,
                  onUpdated: onUpdated,
                ),
              ),
              icon: const Icon(
                Icons.mode_comment_outlined,
                color: TomiColors.muted,
              ),
              label: Text(post.commentsCount.toString()),
            ),
          ],
        ),
      ],
    ),
  );
}

class SocialComposer extends StatefulWidget {
  const SocialComposer({
    super.key,
    required this.accounts,
    required this.imageEnabled,
    this.initialImage,
  });
  final AccountController accounts;
  final bool imageEnabled;
  final XFile? initialImage;
  @override
  State<SocialComposer> createState() => _SocialComposerState();
}

class _SocialComposerState extends State<SocialComposer> {
  final text = TextEditingController();
  String requestId = newRequestId();
  String? error, stage;
  ImageDraft? image;
  ImageUpload? upload;
  bool busy = false, imageSent = false, picking = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) unawaited(loadImage(widget.initialImage!));
  }

  Future<void> loadImage(XFile f) async {
    try {
      final p = await readPickedImage(f);
      if (mounted)
        setState(() {
          image = p;
          upload = null;
          imageSent = false;
          requestId = newRequestId();
          error = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر فتح الصورة؛ جرّب صورة ثانية.');
    }
  }

  Future<void> pick() async {
    if (busy || picking) return;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      await GalleryIntent.remember(
        widget.accounts.api.baseUrl,
        widget.accounts.user!.id,
      );
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      await GalleryIntent.clear();
      if (f != null) await loadImage(f);
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر فتح المعرض؛ تأكد من الصلاحيات.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> publish() async {
    if (busy || picking) return;
    if (text.text.trim().isEmpty && image == null) {
      setState(() => error = 'اكتب نص أو اختَر صورة.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      stage = image != null ? 'جارٍ رفع الصورة…' : 'جارٍ نشر المنشور…';
    });
    try {
      if (image != null && !imageSent) {
        upload ??= await widget.accounts.prepareImage(image!);
        await widget.accounts.uploadImage(upload!, image!);
        imageSent = true;
      }
      if (mounted) setState(() => stage = 'جارٍ التحقق والنشر…');
      final p = await widget.accounts.publishPost(
        text.text,
        requestId,
        uploadId: upload?.id,
      );
      if (mounted) Navigator.pop(context, p);
    } on AccountFailure catch (f) {
      if (f.code == 'IMAGE_UPLOAD' || f.code == 'UPLOAD_INVALID') {
        upload = null;
        imageSent = false;
      }
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'تعذّر النشر؛ منشورك محفوظ هنا، جرّب مرة ثانية.',
        );
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          stage = null;
        });
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy && !picking,
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
                    tooltip: 'إلغاء',
                    onPressed: busy || picking ? null : () => Navigator.pop(c),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('post-input'),
                controller: text,
                enabled: !busy && !picking,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                onChanged: (_) => requestId = newRequestId(),
                decoration: const InputDecoration(
                  hintText: 'شنو تحب تشارك اليوم؟',
                ),
              ),
              const SizedBox(height: 10),
              if (image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.memory(
                    image!.bytes,
                    height: 180,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Text('تعذّر عرض معاينة الصورة'),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy || picking
                      ? null
                      : () => setState(() {
                          image = null;
                          upload = null;
                          imageSent = false;
                          requestId = newRequestId();
                        }),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('إزالة الصورة'),
                ),
              ],
              OutlinedButton.icon(
                key: const Key('pick-post-image'),
                onPressed: busy || picking || !widget.imageEnabled
                    ? null
                    : pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(picking ? 'جارٍ فتح المعرض…' : 'إضافة صورة'),
              ),
              if (!widget.imageEnabled)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'نشر الصور غير متاح حاليًا؛ تگدر تنشر نص.',
                    style: TextStyle(color: TomiColors.muted, height: 1.6),
                  ),
                ),
              if (error != null) AccountErrorMessage(error!),
              if (busy) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(stage ?? '', textAlign: TextAlign.center),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('publish-post'),
                onPressed: busy || picking ? null : publish,
                icon: const Icon(Icons.send_rounded),
                label: Text(busy ? 'جارٍ النشر…' : 'نشر'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
      );
      if (mounted)
        setState(() {
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
    try {
      final r = await widget.accounts.addComment(
        widget.post.id,
        text.text,
        requestId,
      );
      if (mounted) {
        setState(
          () => comments = [
            r.comment,
            ...comments.where((v) => v.id != r.comment.id),
          ],
        );
        text.clear();
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

  Future<void> remove(SocialComment v) async {
    if (!deleting.add(v.id)) return;
    setState(() {});
    try {
      final p = await widget.accounts.deleteComment(v.id);
      if (mounted) {
        setState(() => comments.removeWhere((c) => c.id == v.id));
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

  @override
  void dispose() {
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
              height: constraints.maxHeight.clamp(320.0, double.infinity),
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
                  if (loading || sending)
                    const LinearProgressIndicator(minHeight: 2),
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
                        for (final v in comments)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AccountAvatar(v.author.avatarUser, size: 34),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        v.author.displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        v.text,
                                        style: const TextStyle(height: 1.6),
                                      ),
                                      Text(
                                        relativeTime(v.createdAt),
                                        style: const TextStyle(
                                          color: TomiColors.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (v.isMine || widget.post.isMine)
                                  IconButton(
                                    tooltip: 'حذف التعليق',
                                    onPressed: deleting.contains(v.id)
                                        ? null
                                        : () => remove(v),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 19,
                                    ),
                                  ),
                              ],
                            ),
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
