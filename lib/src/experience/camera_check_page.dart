import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../accounts/account_controller.dart';

/// Local diagnostics only: no media intent, upload or gallery persistence.
class CameraCheckPage extends StatefulWidget {
  const CameraCheckPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<CameraCheckPage> createState() => _CameraCheckPageState();
}

class _CameraCheckPageState extends State<CameraCheckPage> {
  Uint8List? preview;
  bool busy = false, confirmed = false;
  String? error;
  late final revision = widget.accounts.sessionRevision;
  late final account = widget.accounts.user?.id;
  bool get current =>
      mounted &&
      widget.accounts.user?.id == account &&
      widget.accounts.sessionRevision == revision;
  Future<void> capture() async {
    if (!current || busy || widget.accounts.liveAudioBusy) return;
    setState(() {
      busy = true;
      error = null;
      confirmed = false;
    });
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (file == null || !current) return;
      if (await file.length() > 10 * 1024 * 1024)
        throw const FormatException('camera image too large');
      final bytes = await file.readAsBytes();
      if (current) setState(() => preview = bytes);
    } catch (_) {
      if (current)
        setState(
          () => error =
              'تعذّر فتح الكاميرا. تأكد من إذنها ومن عدم استخدامها بمكالمة أو تطبيق آخر.',
        );
    } finally {
      // Delete only the camera plugin's temporary capture inside this app's cache.
      // Never remove a gallery file or an arbitrary path outside that directory.
      if (file != null) {
        try {
          final root = await (await getTemporaryDirectory())
              .resolveSymbolicLinks();
          final captured = File(file.path),
              path = await captured.resolveSymbolicLinks();
          if (path.startsWith('$root${Platform.pathSeparator}'))
            await captured.delete();
        } catch (_) {}
      }
      if (current) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    preview = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('فحص الكاميرا محلياً')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'افتح الكاميرا والتقط صورة حتى تتأكد من الوضوح. صورة الفحص لا تُرفع إلى TOMI ولا تُنشر.',
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(error!),
          ),
        if (preview != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(
              preview!,
              height: 300,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('الصورة غير قابلة للعرض؛ أعد الفحص.'),
              ),
            ),
          ),
          CheckboxListTile(
            value: confirmed,
            onChanged: busy
                ? null
                : (v) => setState(() => confirmed = v == true),
            title: const Text('الصورة واضحة والكاميرا تعمل عندي'),
          ),
        ],
        FilledButton.icon(
          onPressed: busy || widget.accounts.liveAudioBusy ? null : capture,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(preview == null ? 'فتح الكاميرا' : 'إعادة الفحص'),
        ),
        if (confirmed)
          const ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('أكدتَ نجاح فحص الكاميرا على هذا الجهاز'),
          ),
        const SizedBox(height: 12),
        const Text(
          'هذا يفحص الكاميرا على جهازك. اتصال الفيديو يحتاج أيضاً إنترنت وخدمة مكالمات مهيّأة لدى الطرفين.',
        ),
      ],
    ),
  );
}
