import '../messaging/video_media.dart' show readPickedVideo;
import '../preferences/network_media_image.dart';
import '../messaging/chat_models.dart' show PendingChatMessage;
import '../messaging/upload_transfer.dart';
import '../identity/identity_avatar.dart';
import '../identity/identity_models.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../messaging/audio_focus.dart';
import '../messaging/gallery_intent.dart';
import '../messaging/chat_screens.dart';
import '../widgets.dart';
import 'home_controller.dart';
import 'social_models.dart';
import 'social_media.dart';
import 'social_screens.dart' show openAuthor, readPickedImage, relativeTime;

const socialBackground = TomiColors.background;
const socialSurface = TomiColors.surface;

class StoryAvatar extends StatelessWidget {
  const StoryAvatar({
    super.key,
    required this.user,
    this.size = 64,
    this.hasStory = false,
    this.unseen = true,
    this.add = false,
    this.onTap,
    this.onAdd,
  });
  final AccountUser user;
  final double size;
  final bool hasStory, unseen, add;
  final VoidCallback? onTap, onAdd;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'صورة ${user.displayName}${hasStory ? '، لديه ستوري' : ''}',
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: EdgeInsets.all(hasStory ? 3 : 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasStory && unseen
                      ? const SweepGradient(
                          colors: [
                            Color(0xFF77DECF),
                            Color(0xFF63BBF1),
                            Color(0xFFB197FF),
                            Color(0xFFF6CD76),
                            Color(0xFF77DECF),
                          ],
                          transform: GradientRotation(.8),
                        )
                      : null,
                  border: hasStory && !unseen
                      ? Border.all(color: const Color(0xFF697078), width: 2)
                      : null,
                ),
                child: Container(
                  padding: EdgeInsets.all(hasStory ? 3 : 2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: socialBackground,
                  ),
                  child: IdentityDecoration(
                    identity: UserIdentity({
                      ...user.identity.data,
                      'frameId': 'none',
                    }),
                    size: (size - (hasStory ? 12 : 0))
                        .clamp(12.0, size)
                        .toDouble(),
                    name: user.displayName,
                    child: ClipOval(
                      child: user.avatarUrl != null
                          ? NetworkMediaImage(
                              user.avatarUrl!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => placeholder(),
                            )
                          : placeholder(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (add)
            Positioned(
              right: 0,
              bottom: 0,
              child: Semantics(
                label: 'إضافة ستوري',
                button: true,
                child: GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: socialBackground, width: 2),
                    ),
                    child: const Icon(Icons.add, color: Colors.black, size: 17),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  Widget placeholder() {
    final symbol = avatarSymbols[user.avatarPreset] ?? '';
    return Container(
      color: const Color(0xFF353B43),
      alignment: Alignment.center,
      child: symbol.isNotEmpty
          ? Text(
              symbol,
              textScaler: TextScaler.noScaling,
              style: TextStyle(fontSize: size * .43),
            )
          : Icon(Icons.person, color: const Color(0xFFC6CBD0), size: size * .7),
    );
  }
}

Future<void> openProfilePicture(BuildContext context, AccountUser user) async {
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (c) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(user.username, textDirection: TextDirection.ltr),
        ),
        body: Center(
          child: user.avatarUrl == null
              ? StoryAvatar(user: user, size: 180)
              : InteractiveViewer(
                  child: NetworkMediaImage(
                    user.avatarUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text('تعذّر تحميل الصورة'),
                  ),
                ),
        ),
      ),
    ),
  );
}

Future<void> openStoryAvatar(
  BuildContext context,
  AccountController accounts,
  AccountUser user,
) async {
  try {
    final fresh = await accounts.home.authorStories(user.id);
    if (!context.mounted) return;
    if (fresh.isEmpty) {
      await openProfilePicture(context, user);
      return;
    }
    final groups = accounts.home.groups
        .where((g) => g.stories.any((s) => s.active))
        .toList();
    final index = groups.indexWhere((g) => g.author.id == user.id);
    if (index < 0) {
      groups.add(fresh.first);
    } else {
      groups[index] = fresh.first;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StoryViewerPage(
          accounts: accounts,
          groups: groups,
          initialGroup: index < 0 ? groups.length - 1 : index,
        ),
      ),
    );
    await accounts.home.loadStories();
  } on AccountFailure catch (e) {
    if (context.mounted) showNote(context, e.message);
  } catch (_) {
    if (context.mounted)
      showNote(context, 'تعذّر تحميل الستوري؛ جرّب مرة ثانية.');
  }
}

