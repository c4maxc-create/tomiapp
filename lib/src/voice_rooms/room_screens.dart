import 'dart:async';
import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import 'room_controller.dart';
import 'room_models.dart';

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
    if (await controller.join(id) && mounted) {
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
                      '${r.memberCount} / ${r.capacity} عضو  •  ${r.seatCount} مقاعد مايك',
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

class VoiceRoomPage extends StatefulWidget {
  const VoiceRoomPage({super.key, required this.controller});
  final VoiceRoomsController controller;
  @override
  State<VoiceRoomPage> createState() => _VoiceRoomPageState();
}

class _VoiceRoomPageState extends State<VoiceRoomPage> {
  VoiceRoomsController get c => widget.controller;
  bool leaving = false;
  Future<void> leave() async {
    if (leaving) return;
    setState(() => leaving = true);
    await c.leave();
    if (mounted) Navigator.pop(context);
  }

  Future<void> closeRoom() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إغلاق الغرفة؟'),
        content: const Text('راح يغادر كل الأعضاء وتنغلق الغرفة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    if (yes == true) await c.action('close');
  }

  Future<void> manage(VoiceMember member) async {
    final me = c.me;
    if (me == null ||
        member.user.id == me.user.id ||
        member.role == 'owner' ||
        me.role == 'moderator' && member.role != 'member')
      return;
    final operation = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  member.user.displayName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (member.requestedAt != null) ...[
                ListTile(
                  leading: const Icon(Icons.mic_rounded),
                  title: const Text('قبول طلب المايك'),
                  onTap: () => Navigator.pop(context, 'approve'),
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('رفض الطلب'),
                  onTap: () => Navigator.pop(context, 'reject'),
                ),
              ],
              if (member.seat != null) ...[
                ListTile(
                  leading: Icon(
                    member.micAllowed
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                  ),
                  title: Text(
                    member.micAllowed
                        ? 'كتم المايك بالإدارة'
                        : 'السماح بفتح المايك',
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    member.micAllowed ? 'mute' : 'allow-mic',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.south_rounded),
                  title: const Text('إنزال إلى المستمعين'),
                  onTap: () => Navigator.pop(context, 'lower'),
                ),
              ],
              if (me.role == 'owner')
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(
                    member.role == 'moderator' ? 'إلغاء الإشراف' : 'تعيين مشرف',
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    member.role == 'moderator' ? 'demote' : 'promote',
                  ),
                ),
              ListTile(
                leading: const Icon(
                  Icons.person_remove_rounded,
                  color: TomiColors.pink,
                ),
                title: const Text('إزالة من الغرفة'),
                subtitle: const Text('لن يقدر يرجع لهذه الغرفة.'),
                onTap: () => Navigator.pop(context, 'kick'),
              ),
            ],
          ),
        ),
      ),
    );
    if (operation != null) await c.moderate(member, operation);
  }

  Widget seat(VoiceRoom room, int index) {
    final member = room.seated(index),
        speaking =
            member != null &&
            c.audio?.speakers.contains(member.identity) == true;
    return Semantics(
      label:
          'مقعد ${index + 1}${member == null ? ' فارغ' : ': ${member.user.displayName}'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: member != null && c.manage && !c.busy
            ? () => manage(member)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: TomiColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: speaking ? TomiColors.accent : TomiColors.raised,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (member == null)
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: TomiColors.raised,
                  child: Icon(Icons.mic_none_rounded, color: TomiColors.muted),
                )
              else
                MediaQuery.withNoTextScaling(
                  child: AccountAvatar(member.user, size: 56),
                ),
              const SizedBox(height: 8),
              Text(
                member?.user.displayName ?? 'مقعد ${index + 1}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              if (member != null)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Icon(
                      c.audio?.openMics.contains(member.identity) == true
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      size: 15,
                      color: member.micAllowed
                          ? TomiColors.accent
                          : TomiColors.pink,
                    ),
                    Text(
                      member.role == 'owner'
                          ? 'المالك'
                          : member.role == 'moderator'
                          ? 'مشرف'
                          : 'متحدث',
                      style: const TextStyle(
                        fontSize: 11,
                        color: TomiColors.muted,
                      ),
                    ),
                  ],
                )
              else
                const Text(
                  'متاح',
                  style: TextStyle(fontSize: 11, color: TomiColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final r = c.active;
      return PopScope(
        canPop: r == null || leaving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(leave());
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              r?.title ?? 'انتهت الغرفة',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (c.me?.role == 'owner')
                IconButton(
                  tooltip: 'إغلاق الغرفة',
                  onPressed: c.busy ? null : closeRoom,
                  icon: const Icon(Icons.power_settings_new_rounded),
                ),
            ],
          ),
          body: SafeArea(
            child: r == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.headset_off_rounded,
                            size: 52,
                            color: TomiColors.muted,
                          ),
                          const SizedBox(height: 16),
                          Text(c.notice ?? 'غادرت الغرفة.'),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('الرجوع للغرف'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(18),
                          children: [
                            Row(
                              children: [
                                Icon(
                                  c.reconnecting
                                      ? Icons.sync_rounded
                                      : Icons.graphic_eq_rounded,
                                  color: TomiColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    c.reconnecting
                                        ? 'جارٍ استعادة الاتصال…'
                                        : '${r.memberCount} / ${r.capacity} عضو • غرفة صوتية',
                                    style: const TextStyle(
                                      color: TomiColors.muted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (r.pending)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  'جارٍ تطبيق صلاحيات الصوت…',
                                  style: TextStyle(color: TomiColors.gold),
                                ),
                              ),
                            if (c.error != null) AccountErrorMessage(c.error!),
                            const SizedBox(height: 20),
                            LayoutBuilder(
                              builder: (context, box) {
                                final columns = box.maxWidth >= 500
                                    ? 4
                                    : (MediaQuery.textScalerOf(
                                                context,
                                              ).scale(14) >=
                                              21
                                          ? 2
                                          : 3);
                                final width =
                                    (box.maxWidth - (columns - 1) * 10) /
                                    columns;
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (var i = 0; i < r.seatCount; i++)
                                      SizedBox(width: width, child: seat(r, i)),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            if (c.manage &&
                                r.members.any(
                                  (m) => m.requestedAt != null,
                                )) ...[
                              const Text(
                                'طلبات المايك',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final m in r.members.where(
                                (m) => m.requestedAt != null,
                              ))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: AccountAvatar(m.user, size: 42),
                                  title: Text(m.user.displayName),
                                  trailing: IconButton(
                                    tooltip: 'إدارة الطلب',
                                    onPressed: c.busy ? null : () => manage(m),
                                    icon: const Icon(Icons.more_horiz_rounded),
                                  ),
                                ),
                            ],
                            const Text(
                              'المستمعون',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (r.members.every((m) => m.seat != null))
                              const Text(
                                'ماكو مستمعين بعد.',
                                style: TextStyle(color: TomiColors.muted),
                              ),
                            for (final m in r.members.where(
                              (m) => m.seat == null,
                            ))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: AccountAvatar(m.user, size: 42),
                                title: Text(
                                  '${m.user.displayName}${m.user.id == c.accounts.user?.id ? ' (أنت)' : ''}',
                                ),
                                subtitle: Text(
                                  m.requestedAt != null
                                      ? 'طلب المايك'
                                      : m.role == 'owner'
                                      ? 'المالك'
                                      : m.role == 'moderator'
                                      ? 'مشرف'
                                      : 'مستمع',
                                ),
                                trailing:
                                    c.manage && m.user.id != c.accounts.user?.id
                                    ? IconButton(
                                        tooltip: 'إدارة العضو',
                                        onPressed: c.busy
                                            ? null
                                            : () => manage(m),
                                        icon: const Icon(
                                          Icons.more_horiz_rounded,
                                        ),
                                      )
                                    : null,
                              ),
                            const SizedBox(height: 16),
                            const Text(
                              'الغرفة تعمل والتطبيق مفتوح؛ الرجوع أو مغادرة التطبيق ينهي مشاركتك.',
                              style: TextStyle(
                                fontSize: 12,
                                color: TomiColors.muted,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                        color: TomiColors.surface,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (c.me?.seat == null)
                              FilledButton.tonalIcon(
                                key: const Key('room-request-mic'),
                                onPressed: c.busy
                                    ? null
                                    : () => c.action(
                                        c.me?.requestedAt == null
                                            ? (c.manage
                                                  ? 'take-seat'
                                                  : 'request-mic')
                                            : 'cancel-request',
                                      ),
                                icon: const Icon(Icons.front_hand_rounded),
                                label: Text(
                                  c.me?.requestedAt == null
                                      ? (c.manage
                                            ? 'صعود للمايك'
                                            : 'طلب المايك')
                                      : 'إلغاء الطلب',
                                ),
                              )
                            else
                              FilledButton.tonalIcon(
                                key: const Key('room-microphone'),
                                onPressed:
                                    c.micBusy ||
                                        (!c.canUseMic && !c.microphoneOn)
                                    ? null
                                    : c.toggleMicrophone,
                                icon: Icon(
                                  c.microphoneOn
                                      ? Icons.mic_rounded
                                      : Icons.mic_off_rounded,
                                ),
                                label: Text(
                                  c.microphoneOn ? 'كتم' : 'فتح المايك',
                                ),
                              ),
                            IconButton.filledTonal(
                              tooltip: c.speakerOn
                                  ? 'السماعة الخارجية'
                                  : 'سماعة الهاتف',
                              onPressed: c.toggleSpeaker,
                              icon: Icon(
                                c.speakerOn
                                    ? Icons.volume_up_rounded
                                    : Icons.hearing_rounded,
                              ),
                            ),
                            if (c.me?.seat != null)
                              IconButton.filledTonal(
                                tooltip: 'ترك مقعد المايك',
                                onPressed: c.busy
                                    ? null
                                    : () => c.action('leave-seat'),
                                icon: const Icon(Icons.south_rounded),
                              ),
                            FilledButton.icon(
                              key: const Key('leave-voice-room'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFB83254),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: leaving ? null : leave,
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('مغادرة'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
