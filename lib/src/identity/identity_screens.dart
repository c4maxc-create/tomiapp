import 'dart:async';

import 'package:flutter/material.dart';

import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import '../accounts/account_widgets.dart';
import '../widgets.dart';
import 'identity_controller.dart';
import 'identity_models.dart';
import 'identity_avatar.dart';

class IdentitySummary extends StatelessWidget {
  const IdentitySummary(this.user, {super.key, this.onCustomize});
  final AccountUser user;
  final VoidCallback? onCustomize;
  @override
  Widget build(BuildContext c) {
    final id = user.identity;
    if (!id.available) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'رتبة الدعم ${id.level}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: TomiColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: id.progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 6),
          Text(
            id.next == null
                ? '${id.xp} نقطة • أعلى مستوى'
                : '${id.xp} نقطة • باقي ${id.remaining} للمستوى التالي',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: TomiColors.muted),
          ),
          if (id.badges.isNotEmpty)
            Material(
              color: Colors.transparent,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (final badge in id.badges)
                    Chip(
                      avatar: const Icon(Icons.verified_outlined, size: 16),
                      label: Text(badge['name'] as String),
                    ),
                ],
              ),
            ),
          if (onCustomize != null)
            TextButton.icon(
              key: const Key('customize-identity'),
              onPressed: onCustomize,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('إطاراتي وهويتي'),
            ),
        ],
      ),
    );
  }
}

class IdentityStudioPage extends StatefulWidget {
  const IdentityStudioPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<IdentityStudioPage> createState() => _IdentityStudioPageState();
}

class _IdentityStudioPageState extends State<IdentityStudioPage> {
  late final model = IdentityController(widget.accounts);
  @override
  void initState() {
    super.initState();
    unawaited(model.load());
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: Listenable.merge([model, widget.accounts]),
    builder: (c, _) {
      final user = widget.accounts.user;
      if (user == null) return const SizedBox.shrink();
      final catalog = model.catalog;
      return Scaffold(
        appBar: AppBar(title: const Text('هويتي ومستواي')),
        body: RefreshIndicator(
          onRefresh: model.load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: AccountAvatar(user, size: 100)),
              IdentitySummary(user),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'الكارزما: ${user.identity.charisma} • مجموع الدعم المستلم',
                ),
              ),
              const Text(
                'إطارات وتأثيرات الغرف الجديدة متاحة بمدة محدودة من متجر الغرفة.',
                style: TextStyle(color: TomiColors.muted),
              ),
              const Text(
                'نقطة لكل عملة تجريبية تصرفها بهدية ناجحة. الغرف بدون مستويات. دعم النفس يُحسب مرة واحدة. إعادة نفس الطلب لا تضيف نقاطًا جديدة.',
                style: TextStyle(color: TomiColors.muted, height: 1.7),
              ),
              const Text(
                'الصورة المتحركة تحل محل صورتك. اختَر «صورتي الحالية» للرجوع إليها، أو ارفع صورة جديدة من ملفك الشخصي.',
                style: TextStyle(color: TomiColors.muted, height: 1.7),
              ),
              if (model.error != null) AccountErrorMessage(model.error!),
              if (model.loading || model.saving)
                const LinearProgressIndicator(),
              if (catalog != null) ...[
                section(
                  'الإطارات',
                  'frames',
                  'frameId',
                  user.identity.frameId,
                  user.identity,
                  catalog,
                ),
                section(
                  'الصور المتحركة الجاهزة',
                  'portraits',
                  'portraitId',
                  user.identity.portraitId,
                  user.identity,
                  catalog,
                ),
                section(
                  'تأثير الدخول إلى الغرفة',
                  'entrances',
                  'entranceId',
                  user.identity.entranceId,
                  user.identity,
                  catalog,
                ),
                const SizedBox(height: 20),
                const Text(
                  'عتبات رتبة الدعم',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                for (var i = 0; i < catalog.thresholds.length; i++)
                  ListTile(
                    leading: Icon(
                      i + 1 <= user.identity.level
                          ? Icons.verified
                          : Icons.lock_outline,
                    ),
                    title: Text('رتبة الدعم ${i + 1}'),
                    trailing: Text('${catalog.thresholds[i]} نقطة'),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
  Future<void> previewStyle(String key, IdentityStyle style) async {
    final user = widget.accounts.user;
    if (user == null) return;
    final session = widget.accounts.sessionRevision;
    final identity = UserIdentity({
      ...user.identity.data,
      if (key == 'frameId') 'roomFrameId': style.id,
      if (key == 'frameId') 'roomFrameExpiresAt': null,
      if (key == 'entranceId') 'roomEntranceId': style.id,
      key: style.id,
    });
    final approved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(style.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              IdentityDecoration(
                identity: identity,
                size: 120,
                name: user.displayName,
                child: AccountAvatar(user, size: 120).base(context),
              ),
              const SizedBox(height: 20),
              Text(
                key == 'entranceId'
                    ? 'معاينة الهوية؛ تأثير الدخول يظهر عند دخول الغرفة.'
                    : 'معاينة قبل الحفظ',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ الاختيار'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      ),
    );
    if (approved == true &&
        mounted &&
        widget.accounts.user?.id == user.id &&
        widget.accounts.sessionRevision == session) {
      await model.select(key, style.id);
    }
  }

  Widget section(
    String title,
    String group,
    String key,
    String selected,
    UserIdentity identity,
    IdentityCatalog catalog,
  ) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final style in catalog.styles[group] ?? [])
          ListTile(
            key: ValueKey('identity-$group-${style.id}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              style.id == selected
                  ? Icons.check_circle
                  : style.level > identity.level
                  ? Icons.lock_outline
                  : Icons.circle_outlined,
              color: style.id == selected
                  ? TomiColors.accent
                  : TomiColors.muted,
            ),
            title: Text(style.name),
            subtitle: Text(
              style.level > identity.level
                  ? 'يُفتح عند رتبة الدعم ${style.level}'
                  : 'متاح لمستواك',
            ),
            onTap:
                model.loading ||
                    model.saving ||
                    style.level > identity.level ||
                    style.id == selected
                ? null
                : () => previewStyle(key, style),
          ),
      ],
    ),
  );
}
