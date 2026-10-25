part of 'room_screens.dart';

Future<void> _showRoomShop(BuildContext context, VoiceRoomsController c) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => Theme(
        data: _roomLight(),
        child: Material(
          color: Colors.white,
          child: _RoomShop(c: c),
        ),
      ),
    );

class _RoomShop extends StatefulWidget {
  const _RoomShop({required this.c});
  final VoiceRoomsController c;
  @override
  State<_RoomShop> createState() => _RoomShopState();
}

class _RoomShopState extends State<_RoomShop> {
  Map<String, dynamic>? data;
  bool busy = false;
  String? error;
  Map<String, dynamic>? get pending => widget.c.pendingCosmetic;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(load());
    });
  }

  Future<void> load() async {
    try {
      if (!widget.c.commerceReady)
        await widget.c.restoreSavedRooms(widget.c.generation);
      await widget.c.loadGifts();
      final d = await widget.c.request('GET', '/v1/rooms/shop');
      if (mounted) setState(() => data = d);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحميل المتجر.');
    }
  }

  Future<void> buy(Map<String, dynamic> item) async {
    if (busy) return;
    final yes =
        pending != null ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(item['name'] as String),
                content: Text(
                  'السعر ${item['price']} كوينز لمدة ${item['days']} يومًا. يبدأ الوقت عند الشراء، ويتوقف التأثير عند انتهائه. الشراء مرة أخرى يمدد المدة.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('رجوع'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('شراء وتفعيل'),
                  ),
                ],
              ),
            ) ==
            true;
    if (!yes || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await widget.c.purchaseCosmetic(item);
      if (!ok && mounted) setState(() => error = widget.c.error);
      await load();
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'الشراء محفوظ؛ أعد المحاولة للتحقق بدون خصم جديد.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> equip(Map<String, dynamic> item, bool active) async {
    setState(() => busy = true);
    try {
      await widget.c.request(
        'PUT',
        '/v1/rooms/shop/equip',
        body: {'kind': item['kind'], 'styleId': active ? 'none' : item['id']},
      );
      await widget.c.tick();
      await load();
    } on AccountFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تفعيل العنصر.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (data?['items'] as List? ?? []).cast<Map<String, dynamic>>(),
        owned = (data?['owned'] as List? ?? []).cast<Map<String, dynamic>>();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Color(0xffc59b35)),
              title: const Text('متجر الإطارات وتأثيرات الدخول'),
              subtitle: Text('رصيدك ${widget.c.coins} كوينز • عناصر مؤقتة'),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            if (data == null)
              TextButton(onPressed: load, child: const Text('تحميل المتجر')),
            Expanded(
              child: ListView(
                children: [
                  for (final item in items)
                    Builder(
                      builder: (context) {
                        final entitlement = owned
                                .where(
                                  (x) =>
                                      x['kind'] == item['kind'] &&
                                      x['style_id'] == item['id'],
                                )
                                .firstOrNull,
                            active = entitlement?['equipped'] == 1;
                        final until = DateTime.tryParse(
                          entitlement?['expires_at'] as String? ?? '',
                        )?.toLocal();
                        return ListTile(
                          leading: Text(
                            item['kind'] == 'frame' ? '💠' : '🔥',
                            style: const TextStyle(fontSize: 30),
                          ),
                          title: Text(item['name'] as String),
                          onTap: entitlement == null || busy
                              ? null
                              : () => equip(item, active),
                          subtitle: Text(
                            '${item['price']} كوينز • ${item['days']} أيام${entitlement == null
                                ? ''
                                : active
                                ? ' • مفعّل (اضغط لإيقافه)'
                                : ' • اضغط لتفعيله'}${until == null ? '' : '\nينتهي: ${until.year}/${until.month}/${until.day} ${until.hour}:${until.minute.toString().padLeft(2, '0')}'}',
                          ),
                          trailing: FilledButton.tonal(
                            onPressed:
                                busy ||
                                    (pending != null &&
                                        (pending!['kind'] != item['kind'] ||
                                            pending!['styleId'] != item['id']))
                                ? null
                                : () => buy(item),
                            child: Text(
                              pending != null
                                  ? 'إعادة المحاولة'
                                  : entitlement != null
                                  ? 'تمديد'
                                  : 'شراء',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'الإطار حول الصورة الشخصية فقط. الغلاف لا يتغيّر. الكوينز حاليًا تجريبية وليست دفعًا نقديًا.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