Future<void> composeStory(
  BuildContext context,
  AccountController accounts, {
  XFile? initialImage,
  XFile? initialVideo,
}) async {
  if (initialImage == null && initialVideo == null) {
    try {
      await GalleryIntent.remember(
        accounts.api.baseUrl,
        accounts.user!.id,
        purpose: 'story-media',
      );
      final file = await ImagePicker().pickMedia();
      await GalleryIntent.clear();
      if (!context.mounted) return;
      if (file != null) {
        final video =
            (file.mimeType?.startsWith('video/') ?? false) ||
            [
              '.mp4',
              '.mov',
              '.m4v',
              '.webm',
            ].any(file.name.toLowerCase().endsWith);
        if (video) {
          initialVideo = file;
        } else {
          initialImage = file;
        }
      } else {
        return;
      }
    } catch (_) {
      if (context.mounted) showNote(context, 'تعذّر فتح الاستوديو.');
      return;
    }
  }
  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute<bool>(
      builder: (_) => StoryComposerPage(
        accounts: accounts,
        initialImage: initialImage,
        initialVideo: initialVideo,
      ),
    ),
  );
  if (result == true) {
    await accounts.home.loadStories();
    if (context.mounted) showNote(context, 'تم نشر الستوري لمدة24ساعة');
  }
}

class StoriesStrip extends StatelessWidget {
  const StoriesStrip({super.key, required this.accounts});
  final AccountController accounts;
  static const labelStyle = TextStyle(fontSize: 11, color: Colors.white);

