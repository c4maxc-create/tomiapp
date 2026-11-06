part of 'room_screens.dart';

Widget _roomLightSurface(Widget child) => Theme(
  data: _roomLight(),
  child: Material(color: Colors.white, child: child),
);

ThemeData _roomLight() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff17bdce),
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: Color(0xff282d3c),
    centerTitle: true,
    elevation: 0,
  ),
);
Future<String?> _roomText(
  BuildContext context,
  String title,
  String value, {
  bool secret = false,
  int max = 64,
}) async {
  final text = TextEditingController(text: value);
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => Theme(
      data: _roomLight(),
      child: AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          obscureText: secret,
          maxLength: max,
          minLines: secret ? 1 : null,
          maxLines: secret ? 1 : null,
          decoration: InputDecoration(
            hintText: secret ? '4 أحرف على الأقل' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, text.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
  // A dialog's reverse transition still reads its controller for one frame.
  WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
  return result;
}

Future<String?> _roomChoice(
  BuildContext context,
  String title,
  List<String> options,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  showDragHandle: true,
  builder: (sheet) => Theme(
    data: _roomLight(),
    child: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xff222838),
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                dense: true,
                title: Text(option, textAlign: TextAlign.center),
                onTap: () => Navigator.pop(sheet, option),
              ),
            ListTile(
              title: const Text('إلغاء', textAlign: TextAlign.center),
              onTap: () => Navigator.pop(sheet),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _memberActions(
  BuildContext context,
  VoiceRoomsController c,
  VoiceMember m, {
  VoidCallback? onGift,
}) async {
  final me = c.me;
  if (me == null) return;
  final manage =
      c.manage &&
      m.role != 'owner' &&
      m.user.id != me.user.id &&
      (me.role == 'owner' || m.role == 'member');
  final choices = <String>[
    'إرسال هدية',
    if (manage && m.requestedAt != null) ...['قبول طلب المايك', 'رفض الطلب'],
    if (manage && m.seat != null) ...[
      if (c.active?.seatMuted(m.seat!) == true) 'إلغاء كتم المقعد',
      if (c.active?.seatLocked(m.seat!) == true) 'فتح قفل المقعد',
      m.micAllowed ? 'كتم المايك بالإدارة' : 'السماح بفتح المايك',
      'إنزال إلى المستمعين',
    ],
    if (manage && me.role == 'owner' && c.active?.advanced == true)
      m.role == 'moderator' ? 'إلغاء الإشراف' : 'تعيين مشرف',
    if (manage) 'إزالة من الغرفة',
  ];
  final choice = await _roomChoice(context, m.user.displayName, choices);
  if (choice == null || !context.mounted) return;
  if (choice == 'إرسال هدية') {
    if (onGift != null)
      onGift();
    else
      await _showRoomGifts(context, c, m.user.id);
    return;
  }
  if (choice == 'إلغاء كتم المقعد' || choice == 'فتح قفل المقعد') {
    await c.action(
      'seat-control',
      body: {
        'seat': m.seat,
        'operation': choice == 'إلغاء كتم المقعد' ? 'allow' : 'unlock',
      },
    );
    return;
  }
  final operation = switch (choice) {
    'قبول طلب المايك' => 'approve',
    'رفض الطلب' => 'reject',
    'كتم المايك بالإدارة' => 'mute',
    'السماح بفتح المايك' => 'allow-mic',
    'إنزال إلى المستمعين' => 'lower',
    'تعيين مشرف' => 'promote',
    'إلغاء الإشراف' => 'demote',
    _ => 'kick',
  };
  if (operation == 'kick') {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('إزالة ${m.user.displayName}؟'),
        content: const Text(
          'يبقى بالقائمة السوداء إلى أن يسمح له المالك بالرجوع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (yes != true) return;
  }
  await c.moderate(m, operation);
}

class _RoomMembers extends StatelessWidget {
  const _RoomMembers({required this.c, this.requests = false});
  final VoiceRoomsController c;
  final bool requests;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final members =
          c.active?.members
              .where((m) => !requests || m.requestedAt != null)
              .toList() ??
          [];
      if (requests)
        members.sort(
          (a, b) => (a.requestedAt ?? '').compareTo(b.requestedAt ?? ''),
        );
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  requests
                      ? 'انتظار المايك • ${members.length}'
                      : 'الأعضاء • ${members.length}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (members.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('ماكو طلبات مايك حاليًا.'),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final m in members)
                      ListTile(
                        leading: MediaQuery.withNoTextScaling(
                          child: AccountAvatar(m.user, size: 40),
                        ),
                        title: Text(
                          requests
                              ? '${members.indexOf(m) + 1}. ${m.user.displayName}'
                              : m.user.displayName,
                        ),
                        subtitle: Text(
                          m.role == 'owner'
                              ? 'المالك'
                              : m.role == 'moderator'
                              ? 'مشرف'
                              : m.seat == null
                              ? 'مستمع'
                              : 'متحدث',
                        ),
                        trailing: requests
                            ? IconButton(
                                tooltip: 'قبول طلب المايك',
                                onPressed: c.busy
                                    ? null
                                    : () => c.moderate(m, 'approve'),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  color: _roomCyan,
                                ),
                              )
                            : null,
                        onTap: () => _memberActions(context, c, m),
                      ),
                  ],
                ),
              ),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    c.error!,
                    style: const TextStyle(color: _roomPink),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _GiftArt extends StatelessWidget {
  const _GiftArt({required this.icon, this.size = 56});
  final String icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (glyph, color) = switch (icon) {
      'rose' => (Icons.local_florist_rounded, const Color(0xffff81b1)),
      'heart' => (Icons.favorite_rounded, const Color(0xffff6199)),
      'applause' => (Icons.celebration_rounded, const Color(0xfff6cd75)),
      'cake' => (Icons.cake_rounded, const Color(0xffffa6cb)),
      'diamond' => (Icons.diamond_rounded, const Color(0xff79e6ff)),
      'crown' => (Icons.workspace_premium_rounded, const Color(0xffffd777)),
      'car' => (Icons.directions_car_filled_rounded, const Color(0xffff8eab)),
      _ => (Icons.rocket_launch_rounded, const Color(0xffb7a0ff)),
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * .8,
            height: size * .8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: .25),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: icon == 'rocket' ? -.2 : 0,
            child: Icon(
              glyph,
              size: size * .7,
              color: color,
              shadows: [
                Shadow(
                  color: color.withValues(alpha: .4),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
          Positioned(
            top: size * .03,
            right: size * .08,
            child: Icon(
              Icons.auto_awesome,
              size: size * .17,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showRoomGifts(
  BuildContext context,
  VoiceRoomsController c, [
  String? recipient,
]) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0xff191d30),
  showDragHandle: true,
  builder: (_) => Theme(
    data: ThemeData.dark(useMaterial3: true),
    child: Material(
      color: const Color(0xff191d30),
      child: _RoomGiftSheet(c: c, recipient: recipient),
    ),
  ),
);

class _RoomGiftSheet extends StatefulWidget {
  const _RoomGiftSheet({required this.c, this.recipient});
  final VoiceRoomsController c;
  final String? recipient;
  @override
  State<_RoomGiftSheet> createState() => _RoomGiftSheetState();
}

class _RoomGiftSheetState extends State<_RoomGiftSheet> {
  VoiceRoomsController get c => widget.c;
  String? recipient, gift;
  String category = 'الكل';
  int quantity = 1;
  String audience = 'person';
  @override
  void initState() {
    super.initState();
    recipient = widget.recipient;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(c.loadGifts());
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final members = c.active?.members.toList() ?? [];
      final pending = c.pendingGift;
      final selectedAudience = pending?['audience'] as String? ?? audience;
      final targetCount = selectedAudience == 'person'
          ? 1
          : members
                .where(
                  (m) =>
                      selectedAudience == 'all' ||
                      (selectedAudience == 'mics'
                          ? m.seat != null
                          : m.seat == null),
                )
                .length;
      final selectedRecipient =
          pending?['recipientId'] as String? ??
          recipient ??
          members.firstOrNull?.user.id;
      final selectedGift =
          pending?['giftId'] as String? ?? gift ?? c.gifts.firstOrNull?.id;
      final selected = c.gifts.where((g) => g.id == selectedGift).firstOrNull;
      final count = (pending?['quantity'] as int?) ?? quantity;
      final items = c.gifts
          .where((g) => category == 'الكل' || g.category == category)
          .toList();
      final large =
          MediaQuery.textScalerOf(context).scale(14) > 20 ||
          MediaQuery.sizeOf(context).height < 500;
      final children = <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, color: _roomPink),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'هدايا الغرفة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'عملات تجريبية',
                      style: TextStyle(color: _roomGold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تحديث الهدايا والرصيد',
                onPressed: c.extrasLoading ? null : c.loadGifts,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
        ),
        if (c.extrasLoading) const LinearProgressIndicator(minHeight: 2),
        if (members.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('انتظر دخول الغرفة لدعم نفسك أو الآخرين.'),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              for (final option in const {
                'person': 'شخص / نفسي',
                'mics': 'كل المايكات',
                'viewers': 'كل المشاهدين',
                'all': 'كل الغرفة',
              }.entries)
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: ChoiceChip(
                    label: Text(option.value),
                    selected: selectedAudience == option.key,
                    onSelected: pending != null
                        ? null
                        : (_) => setState(() => audience = option.key),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(14) > 20 ? 105 : 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              for (final m in members)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    key: Key('gift-recipient-${m.user.id}'),
                    onTap: pending != null
                        ? null
                        : () => setState(() => recipient = m.user.id),
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: 62,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selectedRecipient == m.user.id
                                    ? _roomPink
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: MediaQuery.withNoTextScaling(
                              child: AccountAvatar(m.user, size: 40),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            m.user.id == c.accounts.user?.id
                                ? 'نفسي'
                                : m.user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final label in [
                'الكل',
                ...c.gifts.map((g) => g.category).toSet(),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: category == label,
                    onSelected: (_) => setState(() => category = label),
                    selectedColor: const Color(0xff653c71),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: c.gifts.isEmpty
              ? Center(child: Text(c.error ?? 'جارٍ تحميل الهدايا…'))
              : LayoutBuilder(
                  builder: (context, box) {
                    final columns =
                        box.maxWidth < 330 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20
                        ? 2
                        : 4;
                    return GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 7,
                        crossAxisSpacing: 6,
                        mainAxisExtent:
                            MediaQuery.textScalerOf(context).scale(14) > 20
                            ? 163
                            : 135,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final g = items[i], isSelected = selectedGift == g.id;
                        return InkWell(
                          key: Key('gift-${g.id}'),
                          onTap: pending != null
                              ? null
                              : () => setState(() => gift = g.id),
                          borderRadius: BorderRadius.circular(15),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xff392d50)
                                  : Colors.white.withValues(alpha: .025),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: isSelected
                                    ? _roomPink
                                    : Colors.white.withValues(alpha: .06),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _GiftArt(icon: g.icon, size: 62),
                                Text(
                                  g.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.monetization_on_rounded,
                                      size: 12,
                                      color: _roomGold,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${g.price}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xffc7c4d6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        if (c.error != null && c.gifts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
            child: Text(
              c.error!,
              style: const TextStyle(fontSize: 12, color: _roomPink),
            ),
          ),
        if (pending != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Text(
              c.pendingGiftRoom != c.active?.id
                  ? 'ارجع للغرفة السابقة لتأكيد الهدية العالقة.'
                  : 'إرسال سابق ينتظر التأكيد؛ المحاولة تعيد نفس الطلب.',
              style: TextStyle(fontSize: 11, color: _roomGold),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 5,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    key: const Key('send-room-gift'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _roomPink,
                      foregroundColor: Colors.white,
                    ),
                    onPressed:
                        c.busy ||
                            (pending != null &&
                                c.pendingGiftRoom != c.active?.id) ||
                            selected == null ||
                            selectedRecipient == null ||
                            (selectedAudience == 'person' &&
                                !members.any(
                                  (m) => m.user.id == selectedRecipient,
                                )) ||
                            targetCount == 0
                        ? null
                        : () async {
                            final ok = await c.sendGift(
                              pending?['recipientId'] as String? ??
                                  recipient ??
                                  selectedRecipient,
                              pending?['giftId'] as String? ??
                                  gift ??
                                  selected.id,
                              pending?['quantity'] as int? ?? quantity,
                              audience: selectedAudience,
                            );
                            if (ok && context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'وصل الدعم وانضافت الكارزما للمستلمين.',
                                  ),
                                ),
                              );
                          },
                    child: Text(
                      c.busy
                          ? 'إرسال…'
                          : pending != null
                          ? 'إعادة المحاولة'
                          : 'إرسال',
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: count,
                    underline: const SizedBox(),
                    items: [1, 10, 99]
                        .map(
                          (v) => DropdownMenuItem(value: v, child: Text('×$v')),
                        )
                        .toList(),
                    onChanged: pending != null
                        ? null
                        : (v) {
                            if (v != null) setState(() => quantity = v);
                          },
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => _roomWallet(context, c),
                icon: const Icon(
                  Icons.add_circle_outline,
                  size: 17,
                  color: _roomGold,
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${c.coins}',
                      style: const TextStyle(color: _roomGold),
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.monetization_on_rounded,
                      size: 16,
                      color: _roomGold,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'الإجمالي ${selected.price * count * targetCount} كوينز • $targetCount مستلم • العدد حسب الحاضرين وقت الإرسال',
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ),
      ];
      final column = Column(
        mainAxisSize: large ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (final child in children)
            if (large && child is Expanded)
              SizedBox(height: 330, child: child.child)
            else
              child,
        ],
      );
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * (large ? 0.9 : 0.72),
          child: large ? SingleChildScrollView(child: column) : column,
        ),
      );
    },
  );
}

Future<void> _roomWallet(
  BuildContext context,
  VoiceRoomsController c,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 40,
              color: _roomGold,
            ),
            const SizedBox(height: 12),
            Text(
              '${c.coins} عملة',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'رصيد تجريبي للهدايا، بدون شراء أو تحويل لأموال. تحصل على1000 عملة مرة واحدة و500 كل24 ساعة.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.7),
            ),
            if (c.nextClaim != null)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  'المكافأة القادمة: ${_roomDate(c.nextClaim!)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TomiColors.muted),
                ),
              ),
            FilledButton(
              onPressed: c.busy ? null : c.claimCoins,
              child: const Text('استلام المكافأة اليومية'),
            ),
            if (c.notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(c.notice!, textAlign: TextAlign.center),
              ),
            if (c.error != null) AccountErrorMessage(c.error!),
          ],
        ),
      ),
    ),
  ),
);
String _roomDate(String raw) {
  final d = DateTime.tryParse(raw)?.toLocal();
  return d == null
      ? raw
      : '${d.year}/${d.month}/${d.day}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _RoomInfo extends StatelessWidget {
  const _RoomInfo({required this.c});
  final VoiceRoomsController c;
  @override
  Widget build(BuildContext context) => _roomLightSurface(
    AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final r = c.active;
        if (r == null) return const SizedBox.shrink();
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoomTierBadge(r.advanced),
                    if (c.me?.role == 'owner')
                      IconButton(
                        tooltip: 'إعدادات الغرفة',
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RoomSettingsPage(controller: c),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings_outlined),
                      ),
                  ],
                ),
                if (r.advanced)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      children: [
                        Text(
                          'المستوى ${r.level ?? 1} من 10',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xff253d50),
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: r.levelNext == null
                              ? 1
                              : ((r.levelXp - r.levelStart) /
                                        (r.levelNext! - r.levelStart))
                                    .clamp(0.0, 1.0),
                          color: const Color(0xff17bfa9),
                          backgroundColor: const Color(0xffe5edf1),
                          minHeight: 7,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          r.levelNext == null
                              ? 'وصلت الغرفة لأعلى مستوى • الدعم ${r.levelXp}'
                              : 'الدعم الإجمالي ${r.levelXp} / ${r.levelNext} للمستوى التالي',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff536d7c),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (r.advanced && r.expiresAt != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'تحذف بعد 60 يومًا متواصلًا دون دخول المالك. نهاية المهلة الحالية: ${r.expiresAt!.substring(0, 10)}',
                      style: const TextStyle(
                        color: Color(0xff696e7c),
                        fontSize: 12,
                      ),
                    ),
                  ),
                _RoomPicture(r: r, size: 72),
                const SizedBox(height: 14),
                Text(
                  r.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff292c39),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: c.preferenceBusy.contains(r.id)
                          ? null
                          : () => c.setPreference(r, favorite: !r.favorite),
                      icon: Icon(
                        r.favorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                      ),
                      label: Text(r.favorite ? 'بالمفضلة' : 'أضف للمفضلة'),
                    ),
                    TextButton.icon(
                      onPressed: c.preferenceBusy.contains(r.id)
                          ? null
                          : () => c.setPreference(r, following: !r.following),
                      icon: Icon(
                        r.following ? Icons.bookmark : Icons.bookmark_outline,
                      ),
                      label: Text(
                        r.following ? 'أتابع الغرفة' : 'متابعة الغرفة',
                      ),
                    ),
                  ],
                ),
                Text(
                  '${r.followers} متابع',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (r.ownerId != c.accounts.user?.id)
                  TextButton.icon(
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('إبلاغ إدارة التطبيق'),
                    onPressed: () => showReportDialog(
                      context,
                      c.accounts,
                      targetType: 'room',
                      targetId: r.id,
                      title: 'الإبلاغ عن غرفة ${r.title}',
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  r.publicId == null
                      ? 'مجانية • بلا ID عام'
                      : 'ID: ${r.publicId}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 78,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final m in r.members)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: SizedBox(
                            width: 48,
                            child: Column(
                              children: [
                                MediaQuery.withNoTextScaling(
                                  child: AccountAvatar(m.user, size: 40),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  m.user.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff4c5364),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _roomStat(
                        'الأعضاء',
                        '${r.memberCount} / ${r.capacity}',
                        const Color(0xffeaf8f1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _roomStat(
                        'نوع الغرفة',
                        r.advanced ? 'متقدمة' : 'مجانية',
                        const Color(0xfffff4de),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _roomInfoLine('المالك', r.owner?.displayName ?? 'مالك الغرفة'),
                _roomInfoLine('علامة الغرفة', r.category),
                _roomInfoLine('وضع الغرفة', r.mode),
                if (r.announcement.isNotEmpty)
                  _roomInfoLine('إشعار عام', r.announcement),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _showRoomLevels(context, c),
                  icon: const Icon(Icons.leaderboard_outlined),
                  label: const Text('ترتيب الدعم • أعلى 100'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _roomStat(String title, String value, Color color) => Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Column(
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 12, color: Color(0xff889084)),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: Color(0xff656143),
        ),
      ),
    ],
  ),
);
Widget _roomInfoLine(String title, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(width: 20),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(color: Color(0xff535965), fontSize: 12),
        ),
      ),
    ],
  ),
);

