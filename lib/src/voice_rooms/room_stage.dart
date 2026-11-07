part of 'room_screens.dart';

const _roomGold = Color(0xfff6d37c),
    _roomPink = Color(0xffff72ad),
    _roomCyan = Color(0xff6fe1eb);
Color _roomAccent(VoiceRoom r) => switch (r.theme) {
  'rose' => _roomPink,
  'ice' => _roomCyan,
  _ => _roomGold,
};
List<Color> _roomSky(VoiceRoom r) => switch (r.background) {
  'dusk' => const [Color(0xff301447), Color(0xff772f75), Color(0xff221033)],
  'forest' => const [Color(0xff062c32), Color(0xff176b64), Color(0xff061c30)],
  'midnight' => const [Color(0xff090f27), Color(0xff263259), Color(0xff080c20)],
  _ => const [TomiColors.background, TomiColors.surface, TomiColors.background],
};

class VoiceRoomPage extends StatefulWidget {
  const VoiceRoomPage({super.key, required this.controller});
  final VoiceRoomsController controller;
  @override
  State<VoiceRoomPage> createState() => _VoiceRoomPageState();
}

class _VoiceRoomPageState extends State<VoiceRoomPage>
    with WidgetsBindingObserver {
  VoiceRoomsController get c => widget.controller;
  final message = TextEditingController(), chat = ScrollController();
  bool leaving = false, sendingImage = false;
  late final effects = RoomEffectsController(
    (c.active?.events ?? [])
        .where(
          (e) =>
              e.effect?['kind'] != 'entrance' ||
              e.actor.id != c.accounts.user?.id,
        )
        .toList(),
  );
  @override
  void initState() {
    super.initState();
    message.text = c.pendingMessage?['text'] as String? ?? c.roomDraft;
    if (c.minimized)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.expand();
      });
    c.addListener(changed);
    effects.addListener(effectChanged);
    effects.ingest(
      (c.active?.events ?? [])
          .where(
            (e) =>
                e.effect?['kind'] == 'entrance' &&
                e.actor.id == c.accounts.user?.id,
          )
          .toList(),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  void effectChanged() {
    if (mounted) setState(() {});
  }

  void changed() {
    effects.ingest(c.active?.events ?? []);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    effects.visibility(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(changed);
    effects.removeListener(effectChanged);
    effects.dispose();
    message.dispose();
    chat.dispose();
    super.dispose();
  }

  void minimize() {
    c.minimize();
    Navigator.pop(context);
  }

  Future<void> leave() async {
    if (leaving) return;
    setState(() => leaving = true);
    await c.leave();
    if (mounted) Navigator.pop(context);
  }

  Future<void> gifts([String? recipient]) =>
      _showRoomGifts(context, c, recipient);
  Future<void> info() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (_) => _RoomInfo(c: c),
  );
  Future<void> members({bool requests = false}) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _RoomMembers(c: c, requests: requests),
  );
  Future<void> settings() async {
    if (c.me?.role != 'owner') return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => RoomSettingsPage(controller: c)),
    );
  }

  Future<void> tools() {
    FocusScope.of(context).unfocus();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: TomiColors.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheet) => RoomToolsSheet(
        accent: _roomCyan,
        actions: <(IconData, String, VoidCallback)>[
          if (c.me?.role == 'owner')
            (
              Icons.person_add_alt_1,
              'دعوة صديق',
              () {
                final room = c.active;
                Navigator.pop(sheet);
                if (room != null)
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SendInvitationPage(
                        accounts: c.accounts,
                        kind: 'room',
                        targetId: room.id,
                      ),
                    ),
                  );
              },
            ),
          (
            Icons.qr_code_2,
            'مشاركة الغرفة',
            () {
              Navigator.pop(sheet);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ShareCodePage(
                    url: 'tomi://room/${c.active!.id}',
                    title: 'مشاركة الغرفة',
                  ),
                ),
              );
            },
          ),
          (
            Icons.poll_outlined,
            'تصويت الغرفة',
            () {
              Navigator.pop(sheet);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CommunityPage(
                    accounts: c.accounts,
                    kind: 'polls',
                    title: 'تصويت الغرفة',
                    roomId: c.active!.id,
                    canCreate: c.me?.role == 'owner',
                  ),
                ),
              );
            },
          ),
          (
            Icons.casino_outlined,
            'مدار الحظ',
            () {
              Navigator.pop(sheet);
              showLiveRoulette(context, c.accounts, c.active!.id);
            },
          ),
          (
            Icons.info_outline,
            'معلومات الغرفة',
            () {
              Navigator.pop(sheet);
              info();
            },
          ),
          (
            Icons.people_outline,
            'الأعضاء',
            () {
              Navigator.pop(sheet);
              members();
            },
          ),
          (
            Icons.leaderboard_outlined,
            'مساهمو الغرفة',
            () {
              Navigator.pop(sheet);
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ContributionRankingPage(
                    accounts: c.accounts,
                    roomId: c.active!.id,
                  ),
                ),
              );
            },
          ),
          (
            Icons.redeem_rounded,
            'الهدايا',
            () {
              Navigator.pop(sheet);
              gifts();
            },
          ),
          (
            Icons.auto_awesome,
            'متجر الغرفة',
            () {
              Navigator.pop(sheet);
              _showRoomShop(context, c);
            },
          ),
          if (c.manage)
            (
              Icons.pan_tool_outlined,
              'طلبات المايك',
              () {
                Navigator.pop(sheet);
                members(requests: true);
              },
            ),
          if (c.me?.role == 'owner')
            (
              Icons.settings_outlined,
              'إعدادات الغرفة',
              () {
                Navigator.pop(sheet);
                settings();
              },
            ),
          (
            Icons.logout_rounded,
            'خروج',
            () {
              Navigator.pop(sheet);
              leave();
            },
          ),
        ],
      ),
    );
  }

  Future<void> seatAction(VoiceRoom r, int index) async {
    final m = r.seated(index);
    if (m != null) {
      if (m.user.id == c.accounts.user?.id) {
        final choice = await _roomChoice(context, 'مقعدك', [
          c.microphoneOn ? 'كتم المايك' : 'فتح المايك',
          'دعم نفسي',
          if (c.manage && index != -1 && r.seatMuted(index)) 'إلغاء كتم المقعد',
          if (index != -1) 'النزول من المقعد',
        ]);
        if (choice == 'دعم نفسي') {
          await gifts(m.user.id);
          return;
        }
        if (choice == null) return;
        if (choice == 'إلغاء كتم المقعد') {
          await c.action(
            'seat-control',
            body: {'seat': index, 'operation': 'allow'},
          );
        } else if (choice == 'النزول من المقعد') {
          await c.action('leave-seat');
        } else {
          await microphone();
        }
        return;
      }
      await _memberActions(context, c, m, onGift: () => gifts(m.user.id));
      return;
    }
    if (index == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا مكان المالك؛ يبقى محجوزًا حتى وهو خارج الغرفة.'),
        ),
      );
      return;
    }
    final actions = <String>[
      if (c.manage) r.seatLocked(index) ? 'فتح المايك' : 'قفل المايك',
      if (c.manage) r.seatMuted(index) ? 'إلغاء كتم المقعد' : 'كتم الصوت',
      if (c.manage) 'الدعوة',
      if (c.manage && c.me?.role != 'owner' && !r.seatLocked(index))
        'الانتقال إلى مقعد المايك هذا',
      if (!c.manage && !r.seatLocked(index) && c.me?.seat == null) 'طلب المايك',
    ];
    if (actions.isEmpty) return;
    final choice = await _roomChoice(
      context,
      index == -2 ? 'المقعد المميز' : 'مقعد ${index + 1}',
      actions,
    );
    if (choice == null || !mounted) return;
    if (choice == 'طلب المايك') {
      await c.action('request-mic');
      return;
    }
    if (choice == 'الانتقال إلى مقعد المايك هذا') {
      await c.action('take-seat', body: {'seat': index});
      return;
    }
    if (choice == 'الدعوة') {
      final listeners =
          c.active?.members.where((m) => m.seat == null).toList() ?? [];
      if (listeners.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ماكو مستمع متاح للدعوة.')),
        );
        return;
      }
      final target = await showModalBottomSheet<VoiceMember>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('دعوة إلى المايك — ينتظر قبول العضو')),
              for (final member in listeners)
                ListTile(
                  leading: AccountAvatar(member.user, size: 38),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.user.displayName),
                      CharismaBadge(member.user.identity),
                    ],
                  ),
                  onTap: () => Navigator.pop(sheet, member),
                ),
            ],
          ),
        ),
      );
      if (target != null)
        await c.action(
          'invite',
          body: {'seat': index, 'targetId': target.user.id},
        );
      return;
    }
    final op = switch (choice) {
      'فتح المايك' => 'unlock',
      'قفل المايك' => 'lock',
      'كتم الصوت' => 'mute',
      _ => 'allow',
    };
    await c.action('seat-control', body: {'seat': index, 'operation': op});
  }

  Future<void> microphone() async {
    if (c.me?.seat == null) {
      await c.action(
        c.me?.requestedAt == null ? 'request-mic' : 'cancel-request',
      );
      return;
    }
    if (c.me?.role == 'owner' && c.me?.micAllowed != true)
      await c.action('take-seat');
    await c.toggleMicrophone();
  }

  Future<void> send() async {
    if (c.busy) return;
    final text = message.text.trim();
    if (text.isEmpty && c.pendingMessage == null) return;
    if (await c.sendMessage(text) && mounted) message.clear();
  }

  Future<void> picture() async {
    if (sendingImage || c.busy) return;
    setState(() => sendingImage = true);
    try {
      final f = await c.mediaPicker(
        () => ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 88,
        ),
      );
      if (f == null || c.active == null) return;
      final image = await readPickedImage(f);
      await c.sendMessage(message.text.trim(), image: image);
      if (mounted && c.pendingMessage == null) message.clear();
    } on AccountFailure catch (e) {
      c.error = e.message;
      c.notify();
    } catch (_) {
      c.error = 'تعذّر اختيار الصورة.';
      c.notify();
    } finally {
      if (mounted) setState(() => sendingImage = false);
    }
  }

  Widget seat(VoiceRoom r, int index, {bool special = false}) {
    final m = r.seated(index),
        owner = index == -1,
        person = m?.user ?? (owner ? r.owner : null),
        active = m != null && c.audio?.speakers.contains(m.identity) == true,
        locked = owner && m == null || r.seatLocked(index),
        muted = r.seatMuted(index) || m != null && !m.micAllowed,
        accent = _roomAccent(r);
    final size = special ? 76.0 : 52.0;
    return Semantics(
      label: owner
          ? 'مقعد المالك المحجوز'
          : 'مقعد ${index == -2 ? 'مميز' : index + 1}',
      child: InkWell(
        key: Key('room-seat-$index'),
        onTap: c.busy ? null : () => seatAction(r, index),
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size + 14,
                height: size + 14,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: size + 10,
                      height: size + 10,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? accent.withValues(alpha: .14)
                            : Colors.transparent,
                        border: Border.all(
                          color: active
                              ? _roomCyan
                              : accent.withValues(
                                  alpha: person == null ? 0.55 : 0.95,
                                ),
                          width: active ? 3 : 1.2,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: _roomCyan.withValues(alpha: .3),
                                  blurRadius: 15,
                                  spreadRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: person == null
                          ? Icon(
                              locked
                                  ? Icons.lock_outline_rounded
                                  : Icons.add_rounded,
                              color: accent.withValues(alpha: .7),
                              size: special ? 32 : 27,
                            )
                          : Opacity(
                              opacity: m == null ? 0.48 : 1,
                              child: MediaQuery.withNoTextScaling(
                                child: AccountAvatar(person, size: size),
                              ),
                            ),
                    ),
                    if (owner)
                      Positioned(
                        top: 0,
                        right: 1,
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          size: 22,
                          color: accent,
                        ),
                      ),
                    if (locked || muted)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Icon(
                          locked ? Icons.lock : Icons.mic_off,
                          color: _roomPink,
                          size: 18,
                        ),
                      ),
                    if (m != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xff08244d),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            c.audio?.openMics.contains(m.identity) == true
                                ? Icons.mic
                                : Icons.mic_off,
                            size: 13,
                            color: m.micAllowed ? _roomCyan : _roomPink,
                          ),
                        ),
                      ),
                    if (owner && m == null)
                      const Positioned(
                        bottom: 0,
                        left: 0,
                        child: Icon(Icons.lock, size: 15, color: _roomGold),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                person?.displayName ??
                    (index == -2 ? 'مقعد مميز' : '${index + 1}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: special ? 13 : 10,
                  color: Colors.white.withValues(
                    alpha: person == null ? 0.65 : 1,
                  ),
                ),
              ),
              if (person != null) CharismaBadge(person.identity),
              if (locked || muted)
                Text(
                  locked ? 'مغلق' : 'مكتوم',
                  style: const TextStyle(fontSize: 9, color: _roomPink),
                ),
              if (special)
                Text(
                  owner
                      ? (r.advanced
                            ? 'المالك • محجوز دائمًا'
                            : 'مدير الغرفة الحالي')
                      : 'بالدعوة والموافقة',
                  style: TextStyle(fontSize: 10, color: accent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget stage(VoiceRoom r) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(width: 116, child: seat(r, -1, special: true)),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: _roomPink.withValues(alpha: .65)),
                    boxShadow: [
                      BoxShadow(
                        color: _roomPink.withValues(alpha: .12),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      children: [
                        Text(
                          'TOMI',
                          style: TextStyle(
                            fontSize: 23,
                            letterSpacing: 5,
                            fontWeight: FontWeight.w300,
                            color: _roomCyan,
                            shadows: [Shadow(color: _roomCyan, blurRadius: 16)],
                          ),
                        ),
                        Text(
                          'VOICE CLUB',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            color: _roomPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (r.companionEnabled)
                SizedBox(width: 106, child: seat(r, -2, special: true)),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final columns = MediaQuery.textScalerOf(context).scale(14) > 20
                ? 2
                : 4;
            return Column(
              children: [
                for (var row = 0; row < (r.seatCount / columns).ceil(); row++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (columns == 4)
                          Positioned(
                            top: 34,
                            left: 0,
                            right: 0,
                            child: CustomPaint(
                              size: Size(box.maxWidth, 12),
                              painter: _SeatWaves(
                                color: _roomAccent(r).withValues(alpha: .35),
                                active: r.members.any(
                                  (m) =>
                                      m.seat != null &&
                                      m.seat! >= 0 &&
                                      c.audio?.speakers.contains(m.identity) ==
                                          true,
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            for (var col = 0; col < columns; col++)
                              Expanded(
                                child: row * columns + col < r.seatCount
                                    ? seat(r, row * columns + col)
                                    : const SizedBox(),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        if (r.announcement.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.campaign_outlined,
                    size: 16,
                    color: _roomGold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.announcement,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xffe1ecff),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
  Widget header(VoiceRoom r) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 12, 3),
    child: Column(
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('leave-voice-room'),
              tooltip: 'تصغير الغرفة',
              onPressed: minimize,
              icon: const Icon(
                Icons.chevron_right_rounded,
                textDirection: TextDirection.ltr,
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: info,
                child: Row(
                  children: [
                    _RoomPicture(r: r, size: 35),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              _RoomTierBadge(r.advanced),
                            ],
                          ),
                          Text(
                            '${r.category}  •  ${r.memberCount} عضو${r.passwordRequired ? '  🔒' : ''}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xffadc7eb),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'الأعضاء',
              onPressed: () => members(),
              icon: const Icon(Icons.people_outline_rounded, size: 21),
            ),
            IconButton(
              tooltip: 'وظائف الغرفة',
              onPressed: tools,
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              r.publicId == null
                  ? 'غرفة مجانية • إدارة متغيرة'
                  : 'ID: ${r.publicId} • المستوى ${r.level ?? 1}',
              style: TextStyle(fontSize: 10, color: _roomGold),
            ),
            const Text('  |  ', style: TextStyle(color: Colors.white24)),
            Icon(
              c.reconnecting ? Icons.sync : Icons.headphones_rounded,
              size: 13,
              color: _roomCyan,
            ),
            const SizedBox(width: 5),
            Text(
              c.reconnecting
                  ? 'جارٍ استعادة الاتصال…'
                  : 'دردشة جماعية • ${r.mode}',
              style: const TextStyle(fontSize: 10, color: Color(0xffbad1ef)),
            ),
            if (c.manage && r.members.any((m) => m.requestedAt != null))
              TextButton(
                onPressed: () => members(requests: true),
                child: Text(
                  'طلبات ${r.members.where((m) => m.requestedAt != null).length}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    ),
  );
  Widget chatEvent(RoomEvent e) {
    final gifted = e.kind == 'gift';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: (gifted ? _roomPink : Colors.black).withValues(
          alpha: gifted ? 0.10 : 0.12,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.kind != 'system')
                MediaQuery.withNoTextScaling(
                  child: AccountAvatar(e.actor, size: 23),
                ),
              const SizedBox(width: 7),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (e.kind != 'system')
                        TextSpan(
                          text: '${e.actor.displayName}  ',
                          style: const TextStyle(
                            color: _roomGold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      TextSpan(
                        text: gifted
                            ? 'أرسل ${e.text} ×${e.gift!['quantity']} إلى ${e.recipient?.displayName ?? 'عضو'}'
                            : e.text,
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: e.kind == 'system' ? _roomGold : Colors.white,
                  ),
                ),
              ),
              if (gifted)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _GiftArt(icon: e.gift!['giftId'] as String, size: 35),
                ),
            ],
          ),
          if (e.image?['url'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    child: InteractiveViewer(
                      child: NetworkMediaImage(
                        e.image!['url'] as String,
                        errorBuilder: (_, _, _) => const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('تعذّر عرض الصورة.'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: NetworkMediaImage(
                    e.image!['url'] as String,
                    width: 160,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Text('تعذّر عرض الصورة.'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget events(VoiceRoom r, {bool expanded = true}) {
    final all = c.events;
    if (all.isEmpty)
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'هلا بيكم! ابدأوا السالفة أو أرسلوا أول هدية.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xffb3cdec)),
          ),
        ),
      );
    final older = TextButton(
      onPressed: c.historyLoading ? null : c.olderEvents,
      child: Text(c.historyLoading ? 'جارٍ التحميل…' : 'رسائل أقدم'),
    );
    if (!expanded)
      return Column(
        children: [if (c.eventsBefore != null) older, ...all.map(chatEvent)],
      );
    return ListView.builder(
      controller: chat,
      reverse: true,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: all.length + (c.eventsBefore == null ? 0 : 1),
      itemBuilder: (_, i) =>
          i == all.length ? older : chatEvent(all[all.length - 1 - i]),
    );
  }

  Widget composer(VoiceRoom r) {
    final request = c.me?.seat == null, requested = c.me?.requestedAt != null;
    return Container(
      color: TomiColors.surface.withValues(alpha: .90),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 6, 5, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.historyWindow)
                TextButton(
                  onPressed: c.latestEvents,
                  child: const Text('الرجوع لأحدث الرسائل'),
                ),
              if (c.pendingMessage != null)
                Wrap(
                  children: [
                    TextButton(
                      onPressed: c.busy ? null : () => c.retrySend('message'),
                      child: const Text('التحقق وإعادة إرسال الرسالة المعلّقة'),
                    ),
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => c.cancelPending('message'),
                      child: const Text('إلغاء إعادة المحاولة'),
                    ),
                  ],
                ),
              if (r.pending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'جارٍ تطبيق صلاحيات الصوت…',
                    style: TextStyle(fontSize: 11, color: _roomGold),
                  ),
                ),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    c.error!,
                    style: const TextStyle(
                      color: Color(0xffffa9c9),
                      fontSize: 12,
                    ),
                  ),
                ),
              if (c.pendingGift != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.cancelPending('gift'),
                  child: const Text('إلغاء إعادة محاولة الهدية'),
                ),
              if (c.pendingGift != null)
                TextButton(
                  onPressed: c.busy ? null : () => c.retrySend('gift'),
                  child: const Text(
                    'نتيجة الهدية غير مؤكدة — إعادة المحاولة لنفس الإرسال',
                  ),
                ),
              if (r.invitation != null)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'دعوة إلى المايك',
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => c.action(
                              'answer-invite',
                              body: {'accept': true},
                            ),
                      child: const Text('قبول'),
                    ),
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => c.action(
                              'answer-invite',
                              body: {'accept': false},
                            ),
                      child: const Text('رفض'),
                    ),
                  ],
                ),
              if (c.microphoneOn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'مدة فتح المايك • ${c.microphoneSeconds ~/ 60}:${(c.microphoneSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: _roomCyan, fontSize: 12),
                  ),
                ),
              Row(
                children: [
                  _roomTool(Icons.grid_view_rounded, 'وظائف الغرفة', tools),
                  _roomTool(
                    Icons.card_giftcard_rounded,
                    'الهدايا',
                    () => gifts(),
                    color: _roomPink,
                  ),
                  if (!r.imagesDisabled)
                    _roomTool(
                      Icons.add_photo_alternate_outlined,
                      'إرسال صورة',
                      sendingImage || c.busy ? null : picture,
                    ),
                  Expanded(
                    child: TextField(
                      key: const Key('room-chat-input'),
                      controller: message,
                      onChanged: c.setRoomDraft,
                      enabled:
                          c.pendingMessage == null &&
                          !c.busy &&
                          (!r.chatDisabled || c.manage),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => send(),
                      style: const TextStyle(fontSize: 12),
                      maxLength: 500,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: r.chatDisabled && !c.manage
                            ? 'الدردشة مقفلة'
                            : 'أدخل نص هنا',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 11,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          tooltip: c.pendingMessage != null
                              ? 'إعادة إرسال الرسالة'
                              : 'إرسال',
                          onPressed: c.busy ? null : send,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            c.pendingMessage != null
                                ? Icons.refresh_rounded
                                : Icons.send_rounded,
                            size: 17,
                            color: _roomCyan,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _roomTool(
                    request
                        ? (requested ? Icons.pan_tool : Icons.pan_tool_outlined)
                        : (c.microphoneOn ? Icons.mic : Icons.mic_off),
                    request
                        ? (requested ? 'إلغاء طلب المايك' : 'طلب المايك')
                        : (c.microphoneOn ? 'كتم المايك' : 'فتح المايك'),
                    c.busy || c.micBusy ? null : microphone,
                    color: c.microphoneOn ? _roomCyan : Colors.white,
                    buttonKey: request
                        ? const Key('room-request-mic')
                        : const Key('room-microphone'),
                  ),
                  _roomTool(
                    c.speakerOn
                        ? Icons.volume_up_outlined
                        : Icons.hearing_outlined,
                    'مخرج الصوت',
                    c.toggleSpeaker,
                  ),
                ],
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
      return Theme(
        data: TomiTheme.dark(),
        child: PopScope(
          canPop: r == null || leaving,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) minimize();
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: TomiColors.surface,
            body: r == null
                ? SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.headset_off_rounded, size: 52),
                            const SizedBox(height: 16),
                            Text(c.notice ?? 'غادرت الغرفة.'),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('الرجوع للغرف'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _roomSky(r),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _RoomStars()),
                          ),
                        ),
                        SafeArea(
                          bottom: false,
                          child: Column(
                            children: [
                              header(r),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, box) {
                                    if (box.maxHeight < 460 ||
                                        MediaQuery.textScalerOf(
                                              context,
                                            ).scale(14) >
                                            20)
                                      return SingleChildScrollView(
                                        child: Column(
                                          children: [
                                            stage(r),
                                            events(r, expanded: false),
                                          ],
                                        ),
                                      );
                                    return Column(
                                      children: [
                                        stage(r),
                                        Expanded(child: events(r)),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              composer(r),
                            ],
                          ),
                        ),
                        if (effects.active != null)
                          Positioned.fill(
                            child: RoomEffectOverlay(
                              key: ValueKey(
                                'room-effect-${effects.active!.sequence}',
                              ),
                              event: effects.active!,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    },
  );
}

Widget _roomTool(
  IconData icon,
  String label,
  VoidCallback? tap, {
  Color color = Colors.white,
  Key? buttonKey,
}) => SizedBox(
  width: 39,
  child: IconButton(
    key: buttonKey,
    tooltip: label,
    onPressed: tap,
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 22, color: tap == null ? Colors.white30 : color),
  ),
);

class _RoomTierBadge extends StatelessWidget {
  const _RoomTierBadge(this.advanced);
  final bool advanced;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: (advanced ? _roomGold : _roomCyan).withValues(alpha: .15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      advanced ? 'متقدمة' : 'مجانية',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: advanced ? _roomGold : _roomCyan,
      ),
    ),
  );
}

class _RoomPicture extends StatelessWidget {
  const _RoomPicture({required this.r, this.size = 52});
  final VoiceRoom r;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (r.image?['url'] != null)
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * .28),
        child: NetworkMediaImage(
          r.image!['url'] as String,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        ),
      );
    if (r.picture == 'owner' && r.owner != null)
      return MediaQuery.withNoTextScaling(
        child: AccountAvatar(
          r.owner!.withIdentity(
            UserIdentity({
              ...r.owner!.identity.data,
              'frameId': 'none',
              'roomFrameId': 'none',
              'portraitId': 'none',
            }),
          ),
          size: size,
        ),
      );
    return fallback();
  }

  Widget fallback() => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .28),
      gradient: LinearGradient(
        colors: [_roomAccent(r), const Color(0xff5772c6)],
      ),
    ),
    child: Icon(
      switch (r.picture) {
        'moon' => Icons.nightlight_round,
        'crown' => Icons.workspace_premium_rounded,
        'game' => Icons.sports_esports_rounded,
        'music' => Icons.music_note_rounded,
        _ => Icons.headphones_rounded,
      },
      size: size * .55,
      color: Colors.white,
    ),
  );
}

class _RoomStars extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(84),
        p = Paint()..color = Colors.white.withValues(alpha: .12);
    for (var i = 0; i < 55; i++)
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        rng.nextDouble() * 1.6 + .4,
        p,
      );
    final path = Path()
      ..moveTo(0, size.height * .78)
      ..quadraticBezierTo(
        size.width * .4,
        size.height * .71,
        size.width,
        size.height * .88,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xff07144a).withValues(alpha: .27),
    );
  }

  @override
  bool shouldRepaint(covariant _RoomStars oldDelegate) => false;
}

class _SeatWaves extends CustomPainter {
  _SeatWaves({required this.color, required this.active});
  final Color color;
  final bool active;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (final center in [s.width * .25, s.width * .75]) {
      final path = Path()..moveTo(center - 13, 6);
      for (var x = -13; x <= 13; x++)
        path.lineTo(
          center + x,
          6 + (active ? math.sin(x * 1.1) * (13 - x.abs()) * .6 : 0),
        );
      c.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SeatWaves o) =>
      o.active != active || o.color != color;
}
