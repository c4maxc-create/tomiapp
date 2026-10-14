import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../social/social_screens.dart';
import '../social/social_models.dart';
import '../messaging/gallery_intent.dart';
import 'account_api.dart';
import 'account_controller.dart';
import 'account_widgets.dart';

class AvatarEditorPage extends StatefulWidget {
  const AvatarEditorPage({
    super.key,
    required this.accounts,
    this.initialImage,
  });
  final AccountController accounts;
  final XFile? initialImage;
  @override
  State<AvatarEditorPage> createState() => _AvatarEditorPageState();
}

class _AvatarEditorPageState extends State<AvatarEditorPage> {
  ImageDraft? image;
  ImageUpload? upload;
  DateTime? preparedAt;
  String requestId = newRequestId();
  String? error, removalRequestId;
  bool busy = false, picking = false, uploaded = false;
  late final owner = widget.accounts.user?.id;
  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) load(widget.initialImage!);
  }

  Future<void> load(XFile f) async {
    try {
      final d = await readPickedImage(f);
      if (mounted)
        setState(() {
          image = d;
          upload = null;
          preparedAt = null;
          uploaded = false;
          requestId = newRequestId();
          error = null;
        });
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> pick() async {
    if (busy || picking) return;
    setState(() => picking = true);
    try {
      await GalleryIntent.remember(
        widget.accounts.api.baseUrl,
        owner!,
        purpose: 'avatar',
      );
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      await GalleryIntent.clear();
      if (f != null && mounted) await load(f);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر فتح المعرض.');
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> save({bool remove = false}) async {
    if (busy ||
        picking ||
        owner != widget.accounts.user?.id ||
        (!remove && image == null))
      return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (remove) {
        removalRequestId ??= newRequestId();
        await widget.accounts.saveAvatar(null, removalRequestId!);
      } else {
        if (!uploaded) {
          if (upload != null &&
              DateTime.now().difference(preparedAt!).inMinutes >= 14)
            upload = null;
          if (upload == null) {
            final d = await widget.accounts.chatRequest(
              'POST',
              '/v1/me/avatar/uploads',
              body: {
                'contentType': image!.contentType,
                'byteLength': image!.bytes.length,
                'contentMd5': image!.contentMd5,
              },
            );
            if (owner != widget.accounts.user?.id) return;
            upload = ImageUpload.fromJson(d);
            preparedAt = DateTime.now();
          }
          await widget.accounts.uploadImage(upload!, image!);
          if (owner != widget.accounts.user?.id) return;
          uploaded = true;
        }
        await widget.accounts.saveAvatar(upload!.id, requestId);
      }
      if (mounted) Navigator.pop(context);
    } on AccountFailure catch (f) {
      if (f.code == 'UPLOAD_INVALID') {
        upload = null;
        uploaded = false;
      }
      if (mounted) setState(() => error = f.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر حفظ الصورة؛ جرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.accounts.user;
    if (user == null || user.id != owner) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(title: const Text('الصورة الشخصية')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Center(
            child: image == null
                ? AccountAvatar(user, size: 150)
                : ClipOval(
                    child: Image.memory(
                      image!.bytes,
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          const Text(
            'صورتك تظهر في ملفك والمنشورات والمحادثات.',
            textAlign: TextAlign.center,
          ),
          if (error != null) AccountErrorMessage(error!),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const Key('avatar-pick'),
            onPressed: busy || picking ? null : pick,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('اختيار صورة من المعرض'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('avatar-save'),
            onPressed: busy || picking || image == null ? null : () => save(),
            icon: const Icon(Icons.check),
            label: Text(busy ? 'جارٍ حفظ الصورة…' : 'حفظ الصورة'),
          ),
          if (user.avatarId != null)
            TextButton.icon(
              key: const Key('avatar-remove'),
              onPressed: busy || picking ? null : () => save(remove: true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('إزالة الصورة الشخصية'),
            ),
        ],
      ),
    );
  }
}
