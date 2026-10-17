import 'package:flutter/material.dart';

import 'model.dart';
import 'widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.store});
  final TomiStore store;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('profile-scroll'),
    padding: const EdgeInsets.all(18),
    children: [
      SectionHeading(
        'حسابي',
        subtitle: 'قصتك تبدأ من هنا',
        action: IconButton(
          tooltip: 'معلومات النسخة',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => showInfo(
            context,
            'TOMI • معاينة 0.1',
            'نسخة لتجربة التصميم والتنقل.\nالرسائل والمنشورات والأرصدة تجريبية، وتُعاد عند إغلاق التطبيق.\nلا يوجد تسجيل حساب حقيقي أو دفع أو اتصال فعلي في هذه النسخة.',
          ),
        ),
      ),
      TomiCard(
        child: Column(
          children: [
            Avatar(store.displayName, size: 90, highlight: true),
            const SizedBox(height: 14),
            Text(
              store.displayName,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '@${store.username}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: TomiColors.muted),
            ),
            const SizedBox(height: 10),
            Text(
              store.bio,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _stat(
                  '${store.posts.where((post) => post.isMine).length}',
                  'منشوراتك',
                ),
                _stat('148', 'متابعون • تجريبي'),
                _stat('${store.following.length}', 'تتابعهم'),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EditProfilePage(store: store),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل الملف الشخصي'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      TomiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: TomiColors.gold,
                ),
                const SizedBox(width: 10),
                Text(
                  'المستوى ${store.level}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                const TinyLabel('XP'),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: store.levelProgress,
                minHeight: 8,
                color: TomiColors.accent,
                backgroundColor: TomiColors.raised,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${store.xp % 100} / 100 للمستوى التالي • جرّب تحدّي الأسئلة',
              style: const TextStyle(color: TomiColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _balance(
            context,
            'عملة تومي',
            '${store.coins}',
            Icons.toll_rounded,
            TomiColors.gold,
            () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => WalletPage(store: store)),
            ),
          ),
          _balance(
            context,
            'الكاريزما',
            '${store.charisma}',
            Icons.auto_awesome_rounded,
            TomiColors.pink,
            () => showGifts(context, store),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const SectionHeading('منشوراتك'),
      if (!store.posts.any((post) => post.isMine))
        const TomiCard(
          child: Text(
            'ابدأ بنشر نص من زر + في الرئيسية 💜',
            style: TextStyle(color: TomiColors.muted),
          ),
        ),
      for (final post in store.posts.where((post) => post.isMine))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TomiCard(child: Text(post.text)),
        ),
      const SizedBox(height: 18),
      const Center(child: TinyLabel('كل الأرصدة والأعداد تجريبية')),
    ],
  );

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: TomiColors.muted),
        ),
      ],
    ),
  );

  Widget _balance(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final width = (MediaQuery.sizeOf(context).width - 48) / 2;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: TomiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: TomiColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletPage extends StatelessWidget {
  const WalletPage({super.key, required this.store});
  final TomiStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('محفظة TOMI')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: TinyLabel('رصيد تجريبي • بلا قيمة مالية'),
          ),
          const SizedBox(height: 20),
          TomiCard(
            child: Column(
              children: [
                const Icon(
                  Icons.toll_rounded,
                  color: TomiColors.gold,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  '${store.coins}',
                  style: const TextStyle(
                    fontSize: 42,
                    color: TomiColors.gold,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'عملة TOMI',
                  style: TextStyle(color: TomiColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              store.addDemoCoins();
              showNote(context, 'أضفنا 1000 عملة تجريبية');
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة 1000 للتجربة'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => showGifts(context, store),
            icon: const Icon(Icons.card_giftcard_rounded),
            label: const Text('تجربة الهدايا'),
          ),
          const SizedBox(height: 20),
          const FeaturePlaceholder(
            icon: Icons.payments_outlined,
            title: 'الشحن الحقيقي',
            body:
                'شراء عملة تومي بالفلوس الحقيقية غير مفعّل في نسخة التصميم.\nالإضافة أعلاه للتجربة فقط، ولا تستخدم أي وسيلة دفع.',
          ),
        ],
      ),
    ),
  );
}

Future<void> showGifts(BuildContext context, TomiStore store) {
  String recipient = 'نفسي';
  final gifts = [
    ('نجمة', '⭐', 100, 10),
    ('قلب', '💜', 500, 50),
    ('تاج', '👑', 1000, 120),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setLocalState) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الهدايا',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'رصيدك التجريبي: ${store.coins} • كاريزما: ${store.charisma}',
                  style: const TextStyle(color: TomiColors.muted),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final name in ['نفسي', 'علي', 'فاطمة'])
                      ChoiceChip(
                        label: Text(name),
                        selected: recipient == name,
                        onSelected: (_) =>
                            setLocalState(() => recipient = name),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final gift in gifts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TomiCard(
                      padding: const EdgeInsets.all(10),
                      child: ListTile(
                        leading: Text(
                          gift.$2,
                          style: const TextStyle(fontSize: 30),
                        ),
                        title: Text(gift.$1),
                        subtitle: Text('${gift.$3} عملة • ${gift.$4} كاريزما'),
                        trailing: TextButton(
                          onPressed: () {
                            final success = store.sendGift(
                              price: gift.$3,
                              charismaPoints: gift.$4,
                              toSelf: recipient == 'نفسي',
                            );
                            if (success) {
                              Navigator.pop(sheetContext);
                              showNote(
                                context,
                                recipient == 'نفسي'
                                    ? 'تمت إضافة كاريزما تجريبية إلى حسابك'
                                    : 'تمت محاكاة إهداء $recipient • لا تُرسل إلى شخص حقيقي',
                              );
                            } else {
                              showNote(
                                context,
                                'رصيدك التجريبي ما يكفي لهذه الهدية',
                              );
                            }
                          },
                          child: const Text('إهداء'),
                        ),
                      ),
                    ),
                  ),
                const Text(
                  'الهدايا والأرصدة في هذه الشاشة تجريبية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: TomiColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.store});
  final TomiStore store;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.store.displayName);
  late final username = TextEditingController(text: widget.store.username);
  late final bio = TextEditingController(text: widget.store.bio);

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const TinyLabel('تعديل محلي • داخل النسخة التجريبية'),
          const SizedBox(height: 20),
          TextFormField(
            controller: name,
            maxLength: 30,
            decoration: const InputDecoration(labelText: 'الاسم'),
            validator: (value) => (value ?? '').trim().length < 2
                ? 'اكتب اسمًا من حرفين على الأقل'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: username,
            maxLength: 20,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'اليوزر',
              prefixText: '@',
            ),
            validator: (value) =>
                !RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch((value ?? '').trim())
                ? 'استخدم 3 إلى 20 حرفًا إنكليزيًا أو رقمًا أو _'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: bio,
            maxLines: 3,
            maxLength: 140,
            decoration: const InputDecoration(labelText: 'النبذة'),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                widget.store.updateProfile(name.text, username.text, bio.text);
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ التعديلات'),
          ),
        ],
      ),
    ),
  );
}