Future<void> _showRoomLevels(BuildContext context, VoiceRoomsController c) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ContributionRankingPage(accounts: c.accounts, roomId: c.active!.id),
      ),
    );

class RoomSettingsPage extends StatefulWidget {
  const RoomSettingsPage({super.key, required this.controller});
  final VoiceRoomsController controller;
  @override
  State<RoomSettingsPage> createState() => _RoomSettingsPageState();
}

class _RoomSettingsPageState extends State<RoomSettingsPage> {
  VoiceRoomsController get c => widget.controller;
  bool uploading = false;
  Future<void> edit(
    String title,
    String key,
    String value, {
    int max = 64,
  }) async {
    final result = await _roomText(context, title, value, max: max);
    if (result != null) await c.action('settings', body: {key: result});
  }

  Future<void> choose(String title, String key, List<String> values) async {
    final result = await _roomChoice(context, title, values);
    if (result != null) await c.action('settings', body: {key: result});
  }

  Future<void> chooseMapped(
    String title,
    String key,
    Map<String, String> values,
  ) async {
    final result = await _roomChoice(context, title, values.values.toList());
    if (result != null)
      await c.action(
        'settings',
        body: {key: values.entries.firstWhere((e) => e.value == result).key},
      );
  }

  Future<void> roomImage() async {
    final choice = await _roomChoice(context, 'صورة الغرفة', [
      'اختيار صورة من الهاتف',
      'صورة المالك',
      'سماعات',
      'قمر',
      'تاج',
      'ألعاب',
      'موسيقى',
    ]);
    if (choice == null || !mounted) return;
    if (choice != 'اختيار صورة من الهاتف') {
      final preset = switch (choice) {
        'صورة المالك' => 'owner',
        'قمر' => 'moon',
        'تاج' => 'crown',
        'ألعاب' => 'game',
        'موسيقى' => 'music',
        _ => 'headphones',
      };
      await c.action(
        'settings',
        body: {'picture': preset, 'imageUploadId': null},
      );
      return;
    }
    setState(() => uploading = true);
    try {
      final f = await c.mediaPicker(
        () => ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 88,
        ),
      );
      if (f == null || c.active == null) return;
      final id = await c.uploadRoomImage(await readPickedImage(f));
      if (id != null) await c.action('settings', body: {'imageUploadId': id});
    } on AccountFailure catch (e) {
      c.error = e.message;
      c.notify();
    } catch (_) {
      c.error = 'تعذّر اختيار صورة الغرفة.';
      c.notify();
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> password(bool enable) async {
    if (!enable) {
      await c.action('settings', body: {'password': ''});
      return;
    }
    final result = await _roomText(
      context,
      'كلمة مرور الغرفة',
      '',
      secret: true,
    );
    if (result != null) await c.action('settings', body: {'password': result});
  }

  Future<void> administration(String kind) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => _RoomAdminPage(c: c, kind: kind),
    ),
  );
  Future<void> protectedSeats() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => Theme(
        data: _roomLight(),
        child: AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            final r = c.active;
            return Scaffold(
              appBar: AppBar(title: const Text('مقعد محمي')),
              body: r == null
                  ? const Center(child: Text('غادرت الغرفة.'))
                  : ListView(
                      children: [
                        ListTile(
                          title: const Text('مقعد إدارة الغرفة'),
                          subtitle: Text(
                            r.advanced
                                ? 'محجوز دائمًا للمالك حتى وهو خارج الغرفة.'
                                : 'ينتقل تلقائيًا للمدير الجديد عند مغادرة المدير الحالي.',
                          ),
                          trailing: Icon(
                            Icons.lock_rounded,
                            color: Color(0xff12c2cf),
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('مقعد مميز عادي'),
                          subtitle: const Text(
                            'الدخول إليه بدعوة وموافقة العضو.',
                          ),
                          value: r.companionEnabled,
                          onChanged: c.busy
                              ? null
                              : (v) => c.action(
                                  'settings',
                                  body: {'companionEnabled': v},
                                ),
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    ),
  );
  Future<void> closeRoom() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('إغلاق الغرفة نهائيًا؟'),
        content: const Text(
          'يغادر الجميع وتُحذف الغرفة من القائمة. سجلات الدعم محفوظة ولا يوجد مستوى للغرف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await c.action('close');
      if (c.active == null && mounted) Navigator.pop(context);
    }
  }

  Widget row(String title, String value, VoidCallback? tap, {Widget? icon}) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: null,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 145),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child:
                    icon ??
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xff9d9eaa),
                      ),
                    ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_left_rounded,
                textDirection: TextDirection.ltr,
                size: 20,
                color: Color(0xffa3a6ae),
              ),
            ],
          ),
        ),
        onTap: c.busy || uploading ? null : tap,
      );
  Widget section() =>
      const SizedBox(height: 10, child: ColoredBox(color: Color(0xfff7f8fa)));
  @override
  Widget build(BuildContext context) => Theme(
    data: _roomLight(),
    child: AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final r = c.active, owner = c.me?.role == 'owner';
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'إعدادات الغرفة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          body: r == null
              ? const Center(child: Text('غادرت الغرفة.'))
              : !owner
              ? const Center(child: Text('إعدادات الغرفة للمالك فقط.'))
              : ListView(
                  children: [
                    if (c.busy || uploading)
                      const LinearProgressIndicator(minHeight: 2),
                    if (c.error != null)
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text(
                          c.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    row(
                      'اسم الغرفة',
                      r.title,
                      () => edit('اسم الغرفة', 'title', r.title, max: 60),
                    ),
                    row(
                      'صورة الغرفة',
                      '',
                      roomImage,
                      icon: _RoomPicture(r: r, size: 35),
                    ),
                    row(
                      'إشعار عام',
                      r.announcement.isEmpty
                          ? 'اكتب ترحيبًا للزوار'
                          : r.announcement,
                      () => edit(
                        'إشعار عام',
                        'announcement',
                        r.announcement,
                        max: 300,
                      ),
                    ),
                    row(
                      'وضع الغرفة',
                      r.mode,
                      () => choose('وضع الغرفة', 'mode', [
                        'عادي',
                        'تعارف',
                        'احتفال',
                      ]),
                    ),
                    row(
                      'علامة الغرفة',
                      r.category,
                      () => choose('علامة الغرفة', 'category', [
                        'الأصدقاء',
                        'الموسيقى',
                        'الألعاب',
                        'عيد ميلاد',
                        'المكالمات',
                      ]),
                    ),
                    row(
                      'خلفية الغرفة',
                      _backgrounds[r.background] ?? 'المحيط',
                      () => chooseMapped(
                        'خلفية الغرفة',
                        'background',
                        _backgrounds,
                      ),
                    ),
                    row(
                      'ثيم الغرفة',
                      _themes[r.theme] ?? 'ذهبي',
                      () => chooseMapped('ثيم الغرفة', 'theme', _themes),
                    ),
                    section(),
                    row('مقعد محمي', 'مقعد المالك ثابت', protectedSeats),
                    section(),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      title: const Text(
                        'صوت عالي الجودة',
                        style: TextStyle(fontSize: 15),
                      ),
                      subtitle: const Text(
                        'جودة المايك فقط، لا يشارك صوت التطبيقات. يسري بعد إعادة الدخول.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: r.highQuality,
                      onChanged: c.busy
                          ? null
                          : (v) =>
                                c.action('settings', body: {'highQuality': v}),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      title: const Text(
                        'تعطيل الدردشة العامة',
                        style: TextStyle(fontSize: 15),
                      ),
                      value: r.chatDisabled,
                      onChanged: c.busy
                          ? null
                          : (v) =>
                                c.action('settings', body: {'chatDisabled': v}),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      title: const Text(
                        'تعطيل إرسال الصور',
                        style: TextStyle(fontSize: 15),
                      ),
                      value: r.imagesDisabled,
                      onChanged: c.busy
                          ? null
                          : (v) => c.action(
                              'settings',
                              body: {'imagesDisabled': v},
                            ),
                    ),
                    section(),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      title: const Text(
                        'كلمة مرور الغرفة',
                        style: TextStyle(fontSize: 15),
                      ),
                      value: r.passwordRequired,
                      onChanged: c.busy ? null : password,
                    ),
                    if (r.passwordRequired)
                      row('تغيير كلمة المرور', '', () => password(true)),
                    section(),
                    if (r.advanced)
                      row(
                        'مشرفو الغرفة',
                        '',
                        () => administration('moderators'),
                      ),
                    row(
                      'القائمة السوداء',
                      '',
                      () => administration('blacklist'),
                    ),
                    row('سجل العمليات', '', () => administration('audit')),
                    section(),
                    if (r.publicId != null)
                      row('رقم الغرفة', r.publicId!, () async {
                        await Clipboard.setData(
                          ClipboardData(text: r.publicId!),
                        );
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ رقم الغرفة الكامل.'),
                            ),
                          );
                      }),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: c.busy ? null : closeRoom,
                        icon: const Icon(Icons.power_settings_new_rounded),
                        label: const Text('إغلاق الغرفة نهائيًا'),
                      ),
                    ),
                  ],
                ),
        );
      },
    ),
  );
}

