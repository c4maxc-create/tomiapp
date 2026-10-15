import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../accounts/account_models.dart';
import '../accounts/account_api.dart';
import '../social/social_screens.dart' show readPickedImage;
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import 'room_controller.dart';
import 'room_models.dart';
part 'room_stage.dart';
part 'room_panels.dart';

class VoiceRoomsScreen extends StatefulWidget {
  const VoiceRoomsScreen({
    super.key,
    required this.accounts,
    this.visible = true,
  });
  final AccountController accounts;
  final bool visible;
  @override
  State<VoiceRoomsScreen> createState() => _VoiceRoomsScreenState();
}

class _VoiceRoomsScreenState extends State<VoiceRoomsScreen> {
  VoiceRoomsController get controller => widget.accounts.voiceRooms;
  @override
  void initState() {
    super.initState();
    if (widget.visible) loadOnOpen();
  }

  @override
  void didUpdateWidget(covariant VoiceRoomsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) loadOnOpen();
  }

  void loadOnOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.visible) unawaited(controller.load());
    });
  }

  Future<void> open(String id) async {
    final rooms = controller.rooms.where((r) => r.id == id);
    final room = rooms.isEmpty ? null : rooms.first;
    String? password;
    if (room?.passwordRequired == true &&
        room?.ownerId != widget.accounts.user?.id) {
      password = await _roomText(context, 'كلمة مرور الغرفة', '', secret: true);
      if (password == null || !mounted) return;
    }
    if (await controller.join(id, password: password) && mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceRoomPage(controller: controller),
        ),
      );
      if (mounted) unawaited(controller.load());
    }
  }

  Future<void> create() async {
    final input = await showModalBottomSheet<_NewRoom>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateRoomSheet(),
    );
    if (input == null || !mounted) return;
    final id = await controller.create(
      input.title,
      input.capacity,
      input.seats,
    );
    if (id != null && mounted) await open(id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        key: const PageStorageKey('voice-room-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'سوالف تجمعنا',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'ادخل كمستمع، أو اطلب المايك وشارك السالفة.',
            style: TextStyle(color: TomiColors.muted, height: 1.6),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('create-voice-room'),
            onPressed:
                controller.configured && !controller.busy && !controller.loading
                ? create
                : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إنشاء غرفة صوتية'),
          ),
          if (controller.loading) const LinearProgressIndicator(),
          if (controller.error != null) AccountErrorMessage(controller.error!),
          if (controller.notice != null)
            AccountErrorMessage(controller.notice!),
          if (!controller.configured &&
              !controller.loading &&
              controller.error == null)
            const AccountErrorMessage(
              'الغرف الصوتية تنتظر تفعيل الخدمة. باقي ميزات التطبيق متاحة.',
            ),
          if (controller.ownedRoomId != null &&
              !controller.rooms.any((r) => r.id == controller.ownedRoomId))
            TextButton(
              onPressed: controller.busy
                  ? null
                  : () => open(controller.ownedRoomId!),
              child: const Text('فتح غرفتي'),
            ),
          const SizedBox(height: 14),
          if (controller.rooms.isEmpty &&
              controller.configured &&
              !controller.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Column(
                children: [
                  Icon(
                    Icons.spatial_audio_off_rounded,
                    size: 52,
                    color: TomiColors.accent,
                  ),
                  SizedBox(height: 14),
                  Text('بعد ماكو غرف. افتح أول غرفة لأصدقائك!'),
                ],
              ),
            ),
          for (final r in controller.rooms)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TomiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.graphic_eq_rounded,
                          color: TomiColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            r.title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (r.ownerId == widget.accounts.user?.id)
                          const TinyLabel('غرفتك'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${r.memberCount} / ${r.capacity} عضو  •  LV.${r.level}  •  ${r.category}${r.passwordRequired ? '  🔒' : ''}',
                      style: const TextStyle(color: TomiColors.muted),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        key: Key('join-room-${r.id}'),
                        onPressed: controller.busy || !controller.configured
                            ? null
                            : () => open(r.id),
                        icon: const Icon(Icons.headphones_rounded),
                        label: Text(
                          controller.joining ? 'جارٍ الاتصال…' : 'دخول الغرفة',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (controller.nextBefore != null)
            TextButton(
              onPressed: controller.loading
                  ? null
                  : () => controller.load(more: true),
              child: const Text('غرف أكثر'),
            ),
          OutlinedButton.icon(
            onPressed: controller.loading ? null : controller.load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تحديث الغرف'),
          ),
        ],
      ),
    ),
  );
}

class _NewRoom {
  const _NewRoom(this.title, this.capacity, this.seats);
  final String title;
  final int capacity, seats;
}

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet();
  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final name = TextEditingController(), form = GlobalKey<FormState>();
  int capacity = 20, seats = 8;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'غرفة جديدة',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('voice-room-title'),
                controller: name,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'اسم الغرفة',
                  hintText: 'مثال: سوالف الأصدقاء',
                ),
                validator: (v) => ((v ?? '').trim().runes.length < 2)
                    ? 'اكتب اسمًا من حرفين على الأقل.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: capacity,
                decoration: const InputDecoration(labelText: 'عدد الأعضاء'),
                items: [10, 20, 30]
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text('$v عضو')),
                    )
                    .toList(),
                onChanged: (v) => setState(() => capacity = v!),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: seats,
                decoration: const InputDecoration(labelText: 'مقاعد المايك'),
                items: [4, 6, 8]
                    .map(
                      (v) =>
                          DropdownMenuItem(value: v, child: Text('$v مقاعد')),
                    )
                    .toList(),
                onChanged: (v) => setState(() => seats = v!),
              ),
              const SizedBox(height: 16),
              const Text(
                'المايك يبدأ مغلقًا. الغرفة تنغلق بعد 10 دقائق من خروج آخر عضو.',
                style: TextStyle(color: TomiColors.muted, height: 1.6),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  if (form.currentState!.validate())
                    Navigator.pop(
                      context,
                      _NewRoom(name.text.trim(), capacity, seats),
                    );
                },
                child: const Text('إنشاء ودخول'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
