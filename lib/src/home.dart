import 'package:flutter/material.dart';

import 'model.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});
  final TomiStore store;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('home-scroll'),
    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
    children: [
      SectionHeading('لحظاتك أقرب', subtitle: 'شارك، دردش، واستمتع بوقتك',
        action: IconButton.filledTonal(key: const Key('compose-post'),
          tooltip: 'نشر نص', icon: const Icon(Icons.add_rounded),
          onPressed: () => composeText(context, store))),
      SizedBox(height: 114, child: ListView(scrollDirection: Axis.horizontal, children: [
        StoryCircle(name: 'قصتك', add: true,
          onTap: () => store.myStories.isEmpty
            ? composeText(context, store, story: true)
            : Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StoryPage(
                name: store.displayName, text: store.myStories.first,
                onAdd: () => composeText(context, store, story: true)))),
        ),
        for (final name in ['علي', 'فاطمة', 'محمد', 'TOMI']) StoryCircle(name: name,
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StoryPage(
            name: name, text: 'لحظة حلوة، وأصدقاء أجمل 💜\nمعاينة ستوري TOMI',
          )))),
      ])),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFF403162), Color(0xFF25233F)])),
        child: const Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('كلّنا بمكان واحد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('لحظات، سوالف، ولعب يجمعنا.', style: TextStyle(color: Color(0xFFD6C9ED))),
          ])),
          SizedBox(width: 12),
          Icon(Icons.auto_awesome_rounded, size: 38, color: TomiColors.gold),
        ]),
      ),
      const SizedBox(height: 22),
      const SectionHeading('لك', subtitle: 'منشورات المجتمع'),
      for (final post in store.posts) Padding(
        padding: const EdgeInsets.only(bottom: 16), child: PostCard(store: store, post: post)),
    ],
  );
}

class StoryCircle extends StatelessWidget {
  const StoryCircle({super.key, required this.name, required this.onTap, this.add = false});
  final String name;
  final VoidCallback onTap;
  final bool add;

  @override
  Widget build(BuildContext context) => SizedBox(width: 78, child: InkWell(
    borderRadius: BorderRadius.circular(20), onTap: onTap,
    child: Column(children: [
      Stack(children: [
        Avatar(name, size: 64, highlight: !add),
        if (add) Positioned(bottom: 0, left: 0, child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(color: TomiColors.accent, shape: BoxShape.circle),
          child: const Icon(Icons.add_rounded, color: TomiColors.background, size: 18),
        )),
      ]),
      const SizedBox(height: 8),
      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: TomiColors.muted)),
    ]),
  ));
}

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.store, required this.post});
  final TomiStore store;
  final DemoPost post;

  @override
  Widget build(BuildContext context) => TomiCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Avatar(post.isMine ? store.displayName : post.name), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(post.isMine ? store.displayName : post.name, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold))),
            if (post.verified) ...[
              const SizedBox(width: 5),
              const Icon(Icons.verified_rounded, size: 16, color: TomiColors.accent),
            ],
          ]),
          Text('@${post.isMine ? store.username : post.username}', textDirection: TextDirection.ltr,
            style: const TextStyle(color: TomiColors.muted, fontSize: 12)),
        ])),
        if (!post.isMine && post.username != store.username)
          TextButton(onPressed: () => store.toggleFollow(post.username),
            child: Text(store.following.contains(post.username) ? 'متابَع' : 'متابعة')),
      ]),
      const SizedBox(height: 14),
      Text(post.text, style: const TextStyle(height: 1.7, fontSize: 15)),
      if (post.kind != 'text') ...[
        const SizedBox(height: 15),
        InkWell(borderRadius: BorderRadius.circular(20),
          onTap: () => showInfo(context, 'معاينة الوسائط',
            'هذا تصميم بطاقة ${post.kind == 'video' ? 'فيديو' : 'صورة'}.\nنشر وتشغيل ملفات الصور والفيديو يُضافان في مرحلة الوسائط.'),
          child: LandscapeArt(video: post.kind == 'video')),
      ],
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 5, children: [
          TextButton.icon(key: Key('like-${post.id}'),
            onPressed: () => store.toggleLike(post),
            icon: Icon(post.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: post.liked ? TomiColors.pink : TomiColors.muted, size: 21),
            label: Text('${post.likes}', style: const TextStyle(color: TomiColors.text))),
          TextButton.icon(onPressed: () => showComments(context, store, post),
            icon: const Icon(Icons.mode_comment_outlined, size: 20, color: TomiColors.muted),
            label: Text('${post.comments.length}', style: const TextStyle(color: TomiColors.text))),
          IconButton(tooltip: 'حفظ المنشور', onPressed: () => store.toggleSave(post),
            icon: Icon(post.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: post.saved ? TomiColors.accent : TomiColors.muted)),
        ]),
    ],
  ));
}

