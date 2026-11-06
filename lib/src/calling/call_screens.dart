import '../preferences/network_media_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../accounts/account_api.dart';
import '../accounts/account_widgets.dart';
import '../social/social_models.dart';
import '../widgets.dart';
import 'call_controller.dart';
import 'call_models.dart';

class CallAvatar extends StatelessWidget {
  const CallAvatar(this.peer, {super.key, this.size = 64});
  final PostAuthor peer;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: TomiColors.raised,
      child: Text(
        peer.displayName.isEmpty ? 'T' : peer.displayName.characters.first,
        style: TextStyle(fontSize: size / 3, color: TomiColors.accent),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: peer.avatarUrl == null
          ? fallback
          : ClipOval(
              child: NetworkMediaImage(
                peer.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.calls, required this.initialCall});
  final CallController calls;
  final DirectCall initialCall;
  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  Timer? clock, ring;
  bool closing = false;
  DirectCall get call => widget.calls.active?.id == widget.initialCall.id
      ? widget.calls.active!
      : widget.initialCall.locallyEnded('ended');
  @override
  void initState() {
    super.initState();
    widget.calls.addListener(changed);
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    changed();
  }

  void changed() {
    if (call.incoming &&
        call.canControl &&
        !widget.calls.busy &&
        widget.calls.foreground) {
      if (ring == null) {
        sound();
        ring = Timer.periodic(const Duration(seconds: 3), (_) => sound());
      }
    } else {
      ring?.cancel();
      ring = null;
    }
  }

  void sound() {
    if (!widget.calls.foreground ||
        !call.incoming ||
        DateTime.now().isAfter(call.ringDeadline)) {
      ring?.cancel();
      ring = null;
      return;
    }
    unawaited(
      SystemSound.play(SystemSoundType.alert).catchError((Object _) {}),
    );
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
  }

  Future<void> leave() async {
    if (closing) return;
    if (call.ended) {
      Navigator.pop(context);
      return;
    }
    closing = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(call.incoming ? 'رفض المكالمة؟' : 'إنهاء المكالمة؟'),
        content: const Text('مغادرة شاشة الاتصال تنهي المكالمة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إنهاء'),
          ),
        ],
      ),
    );
    if (yes == true) {
      if (call.incoming)
        await widget.calls.decline();
      else
        await widget.calls.hangup();
      if (mounted) Navigator.pop(context);
    }
    closing = false;
  }

  @override
  void dispose() {
    widget.calls.removeListener(changed);
    clock?.cancel();
    ring?.cancel();
    super.dispose();
  }

  Offset? previewPosition;
  bool showLocalLarge = false;

  Widget roundControl({
    required String label,
    required IconData icon,
    required VoidCallback? action,
    Key? key,
    bool selected = false,
    Color? color,
    double size = 54,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: IconButton.filled(
              key: key,
              tooltip: label,
              onPressed: action,
              style: IconButton.styleFrom(
                backgroundColor:
                    color ??
                    (selected ? Colors.white : const Color(0xff34424a)),
                foregroundColor: selected && color == null
                    ? const Color(0xff0b141a)
                    : Colors.white,
                disabledBackgroundColor: const Color(0xff26343b),
                disabledForegroundColor: Colors.white38,
                padding: EdgeInsets.zero,
              ),
              icon: Icon(icon, size: 25),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
    ),
  );

  Widget mediaChangeCard(CallController m, DirectCall c) {
    final change = c.mediaChange;
    if (change == null || !change.ongoing) return const SizedBox.shrink();
    return Container(
      key: const Key('call-media-request'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff34424a),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            change.pending
                ? change.requestedByMe
                      ? 'ننتظر موافقة الطرف الثاني على الفيديو…'
                      : '${c.peer.displayName} يريد تحويل المكالمة إلى فيديو'
                : 'جاري التحويل إلى الفيديو…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (change.pending && !change.requestedByMe) ...[
            const SizedBox(height: 6),
            const Text(
              'الكاميرا تشتغل بعد موافقتك.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('call-video-decline'),
                    onPressed: m.busy
                        ? null
                        : () => unawaited(m.respondToVideo(false)),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('call-video-accept'),
                    onPressed: m.busy
                        ? null
                        : () => unawaited(m.respondToVideo(true)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff00a884),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.videocam),
                    label: const Text('قبول الفيديو'),
                  ),
                ),
              ],
            ),
          ] else
            TextButton(
              key: const Key('call-video-cancel'),
              onPressed: m.busy
                  ? null
                  : () => unawaited(m.cancelVideoRequest()),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('إلغاء الطلب'),
            ),
        ],
      ),
    );
  }

  Widget bottomPanel(CallController m, DirectCall c, double height) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      key: const Key('call-controls'),
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: height * .64),
      decoration: BoxDecoration(
        color: const Color(0xff17242b).withValues(alpha: .96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          14,
          height < 450 ? 9 : 15,
          14,
          height < 450 ? 8 : 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (m.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  m.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffffb4ab),
                    fontSize: 13,
                  ),
                ),
              ),
            if (m.mediaNotice != null && !c.ended)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  m.mediaNotice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            if (!c.ended) mediaChangeCard(m, c),
            if (c.incoming && c.canControl) ...[
              Text(
                c.video ? 'مكالمة فيديو واردة' : 'مكالمة صوتية واردة',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  roundControl(
                    key: const Key('call-decline'),
                    label: 'رفض',
                    icon: Icons.call_end,
                    color: const Color(0xffef4444),
                    action: () => unawaited(m.decline()),
                    size: 64,
                  ),
                  roundControl(
                    key: const Key('call-accept'),
                    label: 'قبول',
                    icon: c.video ? Icons.videocam : Icons.call,
                    color: const Color(0xff00a884),
                    action: m.busy ? null : () => unawaited(m.accept()),
                    size: 64,
                  ),
                ],
              ),
            ] else if (!c.ended)
              LayoutBuilder(
                builder: (context, box) {
                  final ready = m.media != null && m.mediaReady && !m.busy;
                  final changing =
                      c.mediaChange?.ongoing == true || m.modeSyncing;
                  final size = ((box.maxWidth - 36) / (c.video ? 5 : 4)).clamp(
                    38.0,
                    54.0,
                  );
                  return Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.video)
                          roundControl(
                            key: const Key('call-switch-camera'),
                            label: 'تبديل الكاميرا',
                            icon: Icons.cameraswitch_rounded,
                            action: ready && m.cameraOn && !changing
                                ? () => unawaited(m.switchCamera())
                                : null,
                            size: size,
                          ),
                        roundControl(
                          key: const Key('call-speaker'),
                          label: 'مكبر الصوت',
                          icon: m.speakerOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_down_rounded,
                          selected: m.speakerOn,
                          action: ready
                              ? () => unawaited(m.toggleSpeaker())
                              : null,
                          size: size,
                        ),
                        roundControl(
                          key: const Key('call-video-toggle'),
                          label: c.video
                              ? m.cameraOn
                                    ? 'إيقاف الكاميرا'
                                    : 'تشغيل الكاميرا'
                              : 'تحويل لفيديو',
                          icon: c.video && !m.cameraOn
                              ? Icons.videocam_off_rounded
                              : Icons.videocam_rounded,
                          selected: c.video && !m.cameraOn,
                          action:
                              ready &&
                                  !changing &&
                                  (c.video || c.state == 'connected')
                              ? () => unawaited(
                                  c.video
                                      ? m.toggleCamera()
                                      : m.changeKind(true),
                                )
                              : null,
                          size: size,
                        ),
                        roundControl(
                          key: const Key('call-mute'),
                          label: m.muted ? 'تشغيل المايك' : 'كتم المايك',
                          icon: m.muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          selected: m.muted,
                          action: ready
                              ? () => unawaited(m.toggleMute())
                              : null,
                          size: size,
                        ),
                        roundControl(
                          key: const Key('call-end'),
                          label: 'إنهاء',
                          icon: Icons.call_end_rounded,
                          color: const Color(0xffef4444),
                          action: () => unawaited(m.hangup()),
                          size: size,
                        ),
                      ],
                    ),
                  );
                },
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('call-close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('إغلاق'),
                ),
              ),
            if (c.video &&
                c.state == 'connected' &&
                c.mediaChange?.ongoing != true)
              TextButton(
                key: const Key('call-to-audio'),
                onPressed: m.busy ? null : () => unawaited(m.changeKind(false)),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('التحويل إلى مكالمة صوتية'),
              ),
            if (!c.ended && height >= 450) ...[
              const SizedBox(height: 12),
              Text(
                m.backgroundAudio
                    ? 'تگدر تقفل الشاشة؛ الصوت مستمر. الكاميرا تتوقف عند التصغير.'
                    : 'خلي التطبيق مفتوح أثناء المكالمة.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.calls,
    builder: (context, _) {
      final c = call, m = widget.calls, engine = m.media;
      final showVideo = c.video && engine != null && m.mediaReady && !c.ended;
      final status = c.ended
          ? c.statusText
          : m.reconnecting
          ? 'الاتصال ضعيف؛ نحاول استعادته…'
          : m.localConnected
          ? 'المكالمة جارية'
          : c.statusText;
      return PopScope(
        canPop: c.ended,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(leave());
        },
        child: Scaffold(
          backgroundColor: const Color(0xff0b141a),
          body: LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth, height = box.maxHeight;
              final safe = MediaQuery.paddingOf(context);
              final landscape = width > height;
              final pipWidth = (width * .28).clamp(82.0, 116.0);
              final minTop = safe.top + (landscape ? 64 : 104);
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final reserve = c.mediaChange?.ongoing == true
                  ? height * .64
                  : (landscape ? 145.0 : 200.0) +
                        (textScale - 1).clamp(0, 2) * 70;
              final maxPreviewHeight =
                  (height - safe.bottom - reserve - minTop - 12).clamp(
                    56.0,
                    200.0,
                  );
              final pipHeight = (pipWidth * (landscape ? .75 : 1.5)).clamp(
                56.0,
                maxPreviewHeight,
              );
              final maxTop = (height - safe.bottom - reserve - pipHeight - 12)
                  .clamp(minTop, height);
              final offset =
                  previewPosition ?? Offset(width - pipWidth - 16, minTop);
              final pipX = offset.dx.clamp(10.0, width - pipWidth - 10);
              final pipY = offset.dy.clamp(minTop, maxTop);
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (showVideo)
                    KeyedSubtree(
                      key: const Key('call-remote-video'),
                      child: engine.view(local: showLocalLarge && m.cameraOn),
                    )
                  else
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xff23343a), Color(0xff0b141a)],
                        ),
                      ),
                    ),
                  if (!showVideo || !m.remoteVideoReady && !showLocalLarge)
                    Align(
                      alignment: const Alignment(0, -.12),
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: height < 450 ? 40 : 100,
                        ),
                        child: CallAvatar(
                          c.peer,
                          size: (height * .20).clamp(72.0, 150.0),
                        ),
                      ),
                    ),
                  if (showVideo)
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x99000000),
                              Colors.transparent,
                              Color(0x55000000),
                            ],
                            stops: [0, .42, 1],
                          ),
                        ),
                      ),
                    ),
                  SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IconButton(
                                tooltip: 'رجوع',
                                onPressed: leave,
                                color: Colors.white,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 32,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      c.peer.displayName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 25,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      status,
                                      key: const Key('call-status'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (c.connectedAt != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Text(
                                          c.durationText(),
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(
                                width: 40,
                                child: Padding(
                                  padding: EdgeInsets.only(top: 13),
                                  child: Text(
                                    'TOMI',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  if (showVideo)
                    Positioned(
                      left: pipX,
                      top: pipY,
                      width: pipWidth,
                      height: pipHeight,
                      child: GestureDetector(
                        key: const Key('call-local-preview'),
                        onPanUpdate: (d) => setState(
                          () => previewPosition = Offset(
                            pipX + d.delta.dx,
                            pipY + d.delta.dy,
                          ),
                        ),
                        onTap: m.remoteVideoReady && m.cameraOn
                            ? () => setState(
                                () => showLocalLarge = !showLocalLarge,
                              )
                            : null,
                        child: Semantics(
                          label: 'معاينة الكاميرا، اسحب لتحريكها',
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xff26343b),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                            child: !m.cameraOn
                                ? const Icon(
                                    Icons.videocam_off_rounded,
                                    color: Colors.white70,
                                  )
                                : engine.view(local: !showLocalLarge),
                          ),
                        ),
                      ),
                    ),
                  SafeArea(child: bottomPanel(m, c, height)),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({super.key, required this.calls});
  final CallController calls;
  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  final items = <DirectCall>[];
  String? nextBefore, error;
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
      final d = await widget.calls.request(
        'GET',
        '/v1/calls',
        query: more && nextBefore != null ? {'before': nextBefore!} : null,
      );
      if (!mounted) return;
      setState(() {
        if (!more) items.clear();
        final seen = items.map((c) => c.id).toSet();
        items.addAll(
          (d['calls'] as List)
              .map((v) => DirectCall(v as Map<String, dynamic>))
              .where((c) => seen.add(c.id)),
        );
        nextBefore = d['nextBefore'] as String?;
      });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحميل سجل المكالمات.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سجل المكالمات')),
    body: RefreshIndicator(
      onRefresh: () => load(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (error != null) AccountErrorMessage(error!),
          if (!loading && items.isEmpty && error == null)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Text(
                'مكالماتك راح تظهر هنا.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final c in items)
            Card(
              child: ListTile(
                leading: CallAvatar(c.peer, size: 48),
                title: Text(
                  c.peer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${c.video ? 'فيديو' : 'صوت'} · ${c.statusText}\n${c.createdAt.toLocal().toString().substring(0, 16)}${c.connectedAt != null ? ' · ${c.durationText()}' : ''}',
                ),
                isThreeLine: true,
                trailing: Icon(
                  c.isCaller ? Icons.call_made : Icons.call_received,
                  color: c.reason == 'missed'
                      ? Colors.redAccent
                      : TomiColors.accent,
                ),
                onTap: () => widget.calls.open(c.id),
              ),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (nextBefore != null && !loading)
            TextButton(
              onPressed: () => load(more: true),
              child: const Text('مكالمات أقدم'),
            ),
        ],
      ),
    ),
  );
}
