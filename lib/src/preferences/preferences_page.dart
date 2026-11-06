import 'package:flutter/material.dart';
import '../accounts/account_controller.dart';
import 'media_preferences.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  final media = MediaPreferences.instance;
  Map<String, dynamic>? policy;
  bool busy = false;
  String? error, note;
  @override
  void initState() {
    super.initState();
    media.addListener(changed);
    load();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      await media.restore();
      final d = await widget.accounts.chatRequest(
        'GET',
        '/v1/me/contact-preferences',
      );
      if (mounted)
        setState(() {
          policy = (d['preferences'] as Map).cast<String, dynamic>();
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => error = 'تعذّر جلب إعدادات التواصل؛ حدّث الخادم وأعد المحاولة.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> savePolicy(String key, String value) async {
    if (busy || policy == null) return;
    setState(() => busy = true);
    try {
      final d = await widget.accounts.chatRequest(
        'PUT',
        '/v1/me/contact-preferences',
        body: {...policy!, key: value},
      );
      if (mounted)
        setState(() {
          policy = (d['preferences'] as Map).cast<String, dynamic>();
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'لم يُحفظ التغيير؛ أعد المحاولة.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> operation(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) setState(() => note = 'تم الحفظ.');
    } catch (_) {
      if (mounted)
        setState(() => error = 'تعذّر الحفظ أو التنظيف؛ حاول مجددًا.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    media.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('التواصل وتوفير البيانات')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.redAccent)),
        if (policy == null && !busy)
          TextButton(onPressed: load, child: const Text('إعادة المحاولة')),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('من يگدر يتواصل وياك؟'),
          subtitle: Text('تطبق هذه الخيارات على الخادم وعلى جميع أجهزتك.'),
        ),
        for (final e in {
          'messages': 'يراسلني',
          'calls': 'يتصل بي',
          'roomInvites': 'يدعوني لمايك الغرفة',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              key: ValueKey('${e.key}-${policy?[e.key]}'),
              initialValue: policy?[e.key] as String?,
              isExpanded: true,
              decoration: InputDecoration(labelText: e.value),
              items: const [
                DropdownMenuItem(value: 'everyone', child: Text('الجميع')),
                DropdownMenuItem(
                  value: 'following',
                  child: Text('الأشخاص الذين أتابعهم'),
                ),
                DropdownMenuItem(value: 'nobody', child: Text('لا أحد')),
              ],
              onChanged: busy || policy == null
                  ? null
                  : (v) {
                      if (v != null) savePolicy(e.key, v);
                    },
            ),
          ),
        const Divider(),
        SwitchListTile(
          title: const Text('توفير البيانات'),
          subtitle: const Text(
            'فيديو أصغر عند الإرسال وذاكرة صور أقل؛ التشغيل التلقائي متوقف.',
          ),
          value: media.dataSaver,
          onChanged: busy
              ? null
              : (v) => operation(() => media.update(saver: v)),
        ),
        SwitchListTile(
          title: const Text('جودة ذكية للرفع'),
          subtitle: const Text(
            'تخفيف الفيديو على بيانات الهاتف والحفاظ على جودة أعلى عبر Wi-Fi.',
          ),
          value: media.smartQuality,
          onChanged: busy
              ? null
              : (v) => operation(() => media.update(smart: v)),
        ),
        SwitchListTile(
          title: const Text('تشغيل فيديو المنشورات والمحادثات عند فتحه'),
          subtitle: const Text('الفيديوهات داخل القائمة لا تشتغل تلقائيًا.'),
          value: media.autoplay && !media.dataSaver,
          onChanged: busy || media.dataSaver
              ? null
              : (v) => operation(() => media.update(auto: v)),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('تنظيف المعاينات المؤقتة'),
          subtitle: const Text('لا يحذف الرسائل أو المسودات أو صور الاستوديو.'),
          onTap: busy ? null : () => operation(media.clearPreviews),
        ),
        if (note != null) Text(note!),
      ],
    ),
  );
}
