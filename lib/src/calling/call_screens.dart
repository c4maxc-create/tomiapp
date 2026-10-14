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
              child: Image.network(
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

  Widget control(
    String label,
    IconData icon,
    VoidCallback action, {
    bool enabled = true,
  }) => FilledButton.tonalIcon(
    onPressed: enabled ? action : null,
    icon: Icon(icon),
    label: Text(label),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.calls,
    builder: (context, _) {
      final c = call, m = widget.calls, engine = m.media;
      return PopScope(
        canPop: c.ended,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(leave());
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(c.video ? 'مكالمة فيديو' : 'مكالمة صوتية'),
            leading: IconButton(
              onPressed: leave,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 14),
                Center(child: CallAvatar(c.peer, size: 76)),
                const SizedBox(height: 14),
                Text(
                  c.peer.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.ended
                      ? c.statusText
                      : m.reconnecting
                      ? 'الاتصال ضعيف؛ نحاول استعادته…'
                      : m.localConnected
                      ? 'المكالمة جارية'
                      : c.statusText,
                  key: const Key('call-status'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TomiColors.muted, fontSize: 17),
                ),
                if (c.connectedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      c.durationText(),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 25),
                    ),
                  ),
                if (m.busy)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: LinearProgressIndicator(),
                  ),
                if (m.error != null) AccountErrorMessage(m.error!),
                const SizedBox(height: 22),
                if (c.video && engine != null && !c.ended && m.mediaReady)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Colors.black,
                            child: engine.view(local: false),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            width: 96,
                            height: 128,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: ColoredBox(
                                color: TomiColors.raised,
                                child: m.cameraOn
                                    ? engine.view(local: true)
                                    : const Icon(Icons.videocam_off),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (c.incoming && c.canControl)
                  Column(
                    children: [
                      Text(
                        c.video
                            ? 'الرد يشغّل المايك والكاميرا بعد موافقتك.'
                            : 'الرد يشغّل المايك بعد موافقتك.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: TomiColors.muted),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            key: const Key('call-accept'),
                            onPressed: m.busy ? null : m.accept,
                            icon: const Icon(Icons.call),
                            label: const Text('قبول'),
                          ),
                          FilledButton.icon(
                            key: const Key('call-decline'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                            ),
                            onPressed: m.decline,
                            icon: const Icon(Icons.call_end),
                            label: const Text('رفض'),
                          ),
                        ],
                      ),
                    ],
                  ),
                if (!c.incoming && !c.ended)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        control(
                          m.muted ? 'تشغيل المايك' : 'كتم المايك',
                          m.muted ? Icons.mic_off : Icons.mic,
                          () => unawaited(m.toggleMute()),
                          enabled: engine != null && !m.busy,
                        ),
                        control(
                          m.speakerOn ? 'سماعة الهاتف' : 'مكبر الصوت',
                          m.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
                          () => unawaited(m.toggleSpeaker()),
                          enabled: engine != null && !m.busy,
                        ),
                        if (c.video)
                          control(
                            m.cameraOn ? 'إيقاف الفيديو' : 'تشغيل الفيديو',
                            m.cameraOn ? Icons.videocam : Icons.videocam_off,
                            () => unawaited(m.toggleCamera()),
                            enabled: engine != null && !m.busy,
                          ),
                        if (c.video)
                          control(
                            'تبديل الكاميرا',
                            Icons.cameraswitch,
                            () => unawaited(m.switchCamera()),
                            enabled: engine != null && !m.busy && m.cameraOn,
                          ),
                        FilledButton.icon(
                          key: const Key('call-end'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                          ),
                          onPressed: () => unawaited(m.hangup()),
                          icon: const Icon(Icons.call_end),
                          label: const Text('إنهاء'),
                        ),
                      ],
                    ),
                  ),
                if (c.ended)
                  FilledButton.icon(
                    key: const Key('call-close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('إغلاق'),
                  ),
                const SizedBox(height: 24),
                if (!c.ended)
                  const Text(
                    'خلي التطبيق مفتوح أثناء المكالمة. المغادرة تنهي الاتصال في هذه النسخة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: TomiColors.muted, fontSize: 12),
                  ),
              ],
            ),
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
