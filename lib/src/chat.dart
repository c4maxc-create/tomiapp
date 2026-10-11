import 'package:flutter/material.dart';

import 'model.dart';
import 'widgets.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key, required this.store});
  final TomiStore store;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('chats-scroll'),
    padding: const EdgeInsets.all(18), children: [
      const SectionHeading('المحادثات', subtitle: 'سوالفك، كلّها قريبة منك'),
      const Padding(padding: EdgeInsets.only(bottom: 18), child: TinyLabel('محادثات تجريبية')),
      for (final chat in store.chats) Padding(padding: const EdgeInsets.only(bottom: 12),
        child: TomiCard(padding: EdgeInsets.zero, child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: Avatar(chat.name, size: 52),
          title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(
            chat.messages.isEmpty ? 'ابدأ المحادثة' : chat.messages.last.text,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: TomiColors.muted),
          )),
          trailing: chat.unread > 0 ? Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: TomiColors.accent, shape: BoxShape.circle),
            child: Text('${chat.unread}', style: const TextStyle(color: TomiColors.background)),
          ) : const Icon(Icons.chevron_left_rounded, color: TomiColors.muted),
          onTap: () {
            store.markRead(chat);
            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChatPage(store: store, chat: chat)));
          },
        ))),
      const SizedBox(height: 10),
      const TomiCard(child: Row(children: [
        Icon(Icons.groups_outlined, color: TomiColors.accent), SizedBox(width: 12),
        Expanded(child: Text('الخاص والكروبات في مكان واحد.', style: TextStyle(color: TomiColors.muted))),
      ])),
    ],
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.store, required this.chat});
  final TomiStore store;
  final DemoChat chat;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();

  @override
  void dispose() {
    input.dispose(); scroll.dispose(); super.dispose();
  }

  void send() {
    if (input.text.trim().isEmpty) return;
    widget.store.sendMessage(widget.chat, input.text);
    input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(titleSpacing: 0,
        title: Row(children: [Avatar(widget.chat.name, size: 32), const SizedBox(width: 8),
          Expanded(child: Text(widget.chat.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ]), actions: [
          IconButton(tooltip: 'معاينة اتصال صوتي', icon: const Icon(Icons.call_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => CallPreviewPage(name: widget.chat.name, video: false)))),
          IconButton(tooltip: 'معاينة اتصال فيديو', icon: const Icon(Icons.videocam_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => CallPreviewPage(name: widget.chat.name, video: true)))),
        ]),
      body: SafeArea(child: Column(children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
          child: TinyLabel('معاينة محلية • الرسائل لا تُرسل إلى أشخاص')),
        Expanded(child: ListView.builder(controller: scroll,
          padding: const EdgeInsets.all(16), itemCount: widget.chat.messages.length,
          itemBuilder: (context, index) {
            final message = widget.chat.messages[index];
            return Align(alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: message.mine ? const Color(0xFF4C3B70) : TomiColors.surface,
                  borderRadius: BorderRadius.circular(20)),
                child: Text(message.text, style: const TextStyle(height: 1.6)),
              ));
          })),
        Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 12), child: Row(children: [
          IconButton(tooltip: 'الوسائط', icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => showInfo(context, 'وسائط المحادثة',
              'الصور والفيديو والتسجيلات الصوتية تُضاف في مرحلة الوسائط.\nتقدر الآن تجرّب كتابة الرسائل ومظهر المحادثة.')),
          Expanded(child: TextField(key: const Key('message-input'), controller: input,
            minLines: 1, maxLines: 4, textInputAction: TextInputAction.send,
            onSubmitted: (_) => send(),
            decoration: const InputDecoration(hintText: 'اكتب رسالتك...'))),
          const SizedBox(width: 8),
          IconButton.filled(key: const Key('send-message'), tooltip: 'إرسال',
            onPressed: send, icon: const Icon(Icons.send_rounded)),
        ])),
      ])),
    ));
}

class CallPreviewPage extends StatefulWidget {
  const CallPreviewPage({super.key, required this.name, required this.video});
  final String name;
  final bool video;

  @override
  State<CallPreviewPage> createState() => _CallPreviewPageState();
}

class _CallPreviewPageState extends State<CallPreviewPage> {
  bool muted = false;
  bool camera = true;
  bool speaker = true;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.video ? 'معاينة اتصال فيديو' : 'معاينة اتصال صوتي')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 20),
      const Center(child: TinyLabel('واجهة تجريبية • لا توجد مكالمة نشطة')),
      const SizedBox(height: 34),
      Center(child: Avatar(widget.name, size: 116, highlight: true)),
      const SizedBox(height: 20),
      Text(widget.name, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      const Text('جرّب ترتيب أزرار الاتصال', textAlign: TextAlign.center,
        style: TextStyle(color: TomiColors.muted)),
      if (widget.video) ...[
        const SizedBox(height: 26),
        TomiCard(child: Column(children: [
          Icon(camera ? Icons.videocam_outlined : Icons.videocam_off_outlined,
            size: 64, color: TomiColors.accent),
          const SizedBox(height: 12),
          Text(camera ? 'مساحة الفيديو • بدون تشغيل الكاميرا' : 'الكاميرا متوقفة في المعاينة', textAlign: TextAlign.center),
        ])),
      ],
      const SizedBox(height: 34),
      Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 14, children: [
        IconButton.filledTonal(tooltip: 'الميكروفون في المعاينة',
          onPressed: () => setState(() => muted = !muted),
          icon: Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded)),
        if (widget.video) IconButton.filledTonal(tooltip: 'الكاميرا في المعاينة',
          onPressed: () => setState(() => camera = !camera),
          icon: Icon(camera ? Icons.videocam_rounded : Icons.videocam_off_rounded)),
        IconButton.filledTonal(tooltip: 'السماعة في المعاينة',
          onPressed: () => setState(() => speaker = !speaker),
          icon: Icon(speaker ? Icons.volume_up_rounded : Icons.volume_off_rounded)),
        IconButton.filled(tooltip: 'إغلاق المعاينة', style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFC9546B), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context), icon: const Icon(Icons.call_end_rounded)),
      ]),
    ])),
  );
}