Future<void> composeText(BuildContext context, TomiStore store, {bool story = false}) {
  return showModalBottomSheet<void>(context: context, isScrollControlled: true,
    showDragHandle: true, builder: (_) => ComposeSheet(store: store, story: story));
}

class ComposeSheet extends StatefulWidget {
  const ComposeSheet({super.key, required this.store, required this.story});
  final TomiStore store;
  final bool story;

  @override
  State<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<ComposeSheet> {
  final controller = TextEditingController();

  @override
  void dispose() { controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.story ? 'ستوري نصية' : 'نشر نص',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('نشر تجريبي داخل جلسة التطبيق.', style: TextStyle(color: TomiColors.muted)),
          const SizedBox(height: 18),
          TextField(key: const Key('post-input'), controller: controller,
            minLines: 3, maxLines: 6, maxLength: 500,
            decoration: const InputDecoration(hintText: 'شنو تحب تشارك اليوم؟')),
          const SizedBox(height: 12),
          FilledButton.icon(key: const Key('publish-post'),
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              if (widget.story) { widget.store.addStory(controller.text); }
              else { widget.store.addPost(controller.text); }
              showNote(context, widget.story ? 'تمت إضافة الستوري التجريبية' : 'تم نشر النص التجريبي');
              Navigator.pop(context);
            }, icon: const Icon(Icons.send_rounded), label: const Text('نشر')),
        ],
      )),
    );
}

Future<void> showComments(BuildContext context, TomiStore store, DemoPost post) {
  return showModalBottomSheet<void>(context: context, isScrollControlled: true,
    showDragHandle: true, builder: (_) => CommentsSheet(store: store, post: post));
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.store, required this.post});
  final TomiStore store;
  final DemoPost post;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final controller = TextEditingController();

  @override
  void dispose() { controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.store,
      builder: (context, _) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('التعليقات', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .35),
            child: SingleChildScrollView(child: Column(children: [
              if (widget.post.comments.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('كن أول من يعلّق 💜')),
              for (final comment in widget.post.comments) ListTile(
                leading: Avatar(widget.store.displayName, size: 36),
                title: Text(comment), subtitle: Text(widget.store.displayName)),
            ]))),
          Row(children: [
            Expanded(child: TextField(controller: controller,
              decoration: const InputDecoration(hintText: 'اكتب تعليقك'))),
            IconButton.filled(onPressed: () {
              widget.store.addComment(widget.post, controller.text); controller.clear();
            }, icon: const Icon(Icons.send_rounded)),
          ]),
        ]),
      ));
}

class StoryPage extends StatelessWidget {
  const StoryPage({super.key, required this.name, required this.text, this.onAdd});
  final String name;
  final String text;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name), actions: [
      if (onAdd != null) IconButton(tooltip: 'ستوري جديدة', onPressed: onAdd, icon: const Icon(Icons.add)),
    ]),
    body: Padding(padding: const EdgeInsets.all(18), child: Container(
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [Color(0xFF655095), Color(0xFF2C264C), Color(0xFF252E51)])),
      child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child:
        Text(text, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 27, height: 1.7, fontWeight: FontWeight.w700)))),
    )),
  );
}
