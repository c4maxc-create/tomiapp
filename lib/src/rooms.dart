import 'package:flutter/material.dart';

import 'model.dart';
import 'profile.dart';
import 'widgets.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key, required this.store});
  final TomiStore store;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  String filter = 'الكل';

  @override
  Widget build(BuildContext context) {
    final rooms = TomiStore.rooms.where((room) => filter == 'الكل' ||
      (filter == 'ألعاب' && room.topic.contains('ألعاب')) ||
      (filter == 'سوالف' && !room.topic.contains('ألعاب')));
    return ListView(key: const PageStorageKey('rooms-scroll'),
      padding: const EdgeInsets.all(18), children: [
        const SectionHeading('الغرف الصوتية', subtitle: 'جمعتكم أحلى مع تومي'),
        Wrap(spacing: 8, children: [
          for (final value in ['الكل', 'سوالف', 'ألعاب']) ChoiceChip(label: Text(value),
            selected: filter == value, onSelected: (_) => setState(() => filter = value)),
        ]),
        const SizedBox(height: 20),
        for (final room in rooms) Padding(padding: const EdgeInsets.only(bottom: 14),
          child: InkWell(borderRadius: BorderRadius.circular(24),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => RoomPage(store: widget.store, room: room))),
            child: TomiCard(child: Row(children: [
              Container(width: 70, height: 80, alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [Color(0xFF5C437F), Color(0xFF35334F)])),
                child: Text(room.symbol, style: const TextStyle(fontSize: 31))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(room.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(room.topic, style: const TextStyle(color: TomiColors.muted, fontSize: 12)),
                const SizedBox(height: 10),
                TinyLabel('${room.people} في المعاينة'),
              ])),
              const Icon(Icons.chevron_left_rounded, color: TomiColors.accent),
            ]))),
        ),
      ]);
  }
}

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.store, required this.room});
  final TomiStore store;
  final DemoRoom room;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  bool muted = true;
  final input = TextEditingController();
  final messages = <String>['علي: أهلًا بيكم 💜', 'فاطمة: منو جاهز للأسئلة؟'];

  @override
  void dispose() { input.dispose(); super.dispose(); }

  void send() {
    if (input.text.trim().isEmpty) return;
    setState(() => messages.add('${widget.store.displayName}: ${input.text.trim()}'));
    input.clear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.room.title), actions: [
      IconButton(tooltip: 'معلومات الغرفة', icon: const Icon(Icons.info_outline_rounded),
        onPressed: () => showInfo(context, 'الغرفة التجريبية',
          'هذه معاينة المقاعد والدردشة والهدايا.\nالميكروفون لا يسجّل صوتًا، ولا يوجد أشخاص متصلون فعليًا.')),
    ]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Align(alignment: Alignment.centerRight, child: TinyLabel('معاينة • بدون بث صوتي')),
      const SizedBox(height: 16),
      TomiCard(child: GridView.builder(shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(), itemCount: 8,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisExtent: 112, crossAxisSpacing: 6, mainAxisSpacing: 8),
        itemBuilder: (context, index) {
          final names = [widget.store.displayName, 'علي', 'فاطمة', 'محمد'];
          return Column(children: [
            if (index < 4) Avatar(names[index], size: 48, highlight: index == 0)
            else Container(width: 48, height: 48,
              decoration: const BoxDecoration(color: TomiColors.raised, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, color: TomiColors.muted)),
            const SizedBox(height: 6),
            Text(index < 4 ? names[index] : 'مقعد فارغ', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: TomiColors.muted)),
            const SizedBox(height: 3),
            Icon(index == 0 && !muted ? Icons.mic_rounded : Icons.mic_off_rounded,
              size: 13, color: TomiColors.muted),
          ]);
        })),
      const SizedBox(height: 18),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.tonalIcon(onPressed: () => setState(() => muted = !muted),
          icon: Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded),
          label: Text(muted ? 'فتح المايك • معاينة' : 'كتم المايك • معاينة')),
        FilledButton.tonalIcon(onPressed: () => showGifts(context, widget.store),
          icon: const Icon(Icons.card_giftcard_rounded), label: const Text('هدايا')),
      ]),
      const SizedBox(height: 22),
      const SectionHeading('دردشة الغرفة'),
      for (final message in messages) Padding(padding: const EdgeInsets.only(bottom: 10),
        child: TomiCard(padding: const EdgeInsets.all(13), child: Text(message))),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: TextField(controller: input, onSubmitted: (_) => send(),
          decoration: const InputDecoration(hintText: 'شاركنا سوالفك...'))),
        const SizedBox(width: 8),
        IconButton.filled(tooltip: 'إرسال', onPressed: send, icon: const Icon(Icons.send_rounded)),
      ]),
    ])),
  );
}
