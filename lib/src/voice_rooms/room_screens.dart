import 'room_tools_sheet.dart';
import '../preferences/network_media_image.dart';
import '../experience/send_invitation_page.dart';
import '../experience/share_code_page.dart';
import '../experience/community_pages.dart';
import '../design/tomi_theme.dart';
import '../roulette/live_sheet.dart';
import '../identity/charisma_badge.dart';
import '../identity/room_effects.dart';
import '../identity/identity_models.dart';
import '../identity/ranking_screen.dart';

import 'dart:async';

import '../moderation/report_dialog.dart';

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
part 'room_shop.dart';

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
  bool openingCreation = false;
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

  Future<void> discardSaved(String rid, String kind) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إلغاء إعادة المحاولة؟'),
        content: const Text(
          'إذا سبق أن نجح الإرسال، يبقى مسجلًا. هذا الزر يلغي المحاولة المحفوظة على الجهاز.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إلغاء المحاولة'),
          ),
        ],
      ),
    );
    if (yes == true && mounted)
      await controller.resolveSavedRoom(rid, kind, discard: true);
  }

  Future<void> create() async {
    if (openingCreation || controller.busy) return;
    if (controller.inRoom) {
      controller.error = 'غادر غرفتك الحالية قبل إنشاء غرفة أخرى.';
      controller.notify();
      return;
    }
    setState(() => openingCreation = true);
    try {
      final pending = controller.pendingCreation;
      if (pending != null) {
        final id = await controller.create(
          pending['title'] as String,
          pending['capacity'] as int,
          pending['seatCount'] as int,
          tier: pending['tier'] as String,
          acceptTerms: pending['acceptTerms'] == true,
        );
        if (id != null && mounted) await open(id);
        return;
      }
      unawaited(controller.loadGifts());
      if (!mounted) return;
      final input = await showModalBottomSheet<_NewRoom>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (_) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Theme(
            data: _roomLight(),
            child: Material(
              color: Colors.white,
              child: _CreateRoomSheet(
                coins: controller.coins,
                walletReady: controller.walletReady,
                walletLoading: controller.extrasLoading,
                serviceReady: controller.configured,
                refreshWallet: controller.loadGifts,
              ),
            ),
          ),
        ),
      );
      if (input == null || !mounted) return;
      final id = await controller.create(
        input.title,
        input.capacity,
        input.seats,
        tier: input.advanced ? 'advanced' : 'free',
        acceptTerms: input.advanced,
      );
      if (id != null && mounted) await open(id);
    } finally {
      if (mounted) setState(() => openingCreation = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData.light(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff10bfc4)),
    ),
    child: Material(
      color: Colors.white,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            key: const PageStorageKey('voice-room-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'الغرف الصوتية',
                      style: TextStyle(
                        color: Color(0xff1f2532),
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('create-voice-room'),
                    tooltip: controller.pendingCreation == null
                        ? 'إنشاء غرفة صوتية'
                        : 'إكمال طلب الإنشاء',
                    onPressed: controller.busy || openingCreation
                        ? null
                        : create,
                    icon: controller.busy
                        ? const SizedBox(
                            width: 25,
                            height: 25,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.add_circle,
                            color: Color(0xff10bfc4),
                            size: 30,
                          ),
                  ),
                  IconButton(
                    tooltip: 'متجر الإطارات والدخول',
                    onPressed: () => _showRoomShop(context, controller),
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
                ],
              ),
              const Text(
                'سوالف، أصدقاء ولحظات تجمعنا',
                style: TextStyle(color: Color(0xff858b99), fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('room-id-search'),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xfff5f6f8),
                  hintText: 'ابحث عن غرفة متقدمة بالـ ID',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (value) async {
                  final id = await controller.findRoom(value);
                  if (id != null && mounted) await open(id);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 4,
                children: [
                  for (final e in const {
                    'all': 'كل الغرف',
                    'favorites': 'المفضلة',
                    'following': 'أتابعها',
                  }.entries)
                    ChoiceChip(
                      key: ValueKey('room-scope-${e.key}'),
                      label: Text(e.value),
                      selected: controller.scope == e.key,
                      onSelected: (_) => controller.selectScope(e.key),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.leaderboard_outlined, size: 17),
                    label: const Text('نجوم تومي'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ContributionRankingPage(accounts: widget.accounts),
                      ),
                    ),
                  ),
                ],
              ),
              if (controller.pendingCreation != null)
                ListTile(
                  leading: const Icon(
                    Icons.pending_actions,
                    color: Colors.orange,
                  ),
                  title: const Text('طلب إنشاء محفوظ'),
                  subtitle: const Text(
                    'أكمل الطلب للتحقق من النتيجة بدون خصم جديد',
                  ),
                  onTap: controller.busy ? null : create,
                ),
              if (controller.loading) const LinearProgressIndicator(),
              if (controller.error != null)
                AccountErrorMessage(controller.error!),
              if (controller.notice != null)
                AccountErrorMessage(controller.notice!),
              if (!controller.configured &&
                  !controller.loading &&
                  controller.error == null)
                const AccountErrorMessage(
                  'الغرف الصوتية تنتظر تفعيل الخدمة. باقي ميزات التطبيق متاحة.',
                ),
              for (final saved in controller.savedRoomRequests.entries.where(
                (e) => e.key != controller.active?.id,
              ))
                for (final kind in ['gift', 'message'])
                  if (saved.value[kind] != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              saved.value['title'] as String? ?? 'غرفة محفوظة',
                            ),
                            Text(
                              kind == 'gift'
                                  ? 'هدية محفوظة تنتظر التحقق'
                                  : 'رسالة محفوظة تنتظر التحقق',
                            ),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: controller.busy
                                      ? null
                                      : () => controller.resolveSavedRoom(
                                          saved.key,
                                          kind,
                                        ),
                                  child: const Text('التحقق من النتيجة'),
                                ),
                                TextButton(
                                  onPressed: controller.busy
                                      ? null
                                      : () => discardSaved(saved.key, kind),
                                  child: const Text('إلغاء إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
              if (controller.ownedRoomId != null &&
                  !controller.rooms.any((r) => r.id == controller.ownedRoomId))
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () => open(controller.ownedRoomId!),
                  child: const Text('فتح غرفتي'),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'اكتشف الغرف',
                  style: TextStyle(
                    color: Color(0xff252b36),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (controller.rooms.isEmpty &&
                  controller.configured &&
                  !controller.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.spatial_audio_off_rounded,
                        size: 52,
                        color: Color(0xff10bfc4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        controller.scope == 'all'
                            ? 'بعد ماكو غرف. افتح أول غرفة لأصدقائك!'
                            : 'بعد ماكو غرف محفوظة بهالقائمة.',
                        style: const TextStyle(color: Color(0xff686e7c)),
                      ),
                      TextButton(
                        onPressed: create,
                        child: const Text('إنشاء غرفة صوتية'),
                      ),
                    ],
                  ),
                ),
              for (final room in controller.rooms) _roomRow(context, room),
              if (controller.nextBefore != null)
                TextButton(
                  onPressed: controller.loading
                      ? null
                      : () => controller.load(more: true),
                  child: const Text('غرف أكثر'),
                ),
              TextButton.icon(
                onPressed: controller.loading ? null : controller.load,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث الغرف'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _roomRow(BuildContext context, VoiceRoom room) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xfff0f1f4))),
    ),
    child: Column(
      children: [
        InkWell(
          key: Key('join-room-${room.id}'),
          onTap: controller.busy || !controller.configured
              ? null
              : () => open(room.id),
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              _RoomPicture(r: room, size: 62),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff252b36),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${room.advanced ? 'متقدمة' : 'مجانية'} • ${room.category}${room.passwordRequired ? ' • 🔒' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff8a90a0),
                        fontSize: 12,
                      ),
                    ),
                    if (room.publicId != null)
                      Text(
                        'ID ${room.publicId}',
                        style: const TextStyle(
                          color: Color(0xff18aeb8),
                          fontSize: 11,
                        ),
                      ),
                    if (room.ownerId == widget.accounts.user?.id)
                      Text(
                        room.advanced ? 'غرفتك' : 'أنت المدير الحالي',
                        style: const TextStyle(
                          color: Color(0xffbe8e27),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    color: room.memberCount > 0
                        ? const Color(0xff10bfc4)
                        : Colors.grey,
                    size: 22,
                  ),
                  Text(
                    '${room.memberCount}/${room.capacity}',
                    style: const TextStyle(
                      color: Color(0xff6c7381),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              key: ValueKey('favorite-room-${room.id}'),
              onPressed: controller.preferenceBusy.contains(room.id)
                  ? null
                  : () => controller.setPreference(
                      room,
                      favorite: !room.favorite,
                    ),
              icon: Icon(
                room.favorite ? Icons.favorite : Icons.favorite_border,
                size: 16,
                color: room.favorite ? const Color(0xfff074a0) : null,
              ),
              label: Text(
                room.favorite ? 'بالمفضلة' : 'مفضلة',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            TextButton.icon(
              key: ValueKey('follow-room-${room.id}'),
              onPressed: controller.preferenceBusy.contains(room.id)
                  ? null
                  : () => controller.setPreference(
                      room,
                      following: !room.following,
                    ),
              icon: Icon(
                room.following ? Icons.bookmark : Icons.bookmark_border,
                size: 16,
              ),
              label: Text(
                room.following ? 'أتابعها' : 'متابعة',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Expanded(
              child: Text(
                '${room.followers} متابع',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11, color: Color(0xff9a9eaa)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _NewRoom {
  const _NewRoom(this.title, this.capacity, this.seats, this.advanced);
  final String title;
  final int capacity, seats;
  final bool advanced;
}

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet({
    required this.coins,
    required this.walletReady,
    required this.walletLoading,
    required this.serviceReady,
    required this.refreshWallet,
  });
  final int coins;
  final bool walletReady, walletLoading, serviceReady;
  final Future<void> Function() refreshWallet;
  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final name = TextEditingController(), form = GlobalKey<FormState>();
  int capacity = 20, seats = 8;
  bool advanced = false, accepted = false;
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
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('مجانية'),
                    icon: Icon(Icons.groups_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('متقدمة'),
                    icon: Icon(Icons.workspace_premium_outlined),
                  ),
                ],
                selected: {advanced},
                onSelectionChanged: (v) => setState(() => advanced = v.first),
              ),
              const SizedBox(height: 12),
              if (!widget.serviceReady)
                const AccountErrorMessage(
                  'خدمة الصوت غير جاهزة حاليًا. أعد المحاولة بعد تفعيلها؛ لا يتم خصم العملات عند رفض الإنشاء.',
                ),
              if (widget.walletLoading)
                const Text('جارٍ تحديث الرصيد…', textAlign: TextAlign.center)
              else if (widget.walletReady)
                Text(
                  'رصيدك: ${widget.coins} كوينز',
                  textAlign: TextAlign.center,
                )
              else
                TextButton.icon(
                  onPressed: widget.refreshWallet,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة تحميل الرصيد'),
                ),
              const SizedBox(height: 12),
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
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: TomiColors.accent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  advanced
                      ? 'السعر 5799 كوينز، خصم مرة واحدة عند الإنشاء. مالك ثابت ومشرفون وID خاص. تُحذف الغرفة بعد 60 يومًا متواصلًا دون دخول مالكها، حتى لو دخل الآخرون. تتطور الغرفة من المستوى 1 إلى 10 حسب دعم الهدايا الإجمالي.'
                      : 'مجانية وبدون مستويات أو مشرفين. تنتقل الإدارة عشوائيًا لأحد الحاضرين عند خروج المدير، وتغلق بخروج آخر شخص. دعم النفس والآخرين يزيد الكارزما.',
                  style: const TextStyle(height: 1.6),
                ),
              ),
              if (advanced)
                CheckboxListTile(
                  key: const Key('advanced-room-terms'),
                  value: accepted,
                  onChanged: (v) => setState(() => accepted = v == true),
                  title: const Text(
                    'أوافق على السعر وشرط عدم الدخول لمدة 60 يومًا',
                  ),
                ),

              const SizedBox(height: 18),
              FilledButton(
                key: const Key('submit-voice-room'),
                onPressed:
                    advanced &&
                        (!accepted ||
                            !widget.walletReady ||
                            widget.coins < 5799)
                    ? null
                    : () {
                        if (form.currentState!.validate())
                          Navigator.pop(
                            context,
                            _NewRoom(
                              name.text.trim(),
                              capacity,
                              seats,
                              advanced,
                            ),
                          );
                      },
                child: Text(
                  advanced ? 'شراء الغرفة • 5799 كوينز' : 'إنشاء ودخول',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