  double stripHeight(BuildContext context, Iterable<String> labels) {
    var style = DefaultTextStyle.of(context).style.merge(labelStyle);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    double labelHeight = 0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 84);
      labelHeight = math.max(labelHeight, painter.height);
      painter.dispose();
    }
    // TOMI moment cards: inset20 + art66 + gap8 + list16, plus text.
    return math.max(142.0, 116 + labelHeight.ceilToDouble());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: accounts.home,
    builder: (c, _) {
      final me = accounts.user;
      if (me == null) return const SizedBox.shrink();
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: TomiColors.accent,
                  size: 17,
                ),
                SizedBox(width: 7),
                Text(
                  'لحظات تومي',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: TomiColors.muted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            key: const Key('story-strip'),
            height: stripHeight(c, [
              'قصتك',
              for (final g in accounts.home.groups)
                if (g.author.id != me.id && g.stories.any((s) => s.active))
                  g.author.username,
            ]),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                children: [
                  item(c, me, 'قصتك', own: true),
                  for (final g in accounts.home.groups)
                    if (g.author.id != me.id && g.stories.any((s) => s.active))
                      item(c, g.author.avatarUser, g.author.username),
                ],
              ),
            ),
          ),
          if (accounts.home.storyError != null)
            TextButton(
              onPressed: accounts.home.loadStories,
              child: const Text('تعذّر تحميل الستوريات • إعادة المحاولة'),
            ),
          const Divider(height: 1, color: TomiColors.border),
        ],
      );
    },
  );
  Widget item(
    BuildContext c,
    AccountUser u,
    String label, {
    bool own = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: SizedBox(
      width: 104,
      child: Material(
        color: TomiColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TomiRadius.card),
          side: BorderSide(
            color: accounts.home.hasStory(u.id) && accounts.home.unseen(u.id)
                ? TomiColors.accent
                : TomiColors.border,
            width: 1.4,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(TomiRadius.card),
          onTap: () => own && !accounts.home.hasStory(u.id)
              ? composeStory(c, accounts)
              : openStoryAvatar(c, accounts, u),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 66,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: -.10,
                        child: Container(
                          width: 54,
                          height: 59,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                TomiColors.accent.withValues(alpha: .18),
                                TomiColors.raised,
                              ],
                            ),
                            border: Border.all(color: TomiColors.border),
                          ),
                        ),
                      ),
                      AccountAvatar(u, size: 43),
                      Positioned(
                        right: 1,
                        bottom: 0,
                        child: Material(
                          color: TomiColors.raised,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: own
                                ? () => composeStory(c, accounts)
                                : () => openStoryAvatar(c, accounts, u),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                own
                                    ? Icons.add_rounded
                                    : Icons.play_arrow_rounded,
                                size: 15,
                                color: TomiColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  key: ValueKey('story-label-${u.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.accounts,
    required this.groups,
    this.initialGroup = 0,
  });
  final AccountController accounts;
  final List<StoryGroup> groups;
  final int initialGroup;
  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  late int current = widget.initialGroup;
  late final pages = PageController(initialPage: current);
  late final accountId = widget.accounts.user?.id;
  bool closing = false;
  void next(int delta) {
    if (closing) return;
    final n = current + delta;
    if (n < 0) return;
    if (n >= widget.groups.length) {
      closing = true;
      Navigator.pop(context);
      return;
    }
    pages.animateToPage(
      n,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.accounts.addListener(accountChanged);
  }

  void accountChanged() {
    if (widget.accounts.user?.id != accountId && mounted)
      Navigator.pop(context);
  }

  @override
  void dispose() {
    widget.accounts.removeListener(accountChanged);
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 350) Navigator.pop(context);
          },
          child: PageView.builder(
            controller: pages,
            onPageChanged: (i) => setState(() => current = i),
            itemCount: widget.groups.length,
            itemBuilder: (c, i) => AnimatedBuilder(
              animation: pages,
              builder: (c, child) {
                final offset =
                    pages.hasClients && pages.position.hasContentDimensions
                    ? (pages.page ?? current.toDouble()) - i
                    : current - i.toDouble();
                final angle = offset.clamp(-1.0, 1.0) * math.pi / 2;
                return Transform(
                  alignment: offset > 0
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0015)
                    ..rotateY(angle),
                  child: child,
                );
              },
              child: StorySequence(
                key: ValueKey(widget.groups[i].author.id),
                accounts: widget.accounts,
                group: widget.groups[i],
                active: i == current,
                onGroup: next,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class StorySequence extends StatefulWidget {
  const StorySequence({
    super.key,
    required this.accounts,
    required this.group,
    required this.active,
    required this.onGroup,
  });
  final AccountController accounts;
  final StoryGroup group;
  final bool active;
  final ValueChanged<int> onGroup;
  @override
  State<StorySequence> createState() => _StorySequenceState();
}

class _StorySequenceState extends State<StorySequence>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  late int index = initialIndex();
  int generation = 0;
  bool paused = false,
      foreground = true,
      ready = false,
      viewMarked = false,
      failed = false;
  String? error;
  VideoPlayerController? player;
  bool replying = false;
  StoryItem get item => widget.group.stories[index];
  int initialIndex() {
    final n = widget.group.stories.indexWhere((s) => !s.seen && s.active);
    return n < 0 ? 0 : n;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    voiceMediaStops[this] = pauseForOtherAudio;
    progress.addListener(changed);
    progress.addStatusListener((s) {
      if (s == AnimationStatus.completed && item.video == null) step(1);
    });
    unawaited(load());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> pauseForOtherAudio() async {
    paused = true;
    progress.stop();
    await player?.pause();
    changed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!current) {
        progress.stop();
        unawaited(player?.pause());
      } else {
        resume();
      }
    });
  }

  @override
  void didUpdateWidget(covariant StorySequence old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) {
        if (!ready && !failed && player == null)
          unawaited(load());
        else
          resume();
      } else {
        progress.stop();
        unawaited(player?.pause());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      progress.stop();
      unawaited(player?.pause());
    } else
      resume();
  }

  Future<void> load() async {
    final gen = ++generation;
    progress.stop();
    progress.value = 0;
    ready = false;
    viewMarked = false;
    failed = false;
    error = null;
    final old = player;
    player = null;
    old?.removeListener(videoChanged);
    await old?.dispose();
    if (!mounted || gen != generation) return;
    if (!item.active) {
      failed = true;
      error = 'انتهت هذه الستوري';
      changed();
      return;
    }
    if (item.video == null) {
      if (item.image == null) {
        ready = true;
        resume();
      }
      changed();
      return;
    }
    if (!widget.active) return;
    VideoPlayerController? candidate;
    try {
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/stories/${item.id}',
      );
      if (!mounted || gen != generation) return;
      final fresh = StoryItem(d['story'] as Map<String, dynamic>);
      final url = await fresh.video?.playbackUrl();
      if (url == null) throw StateError('missing video');
      candidate = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await candidate.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || gen != generation) {
        await candidate.dispose();
        return;
      }
      player = candidate;
      candidate = null;
      await player!.setVolume(widget.accounts.liveAudioBusy ? 0 : 1);
      player!.addListener(videoChanged);
      ready = true;
      await stopVoiceForCall(except: this);
      if (mounted && gen == generation) resume();
    } catch (_) {
      await candidate?.dispose();
      if (mounted && gen == generation) {
        failed = true;
        error = 'تعذّر تشغيل الستوري';
      }
    }
    if (mounted && gen == generation) changed();
  }

  void videoChanged() {
    final p = player;
    if (p == null || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      if (p.value.isPlaying) unawaited(p.pause());
      return;
    }
    if (p.value.hasError) {
      setState(() {
        failed = true;
        error = 'تعذّر تشغيل الفيديو؛ أعد المحاولة';
      });
      return;
    }
    if (p.value.duration.inMilliseconds > 0) {
      progress.value =
          (p.value.position.inMilliseconds / p.value.duration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();
      if (p.value.position >= p.value.duration &&
          widget.active &&
          !paused &&
          foreground) {
        step(1);
        return;
      }
    }
    changed();
  }

  void mark() {
    if (viewMarked || !ready || !widget.active || !foreground || failed) return;
    viewMarked = true;
    unawaited(widget.accounts.home.markViewed(item).catchError((Object _) {}));
  }

  void resume() {
    if (!mounted ||
        !widget.active ||
        paused ||
        !foreground ||
        !ready ||
        failed ||
        ModalRoute.of(context)?.isCurrent == false)
      return;
    mark();
    if (player != null) {
      unawaited(player!.play().catchError((Object _) {}));
    } else {
      progress.forward();
    }
    changed();
  }

  void hold(bool value) {
    paused = value;
    if (value) {
      progress.stop();
      unawaited(player?.pause());
    } else
      resume();
    changed();
  }

  void step(int delta) {
    if (!mounted || !widget.active) return;
    progress.stop();
    final n = index + delta;
    if (n < 0 || n >= widget.group.stories.length) {
      widget.onGroup(delta);
      return;
    }
    setState(() => index = n);
    unawaited(load());
  }

  Future<void> actions() async {
    hold(true);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('حذف الستوري'),
              onTap: () async {
                Navigator.pop(c);
                try {
                  await widget.accounts.chatRequest(
                    'DELETE',
                    '/v1/stories/${item.id}',
                  );
                  await widget.accounts.home.loadStories();
                  if (mounted) Navigator.pop(context);
                } on AccountFailure catch (e) {
                  if (mounted) showNote(context, e.message);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (mounted) hold(false);
  }

  Future<void> viewers() async {
    hold(true);
    try {
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/stories/${item.id}/viewers',
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('المشاهدات (${item.viewsCount})'),
              ),
              for (final raw in d['users'] as List)
                ListTile(
                  title: Text(raw['displayName'] as String),
                  subtitle: Text('@${raw['username']}'),
                ),
              if ((d['users'] as List).isEmpty)
                const ListTile(title: Text('بعد ماكو مشاهدات')),
            ],
          ),
        ),
      );
    } on AccountFailure catch (e) {
      if (mounted) showNote(context, e.message);
    } finally {
      if (mounted) hold(false);
    }
  }

  Future<void> quickReply(String emoji) async {
    if (replying || item.isMine) return;
    final story = item,
        accounts = widget.accounts,
        session = widget.accounts.sessionRevision;
    setState(() => replying = true);
    hold(true);
    try {
      final conversation = await accounts.chats.open(story.author.id),
          thread = accounts.chats.thread(conversation);
      await thread.restored;
      if (!mounted || accounts.sessionRevision != session) return;
      thread.enqueue(
        '$emoji رد على ستوري ${story.author.displayName}${story.text.isEmpty ? '' : '\n${story.text}'}',
        null,
      );
      if (!await thread.persist()) throw StateError('save');
      if (mounted) showNote(context, 'التفاعل قيد الإرسال بالمحادثة.');
    } on AccountFailure catch (f) {
      if (mounted) showNote(context, f.message);
    } catch (_) {
      if (mounted) showNote(context, 'تعذّر حفظ التفاعل؛ أعد المحاولة.');
    } finally {
      if (mounted) {
        setState(() => replying = false);
        hold(false);
      }
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    voiceMediaStops.remove(this);
    progress.dispose();
    player?.removeListener(videoChanged);
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Container(
        color: const Color(0xFF14171B),
        child: Center(
          child: failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error ?? 'تعذّر العرض'),
                    TextButton(
                      onPressed: () => unawaited(load()),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                )
              : item.video != null
              ? player?.value.isInitialized == true
                    ? AspectRatio(
                        aspectRatio: player!.value.aspectRatio,
                        child: VideoPlayer(player!),
                      )
                    : const CircularProgressIndicator()
              : item.image?.url != null
              ? NetworkMediaImage(
                  item.image!.url!,
                  fit: BoxFit.contain,
                  frameBuilder: (c, child, frame, sync) {
                    if ((frame != null || sync) && !ready)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !ready) {
                          ready = true;
                          resume();
                        }
                      });
                    return child;
                  },
                  errorBuilder: (c, _, _) {
                    if (!failed)
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted)
                          setState(() {
                            failed = true;
                            error = 'تعذّر تحميل الصورة';
                          });
                      });
                    return const Icon(Icons.broken_image_outlined, size: 48);
                  },
                )
              : Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF4D195C),
                        Color(0xFFAD3B6C),
                        Color(0xFF304D76),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    item.text,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      height: 1.5,
                    ),
                  ),
                ),
        ),
      ),
      if (!failed)
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) {
            if (d.localPosition.dx < MediaQuery.sizeOf(context).width * .28) {
              step(-1);
            } else {
              step(1);
            }
          },
          onLongPressStart: (_) => hold(true),
          onLongPressEnd: (_) => hold(false),
        ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
          child: Column(
            children: [
              Row(
                children: [
                  for (var i = 0; i < widget.group.stories.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          value: i < index
                              ? 1
                              : i == index
                              ? progress.value
                              : 0,
                          backgroundColor: Colors.white38,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  StoryAvatar(
                    user: item.author.avatarUser,
                    size: 34,
                    onTap: () async {
                      hold(true);
                      await openAuthor(context, widget.accounts, item.author);
                      if (mounted) hold(false);
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        hold(true);
                        await openAuthor(context, widget.accounts, item.author);
                        if (mounted) hold(false);
                      },
                      child: Text(
                        '${item.author.username}  ·  ${relativeTime(item.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  if (item.isMine)
                    IconButton(
                      onPressed: actions,
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                    ),
                  IconButton(
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (item.text.isNotEmpty && (item.image != null || item.video != null))
        Positioned(
          left: 20,
          right: 20,
          bottom: item.isMine ? 90 : 150,
          child: IgnorePointer(
            child: Text(
              item.text,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                shadows: [Shadow(color: Colors.black, blurRadius: 7)],
              ),
            ),
          ),
        ),
      Positioned(
        bottom: 16,
        left: 16,
        right: 16,
        child: item.isMine
            ? TextButton.icon(
                onPressed: viewers,
                icon: const Icon(
                  Icons.visibility_outlined,
                  color: Colors.white,
                ),
                label: const Text(
                  'المشاهدات',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    children: [
                      for (final emoji in const ['❤️', '😂', '🔥'])
                        IconButton(
                          tooltip: 'رد $emoji',
                          onPressed: replying ? null : () => quickReply(emoji),
                          icon: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.all(14),
                    ),
                    onPressed: () async {
                      hold(true);
                      await openPrivateChat(
                        context,
                        widget.accounts,
                        item.author.id,
                      );
                      if (mounted) hold(false);
                    },
                    icon: const Icon(Icons.send_outlined, size: 20),
                    label: const Text('مراسلة صاحب الستوري'),
                  ),
                ],
              ),
      ),
    ],
  );
}

class StoryComposerPage extends StatefulWidget {
  const StoryComposerPage({
    super.key,
    required this.accounts,
    this.initialImage,
    this.initialVideo,
  });
  final AccountController accounts;
  final XFile? initialImage, initialVideo;
  @override
  State<StoryComposerPage> createState() => _StoryComposerPageState();
}

class _StoryComposerPageState extends State<StoryComposerPage>
    with WidgetsBindingObserver {
  final text = TextEditingController();
  ImageDraft? media;
  ImageUpload? upload;
  String requestId = newRequestId();
  bool busy = false, picking = false;
  String? error, videoPath;
  String audience = 'public';
  late final accountId = widget.accounts.user?.id;
  late final owner = widget.accounts.draftOwnerId;
  late final session = widget.accounts.sessionRevision;
  bool restoring = true,
      committed = false,
      uploaded = false,
      closed = false,
      storageReady = true;
  UploadTransfer? transfer;
  bool get current =>
      !closed &&
      widget.accounts.user?.id == accountId &&
      widget.accounts.sessionRevision == session;
  bool get locked => committed || restoring;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(restoreDraft());
  }

  Future<void> saveDraft() async {
    if (!current || restoring || !storageReady || owner == null) return;
    final item =
        PendingChatMessage(
            text.text,
            media is VideoDraft ? null : media,
            video: media is VideoDraft ? media as VideoDraft : null,
            requestId: requestId,
          )
          ..upload = upload
          ..uploaded = uploaded
          ..commitAttempted = committed;
    await widget.accounts.draftStore.write(
      owner!,
      'story',
      {...item.toJson(), 'audience': audience},
      blobs: {if (media != null) media!.contentSha256: media!.bytes},
      valid: () => current,
    );
  }

  Future<void> saveSafely() async {
    try {
      await saveDraft();
    } catch (_) {
      if (mounted)
        setState(
          () =>
              error = 'تعذّر حفظ مسودة الستوري على الجهاز؛ أبقِ الصفحة مفتوحة.',
        );
    }
  }

  Future<void> restoreDraft() async {
    try {
      final data = owner == null
          ? null
          : await widget.accounts.draftStore.read(owner!, 'story');
      if (!current || !mounted) return;
      if (data != null) {
        final item = PendingChatMessage.restore(data);
        text.text = item.text;
        requestId = item.requestId;
        upload = item.upload;
        committed = item.commitAttempted;
        uploaded = item.uploaded;
        audience = data['audience'] == 'followers' ? 'followers' : 'public';
        if (item.savedMedia != null) {
          final d = item.savedMedia!,
              bytes = await widget.accounts.draftStore.bytes(
                owner!,
                d['mediaKey'] as String,
              );
          if (!current || !mounted) return;
          media = d['kind'] == 'video'
              ? VideoDraft(
                  bytes,
                  durationMs: (d['durationMs'] as num).toInt(),
                  width: (d['width'] as num).toInt(),
                  height: (d['height'] as num).toInt(),
                  poster: d['poster'] as String?,
                )
              : ImageDraft(bytes, d['type'] as String);
        }
        if (committed)
          error = 'يوجد نشر غير مؤكد؛ أعد المحاولة بنفس المحتوى للتحقق منه.';
      }
      restoring = false;
      if (widget.initialImage != null && data == null)
        await load(widget.initialImage!, false);
      if (widget.initialVideo != null && data == null)
        await load(widget.initialVideo!, true);
    } catch (_) {
      storageReady = false;
      error = 'تعذّر قراءة مسودة الستوري؛ لم تُحذف أو تُستبدل.';
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(saveSafely());
  }

  Future<void> closeDraft() async {
    if (busy || picking || restoring) return;
    try {
      await saveDraft();
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'تعذّر حفظ المسودة؛ أبقِ الصفحة مفتوحة وأعد المحاولة.',
        );
      return;
    }
    if (mounted) {
      setState(() => closed = true);
      Navigator.pop(context);
    }
  }

  Future<void> load(XFile file, bool video) async {
    if (locked || !storageReady) return;
    setState(() => picking = true);
    try {
      final next = video
          ? await readPickedVideo(file, maxSeconds: 60)
          : await readPickedImage(file);
      if (next is VideoDraft && next.durationMs > 60000)
        throw const AccountFailure(
          'STORY_DURATION',
          'فيديو الستوري حتى60 ثانية.',
        );
      if (mounted)
        setState(() {
          media = next;
          videoPath = null;
          upload = null;
          uploaded = false;
          requestId = newRequestId();
          error = null;
        });
      await saveDraft();
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر قراءة الملف.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> pick(bool video) async {
    if (busy || picking) return;
    setState(() => picking = true);
    try {
      await GalleryIntent.remember(
        widget.accounts.api.baseUrl,
        accountId!,
        purpose: video ? 'story-video' : 'story',
      );
      final file = video
          ? await ImagePicker().pickVideo(source: ImageSource.gallery)
          : await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1920,
              maxHeight: 1920,
              imageQuality: 90,
              requestFullMetadata: false,
            );
      await GalleryIntent.clear();
      if (file != null && mounted) await load(file, video);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر فتح المعرض.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> discardDraft() async {
    if (busy || picking || restoring || !storageReady) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('مسح مسودة الستوري؟'),
        content: const Text(
          'يلغي إعادة المحاولة من جهازك فقط. إذا كانت الستوري قد نُشرت قبل انقطاع الرد، تبقى منشورة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('مسح المسودة'),
          ),
        ],
      ),
    );
    if (yes != true || !current) return;
    try {
      if (!await widget.accounts.draftStore.write(
        owner!,
        'story',
        null,
        valid: () => current,
      ))
        return;
      if (mounted)
        setState(() {
          text.clear();
          media = null;
          upload = null;
          videoPath = null;
          committed = false;
          uploaded = false;
          requestId = newRequestId();
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر مسح المسودة؛ أعد المحاولة.');
    }
  }

  Future<void> publish() async {
    if (busy || picking || restoring || !storageReady) return;
    if (text.text.trim().isEmpty && media == null) {
      setState(() => error = 'اختَر صورة أو فيديو أو اكتب نصًا.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.accounts.user?.id != accountId)
        throw const AccountFailure(
          'SESSION_CHANGED',
          'تغيّر الحساب؛ افتح الستوري من حسابك الحالي.',
        );
      if (committed) {
        try {
          await widget.accounts.chatRequest(
            'GET',
            '/v1/stories/requests/$requestId',
          );
          if (!current) return;
          await widget.accounts.draftStore.write(
            owner!,
            'story',
            null,
            valid: () => current,
          );
          closed = true;
          if (mounted) Navigator.pop(context, true);
          return;
        } on AccountFailure catch (e) {
          if (e.code != 'REQUEST_NOT_FOUND') rethrow;
        }
      }
      await saveDraft();
      if (media != null && upload == null) {
        final fresh = await widget.accounts.preparePostMedia(
          media!,
          newRequestId(),
        );
        upload = fresh;
        await saveDraft();
      }
      if (media != null && upload != null && !uploaded) {
        transfer = UploadTransfer()..addListener(uploadChanged);
        transfer!.active = true;
        UploadTransfer.owners[media!] = transfer;
        try {
          await widget.accounts.uploadImage(upload!, media!);
        } finally {
          UploadTransfer.owners[media!] = null;
          transfer!.active = false;
          transfer!.removeListener(uploadChanged);
        }
        if (transfer!.cancelled)
          throw const AccountFailure(
            'UPLOAD_CANCELLED',
            'توقف الرفع؛ المسودة محفوظة.',
          );
        uploaded = true;
        await saveDraft();
      }
      if (widget.accounts.user?.id != accountId)
        throw const AccountFailure(
          'SESSION_CHANGED',
          'تغيّر الحساب؛ افتح الستوري من الحساب الحالي.',
        );
      committed = true;
      await saveDraft();
      await widget.accounts.chatRequest(
        'POST',
        '/v1/stories',
        body: {
          'requestId': requestId,
          'audience': audience,
          'text': text.text.trim(),
          if (media != null && upload != null)
            (media is VideoDraft ? 'videoUploadId' : 'imageUploadId'):
                upload!.id,
          if (media != null) 'attachmentSha256': media!.contentSha256,
        },
      );
      if (current && owner != null)
        await widget.accounts.draftStore.write(
          owner!,
          'story',
          null,
          valid: () => current,
        );
      closed = true;
      if (mounted) Navigator.pop(context, true);
    } on AccountFailure catch (e) {
      if (e.code == 'UPLOAD_INVALID') {
        committed = false;
        uploaded = false;
        upload = null;
        requestId = newRequestId();
        await saveSafely();
      }
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر النشر؛ أعد المحاولة بنفس المحتوى.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void uploadChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    transfer?.cancel();
    closed = true;
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: closed,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(closeDraft());
    },
    child: Scaffold(
      backgroundColor: socialBackground,
      appBar: AppBar(
        backgroundColor: socialBackground,
        leading: IconButton(
          onPressed: busy || picking || restoring ? null : closeDraft,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('ستوري جديدة'),
        actions: [
          TextButton(
            onPressed: busy || picking || restoring || !storageReady
                ? null
                : publish,
            child: Text(busy ? 'جارٍ النشر…' : 'نشر'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          AspectRatio(
            aspectRatio: 9 / 12,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF4D195C),
                    Color(0xFFAD3B6C),
                    Color(0xFF304D76),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: media != null && media is! VideoDraft
                  ? Image.memory(media!.bytes, fit: BoxFit.contain)
                  : Center(
                      child: media is VideoDraft && videoPath != null
                          ? InlineSocialVideo(
                              key: ValueKey(videoPath),
                              video: PostVideo({
                                'width': (media! as VideoDraft).width,
                                'height': (media! as VideoDraft).height,
                                'durationMs': (media! as VideoDraft).durationMs,
                              }),
                              source: () async => Uri.file(videoPath!),
                              preview: true,
                            )
                          : media is VideoDraft &&
                                (media! as VideoDraft).posterBytes != null
                          ? Image.memory(
                              (media! as VideoDraft).posterBytes!,
                              fit: BoxFit.contain,
                            )
                          : media is VideoDraft
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_outlined, size: 54),
                                Text('فيديو جاهز للنشر'),
                              ],
                            )
                          : ValueListenableBuilder(
                              valueListenable: text,
                              builder: (c, v, _) => Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  v.text.isEmpty ? 'لحظتك هنا' : v.text,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: audience,
            decoration: const InputDecoration(labelText: 'جمهور الستوري'),
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
            onChanged: busy || locked
                ? null
                : (v) => setState(() {
                    audience = v!;
                    requestId = newRequestId();
                    unawaited(saveSafely());
                  }),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('story-text'),
            controller: text,
            enabled: !busy && !picking && !locked && storageReady,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) {
              requestId = newRequestId();
              unawaited(saveSafely());
            },
            decoration: const InputDecoration(hintText: 'اكتب شيئًا عن لحظتك…'),
          ),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: busy || picking || locked ? null : () => pick(false),
                icon: const Icon(Icons.image_outlined),
                label: const Text('صورة'),
              ),
              OutlinedButton.icon(
                onPressed: busy || picking || locked ? null : () => pick(true),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('فيديو حتى60ث'),
              ),
              if (media != null)
                TextButton(
                  onPressed: busy || picking || locked
                      ? null
                      : () => setState(() {
                          media = null;
                          upload = null;
                          requestId = newRequestId();
                          unawaited(saveSafely());
                        }),
                  child: const Text('إزالة الملف'),
                ),
            ],
          ),
          const Text(
            'تظهر لمدة24ساعة. صور حتى10MB وفيديوMP4 حتى60ث و25MB.',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          if (restoring || transfer?.active == true)
            LinearProgressIndicator(
              value: transfer?.active == true ? transfer?.progress : null,
            ),
          if (transfer?.active == true)
            TextButton(
              onPressed: transfer?.cancel,
              child: Text(
                'إيقاف الرفع • ${((transfer?.progress ?? 0) * 100).round()}%',
              ),
            ),
          const Text('مسودة الستوري محفوظة على هذا الجهاز.'),
          TextButton(
            onPressed: busy || picking || restoring || !storageReady
                ? null
                : discardDraft,
            child: const Text('مسح المسودة'),
          ),
          if (error != null) AccountErrorMessage(error!),
          if (busy || picking) const LinearProgressIndicator(),
        ],
      ),
    ),
  );
}