const _backgrounds = {
  'ocean': 'المحيط',
  'dusk': 'الغروب البنفسجي',
  'forest': 'الغابة',
  'midnight': 'منتصف الليل',
};
const _themes = {'gold': 'ذهبي', 'rose': 'وردي', 'ice': 'ثلجي'};

class _RoomAdminPage extends StatefulWidget {
  const _RoomAdminPage({required this.c, required this.kind});
  final VoiceRoomsController c;
  final String kind;
  @override
  State<_RoomAdminPage> createState() => _RoomAdminPageState();
}

class _RoomAdminPageState extends State<_RoomAdminPage> {
  Map<String, dynamic>? data;
  bool loading = false;
  VoiceRoomsController get c => widget.c;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(load());
    });
  }

  Future<void> load() async {
    setState(() => loading = true);
    final d = await c.roomData('administration');
    if (mounted)
      setState(() {
        data = d;
        loading = false;
      });
  }

  Future<void> action(String target, String operation) async {
    if (await c.action(
      'administration',
      body: {'targetId': target, 'operation': operation},
    ))
      await load();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: _roomLight(),
    child: AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final kind = widget.kind,
            title = switch (kind) {
              'moderators' => 'مشرفو الغرفة',
              'blacklist' => 'القائمة السوداء',
              _ => 'سجل العمليات',
            },
            items = (data?['members'] as List? ?? [])
                .where(
                  (v) => kind == 'blacklist'
                      ? v['state'] == 'kicked'
                      : v['role'] == 'moderator' && v['state'] != 'kicked',
                )
                .toList(),
            audit = data?['audit'] as List? ?? [];
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: c.active == null
              ? const Center(child: Text('غادرت الغرفة.'))
              : ListView(
                  children: [
                    if (loading) const LinearProgressIndicator(),
                    if (c.error != null)
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Text(
                          c.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (kind == 'audit') ...[
                      for (final entry in audit)
                        ListTile(
                          title: Text(_auditLabel(entry['action'] as String)),
                          subtitle: Text(
                            '${entry['actor']['displayName']} • ${_roomDate(entry['createdAt'] as String)}\n${_auditDetail(entry['detail'] as String)}',
                          ),
                        ),
                      if (audit.isEmpty && !loading)
                        const ListTile(title: Text('بعد ماكو عمليات مسجلة.')),
                    ] else ...[
                      for (final item in items)
                        ListTile(
                          leading: MediaQuery.withNoTextScaling(
                            child: AccountAvatar(
                              AccountUser.fromJson(
                                item['user'] as Map<String, dynamic>,
                              ),
                              size: 40,
                            ),
                          ),
                          title: Text(item['user']['displayName'] as String),
                          subtitle: Text(
                            kind == 'blacklist'
                                ? 'ممنوع من دخول الغرفة'
                                : 'مشرف',
                          ),
                          trailing: TextButton(
                            onPressed: c.busy
                                ? null
                                : () => action(
                                    item['user']['id'] as String,
                                    kind == 'blacklist'
                                        ? 'unban'
                                        : 'revoke-mod',
                                  ),
                            child: Text(
                              kind == 'blacklist'
                                  ? 'السماح بالرجوع'
                                  : 'إلغاء الإشراف',
                            ),
                          ),
                        ),
                      if (items.isEmpty && !loading)
                        ListTile(
                          title: Text(
                            kind == 'blacklist'
                                ? 'القائمة السوداء فارغة.'
                                : 'ماكو مشرفين حاليًا.',
                          ),
                        ),
                      if (kind == 'moderators') ...[
                        const Divider(),
                        const ListTile(
                          title: Text('تعيين مشرف من الأعضاء الحاليين'),
                        ),
                        for (final member in c.active!.members.where(
                          (m) => m.role == 'member',
                        ))
                          ListTile(
                            leading: MediaQuery.withNoTextScaling(
                              child: AccountAvatar(member.user, size: 38),
                            ),
                            title: Text(member.user.displayName),
                            trailing: IconButton(
                              tooltip: 'تعيين مشرف',
                              onPressed: c.busy
                                  ? null
                                  : () async {
                                      if (await c.moderate(member, 'promote'))
                                        await load();
                                    },
                              icon: const Icon(Icons.add_moderator_outlined),
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
        );
      },
    ),
  );
}

String _auditLabel(String action) => switch (action) {
  'settings' => 'تحديث إعدادات الغرفة',
  'lock' => 'قفل مقعد',
  'unlock' => 'فتح مقعد',
  'mute' => 'كتم المايك',
  'allow' => 'إلغاء كتم المقعد',
  'allow-mic' => 'السماح بالمايك',
  'approve' => 'قبول طلب المايك',
  'reject' => 'رفض طلب المايك',
  'lower' => 'إنزال من المايك',
  'promote' => 'تعيين مشرف',
  'demote' => 'إلغاء الإشراف',
  'revoke-mod' => 'إلغاء إشراف عضو',
  'kick' => 'إزالة عضو',
  'unban' => 'السماح بالرجوع',
  'invite' => 'دعوة للمايك',
  _ => 'تحديث الغرفة',
};
String _auditDetail(String detail) {
  const labels = {
    'title': 'اسم الغرفة',
    'announcement': 'الإشعار',
    'background': 'الخلفية',
    'theme': 'الثيم',
    'picture': 'الصورة',
    'imageUploadId': 'الصورة',
    'mode': 'الوضع',
    'category': 'العلامة',
    'password': 'كلمة المرور',
    'highQuality': 'جودة الصوت',
    'companionEnabled': 'المقعد المميز',
    'chatDisabled': 'الدردشة',
    'imagesDisabled': 'الصور',
  };
  if (RegExp(r'^[a-f0-9-]{36}$').hasMatch(detail)) return '';
  return detail.split('، ').map((k) => labels[k] ?? k).join('، ');
}
