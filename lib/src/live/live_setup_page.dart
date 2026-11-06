import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../accounts/account_controller.dart';

class LiveSetup {
  const LiveSetup({required this.microphone, required this.front});
  final bool microphone, front;
}

class LiveSetupPage extends StatefulWidget {
  const LiveSetupPage({super.key, required this.accounts, required this.title});
  final AccountController accounts;
  final String title;
  @override
  State<LiveSetupPage> createState() => _LiveSetupPageState();
}

class _LiveSetupPageState extends State<LiveSetupPage>
    with WidgetsBindingObserver {
  lk.LocalVideoTrack? camera;
  lk.LocalAudioTrack? microphone;
  bool busy = false, front = true, mic = true, closed = false;
  String? error;
  final lease = Object();
  Future<void>? work, release;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.accounts.liveMediaLease = lease;
    work = prepare();
  }

  Future<void> prepare() async {
    busy = true;
    try {
      final video = await lk.LocalVideoTrack.createCameraTrack(
        const lk.CameraCaptureOptions(
          params: lk.VideoParameters(
            dimensions: lk.VideoDimensions(1280, 720),
            encoding: lk.VideoEncoding(maxBitrate: 2500000, maxFramerate: 30),
          ),
        ),
      );
      camera = video;
      if (closed) {
        await video.dispose();
        return;
      }
      microphone = await lk.LocalAudioTrack.create(
        const lk.AudioCaptureOptions(stopAudioCaptureOnMute: true),
      );
      if (closed) {
        await microphone?.dispose();
        return;
      }
    } catch (_) {
      error =
          'ما نكدر نجهّز الكاميرا أو المايك. اسمح لهم من إعدادات الهاتف ثم جرّب مرة ثانية.';
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> closeTracks() => release ??= () async {
    closed = true;
    try {
      await work;
    } catch (_) {}
    await camera?.dispose();
    await microphone?.dispose();
    if (identical(widget.accounts.liveMediaLease, lease))
      widget.accounts.liveMediaLease = null;
  }();
  Future<void> finish(bool start) async {
    final result = LiveSetup(microphone: mic, front: front);
    await closeTracks();
    if (mounted) Navigator.pop(context, start ? result : null);
  }

  Future<void> flip() async {
    if (camera == null || busy) return;
    try {
      front = !front;
      await camera!.setCameraPosition(
        front ? lk.CameraPosition.front : lk.CameraPosition.back,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تبديل الكاميرا.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(finish(false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(closeTracks());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: closed,
    onPopInvokedWithResult: (p, _) {
      if (!p) unawaited(finish(false));
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('تجهيز البث'),
        leading: IconButton(
          onPressed: () => finish(false),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: camera != null
                    ? lk.VideoTrackRenderer(camera!, fit: lk.VideoViewFit.cover)
                    : Center(
                        child: busy
                            ? const CircularProgressIndicator()
                            : const Icon(
                                Icons.videocam_off,
                                size: 60,
                                color: Colors.white70,
                              ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'هذه معاينة خاصة على جهازك. البث يبدأ فقط عند ضغط الزر.',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      IconButton(
                        onPressed: busy ? null : flip,
                        tooltip: 'تبديل الكاميرا',
                        icon: const Icon(
                          Icons.cameraswitch,
                          color: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () async {
                                final next = !mic;
                                try {
                                  if (next) {
                                    await microphone?.unmute();
                                  } else {
                                    await microphone?.mute();
                                  }
                                  if (mounted) setState(() => mic = next);
                                } catch (_) {
                                  if (mounted)
                                    setState(
                                      () => error = 'تعذّر تغيير حالة المايك.',
                                    );
                                }
                              },
                        icon: Icon(mic ? Icons.mic : Icons.mic_off),
                        label: Text(mic ? 'المايك مفتوح' : 'المايك مغلق'),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          busy || camera == null || (mic && microphone == null)
                          ? null
                          : () => finish(true),
                      icon: const Icon(Icons.sensors),
                      label: const Text('ابدأ البث الآن'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
