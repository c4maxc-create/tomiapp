import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'media_preferences.dart';

/// Enforce the same download policy for avatars, room pictures and shared images.
class NetworkMediaImage extends StatefulWidget {
  const NetworkMediaImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.cacheWidth,
    this.errorBuilder,
    this.loadingBuilder,
    this.frameBuilder,
  });
  final String url;
  final double? width, height;
  final BoxFit? fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageFrameBuilder? frameBuilder;
  @override
  State<NetworkMediaImage> createState() => _NetworkMediaImageState();
}

class _NetworkMediaImageState extends State<NetworkMediaImage> {
  final preferences = MediaPreferences.instance;
  StreamSubscription<List<ConnectivityResult>>? network;
  bool? allowed;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    preferences.addListener(changed);
    unawaited(check());
  }

  void changed() => unawaited(check());
  Future<void> check() async {
    final e = ++epoch;
    await preferences.restore();
    if (!mounted || e != epoch) return;
    if (preferences.wifiOnly)
      network ??= Connectivity().onConnectivityChanged.listen(
        (_) => changed(),
        onError: (Object _) {
          if (mounted) setState(() => allowed = false);
        },
      );
    else {
      unawaited(network?.cancel());
      network = null;
    }
    bool result;
    try {
      result = await preferences.allowNetworkMedia();
    } catch (_) {
      result = false;
    }
    if (mounted && e == epoch && result != allowed)
      setState(() => allowed = result);
  }

  @override
  void dispose() {
    epoch++;
    preferences.removeListener(changed);
    unawaited(network?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (allowed == true)
      return Image.network(
        widget.url,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        errorBuilder: widget.errorBuilder,
        loadingBuilder: widget.loadingBuilder,
        frameBuilder: widget.frameBuilder,
      );
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Tooltip(
        message: allowed == false
            ? 'الصور متوقفة: فعّلت التنزيل عبر Wi-Fi فقط. اتصل بالواي فاي أو غيّر الإعداد.'
            : 'تحميل إعدادات الوسائط',
        child: Center(
          child: Icon(
            allowed == false ? Icons.wifi_off : Icons.image_outlined,
            size: 20,
          ),
        ),
      ),
    );
  }
}
