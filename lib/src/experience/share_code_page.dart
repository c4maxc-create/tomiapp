import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../accounts/account_controller.dart';
import '../voice_rooms/room_models.dart';
import '../voice_rooms/room_screens.dart';
import '../widgets.dart';

class TomiLink {
  const TomiLink(this.kind, this.target);
  final String kind, target;
  static TomiLink? parse(String value) {
    final match = RegExp(
      r'^tomi://(profile|room)/([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})$',
    ).firstMatch(value);
    if (match != null && match.end == value.length)
      return TomiLink(match[1]!, match[2]!.toLowerCase());
    final game = RegExp(r'^tomi://game/([a-fA-F0-9]{8})$').firstMatch(value);
    return game == null || game.end != value.length
        ? null
        : TomiLink('game', game[1]!.toUpperCase());
  }
}

class ShareCodePage extends StatefulWidget {
  const ShareCodePage({super.key, required this.url, required this.title});
  final String url, title;
  @override
  State<ShareCodePage> createState() => _ShareCodePageState();
}

class _ShareCodePageState extends State<ShareCodePage> {
  late final Future<Uint8List?> qr = generate();
  String? error;
  Future<Uint8List?> generate() async {
    if (!(Platform.isAndroid || Platform.isIOS) ||
        Platform.environment.containsKey('FLUTTER_TEST'))
      return null;
    try {
      return await const MethodChannel(
        'tomi/mobile',
      ).invokeMethod<Uint8List>('qrCode', {'url': widget.url});
    } catch (_) {
      return null;
    }
  }

  Future<void> share() async {
    try {
      await const MethodChannel(
        'tomi/mobile',
      ).invokeMethod<void>('shareQr', {'url': widget.url});
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّرت مشاركة الصورة؛ تگدر تنسخ الرابط.');
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'يفتح الرابط المكان المحدد عند تثبيت TOMI. الانضمام يبقى خاضعاً لصلاحيات الغرفة أو اللعبة.',
        ),
        const SizedBox(height: 20),
        FutureBuilder<Uint8List?>(
          future: qr,
          builder: (c, s) => s.data == null
              ? const Icon(Icons.qr_code_2, size: 140)
              : Image.memory(
                  s.data!,
                  width: 280,
                  height: 280,
                  fit: BoxFit.contain,
                ),
        ),
        const SizedBox(height: 20),
        SelectableText(
          widget.url,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: share,
          icon: const Icon(Icons.share_outlined),
          label: const Text('مشاركة QR والرابط'),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.url));
            if (c.mounted) showNote(c, 'تم نسخ الرابط.');
          },
          icon: const Icon(Icons.copy),
          label: const Text('نسخ الرابط'),
        ),
        if (error != null) Text(error!),
      ],
    ),
  );
}

Future<void> openLinkedRoom(
  BuildContext context,
  AccountController accounts,
  String id,
) async {
  final rooms = accounts.voiceRooms;
  if (rooms.active?.id == id) {
    rooms.expand();
  } else {
    final d = await accounts.chatRequest('GET', '/v1/rooms/$id'),
        room = VoiceRoom((d['room'] as Map).cast<String, dynamic>());
    String? password;
    if (room.passwordRequired && room.ownerId != accounts.user?.id) {
      if (!context.mounted) return;
      var value = '';
      password = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('كلمة مرور الغرفة'),
          content: TextField(obscureText: true, onChanged: (v) => value = v),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, value),
              child: const Text('دخول'),
            ),
          ],
        ),
      );
      if (password == null) return;
    }
    if (!await rooms.join(id, password: password))
      throw StateError(rooms.error ?? 'room unavailable');
  }
  if (context.mounted)
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => VoiceRoomPage(controller: rooms)),
    );
}
