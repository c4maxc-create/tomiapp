import 'live_control.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pending_store.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_api.dart';
import '../widgets.dart';
import 'roulette_page.dart' show rouletteRequestId;

String _groupTime(Object? value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return 'مجموعة محفوظة';
  final d = date.toUtc().add(const Duration(hours: 3));
  return '${d.year}/${d.month}/${d.day} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} بغداد';
}

class RouletteAdminPage extends StatefulWidget {
  const RouletteAdminPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<RouletteAdminPage> createState() => _RouletteAdminPageState();
}

class _RouletteAdminPageState extends State<RouletteAdminPage> {
  late final userId = widget.accounts.user!.id;
  late final session = widget.accounts.sessionRevision;
  bool get current =>
      mounted &&
      widget.accounts.user?.id == userId &&
      widget.accounts.sessionRevision == session;
  String get storageKey =>
      'tomi.roulette.admin.pending.${widget.accounts.api.baseUrl}.$userId';
  final daily = TextEditingController(),
      users = TextEditingController(),
      pool = TextEditingController(text: '1000'),
      count = TextEditingController(text: '200');
  final labels = <TextEditingController>[],
      icons = <TextEditingController>[],
      coins = <TextEditingController>[],
      weights = <TextEditingController>[];
  final prizeIds = <String>[],
      kinds = <String>[],
      styles = <String>[],
      days = <TextEditingController>[];
  List<Map<String, dynamic>> groups = [];
  Map<String, dynamic>? config, pending;
  List<Map<String, dynamic>> candidates = [];
  List<String> selected = [];
  String mode = 'everyone', criterion = 'combined';
  bool loading = true, busy = false;
  int total = 0, poolCount = 0;
  int? nextOffset;
  String? error, note;
  @override
  void initState() {
    super.initState();
    load();
  }

  void clearPrizeEditors() {
    for (final group in [labels, icons, coins, weights, days]) {
      for (final c in group) c.dispose();
      group.clear();
    }
  }

  void applyConfig(Map<String, dynamic> c) {
    config = c;
    mode = c['mode'] as String;
    daily.text = '${c['dailyLimit']}';
    clearPrizeEditors();
    prizeIds.clear();
    kinds.clear();
    styles.clear();
    for (final p in c['prizes'] as List) {
      prizeIds.add(p['id'] as String);
      kinds.add(p['kind'] as String? ?? 'coins');
      styles.add(p['styleId'] as String? ?? 'royal');
      days.add(TextEditingController(text: '${p['days'] ?? 7}'));
      labels.add(TextEditingController(text: '${p['label']}'));
      icons.add(TextEditingController(text: '${p['icon']}'));
      coins.add(TextEditingController(text: '${p['coins']}'));
      weights.add(TextEditingController(text: '${p['weight']}'));
    }
  }

  @override
  void dispose() {
    clearPrizeEditors();
    for (final c in [daily, users, pool, count]) c.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final prefs = await RoulettePendingStore.getInstance();
      final saved = await prefs.getString(storageKey);
      final data = await widget.accounts.chatRequest(
        'GET',
        '/v1/admin/roulette',
      );
      if (!current) return;
      setState(() {
        applyConfig((data['config'] as Map).cast<String, dynamic>());
        pending = saved == null
            ? null
            : (jsonDecode(saved) as Map).cast<String, dynamic>();
      });
      await loadCandidates();
      await loadGroups();
    } on AccountFailure catch (f) {
      if (current) setState(() => error = f.message);
    } catch (_) {
      if (current) setState(() => error = 'تعذّر تحميل إعدادات الروليت.');
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  Future<void> loadCandidates({bool more = false}) async {
    final n = int.tryParse(pool.text);
    if (n == null || n < 1 || n > 10000) {
      if (current) setState(() => error = 'مجموعة الاختيار من 1 إلى 10000.');
      return;
    }
    final data = await widget.accounts.chatRequest(
      'GET',
      '/v1/admin/roulette/candidates',
      query: {
        'poolSize': '$n',
        'criterion': criterion,
        if (more && nextOffset != null) 'offset': '$nextOffset',
      },
    );
    if (!current) return;
    setState(() {
      final rows = (data['items'] as List)
          .map((r) => (r as Map).cast<String, dynamic>())
          .toList();
      candidates = more ? [...candidates, ...rows] : rows;
      total = (data['total'] as num).toInt();
      poolCount = (data['poolCount'] as num).toInt();
      nextOffset = (data['nextOffset'] as num?)?.toInt();
    });
  }

  Future<void> showCandidates({bool more = false}) async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await loadCandidates(more: more);
    } on AccountFailure catch (f) {
      if (current) setState(() => error = f.message);
    } catch (_) {
      if (current) setState(() => error = 'تعذّر تحديث المساهمين.');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> loadGroups() async {
    final d = await widget.accounts.chatRequest(
      'GET',
      '/v1/admin/roulette/groups',
    );
    if (current)
      setState(
        () => groups = (d['items'] as List)
            .map((g) => (g as Map).cast<String, dynamic>())
            .toList(),
      );
  }

  void addPrize() {
    if (prizeIds.length >= 8) return;
    setState(() {
      prizeIds.add(
        'p' + rouletteRequestId().replaceAll('-', '').substring(0, 20),
      );
      kinds.add('coins');
      styles.add('royal');
      days.add(TextEditingController(text: '7'));
      labels.add(TextEditingController(text: 'جائزة جديدة'));
      icons.add(TextEditingController(text: '💎'));
      coins.add(TextEditingController(text: '10'));
      weights.add(TextEditingController(text: '10'));
    });
  }

  void removePrize(int i) {
    if (prizeIds.length <= 2) return;
    setState(() {
      prizeIds.removeAt(i);
      kinds.removeAt(i);
      styles.removeAt(i);
      for (final a in [labels, icons, coins, weights, days])
        a.removeAt(i).dispose();
    });
  }

  Widget prizeOptions(int i) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('kind-${prizeIds[i]}-${kinds[i]}'),
              initialValue: kinds[i],
              decoration: const InputDecoration(labelText: 'نوع الجائزة'),
              items: const [
                DropdownMenuItem(value: 'coins', child: Text('كوينز')),
                DropdownMenuItem(value: 'charisma', child: Text('كارزما')),
                DropdownMenuItem(value: 'frame', child: Text('إطار مؤقت')),
                DropdownMenuItem(
                  value: 'entrance',
                  child: Text('تأثير دخول مؤقت'),
                ),
                DropdownMenuItem(value: 'none', child: Text('حظ أوفر')),
              ],
              onChanged: (v) {
                if (v != null)
                  setState(() {
                    kinds[i] = v;
                    styles[i] = 'royal';
                  });
              },
            ),
          ),
          IconButton(
            tooltip: 'حذف الجائزة',
            onPressed: prizeIds.length > 2 ? () => removePrize(i) : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      if (['frame', 'entrance'].contains(kinds[i])) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('style-${prizeIds[i]}-${kinds[i]}-${styles[i]}'),
          initialValue: styles[i],
          decoration: const InputDecoration(labelText: 'التصميم'),
          items: [
            for (final e
                in (kinds[i] == 'frame'
                        ? {
                            'flame': 'اللهب',
                            'ice': 'الجليد',
                            'royal': 'التاج الملكي',
                          }
                        : {
                            'fire': 'ناري',
                            'comet': 'مسار النجوم',
                            'royal': 'دخول ملكي',
                          })
                    .entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => styles[i] = v);
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: days[i],
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'المدة بالأيام (1–30)'),
        ),
      ],
      const SizedBox(height: 10),
    ],
  );

  Future<void> submit(String action) async {
    if (busy || config == null || !current) return;
    Map<String, dynamic> body;
    if (pending != null) {
      body = pending!;
    } else {
      body = {
        'requestId': rouletteRequestId(),
        'action': action,
        'expectedRevision': config!['revision'],
      };
      if (action == 'configure') {
        final n = int.tryParse(daily.text);
        if (n == null || n < 1 || n > 100) {
          setState(() => error = 'المحاولات اليومية من 1 إلى 100.');
          return;
        }
        final prizes = <Map<String, dynamic>>[];
        for (var i = 0; i < labels.length; i++) {
          final value = int.tryParse(coins[i].text),
              weight = int.tryParse(weights[i].text);
          if (value == null ||
              weight == null ||
              value < 0 ||
              value > 10000 ||
              weight < 0 ||
              weight > 10000 ||
              labels[i].text.trim().isEmpty) {
            setState(() => error = 'راجع الاسم والكوينز والفرصة لكل جائزة.');
            return;
          }
          prizes.add({
            'id': prizeIds[i],
            'kind': kinds[i],
            if (['frame', 'entrance'].contains(kinds[i])) 'styleId': styles[i],
            if (['frame', 'entrance'].contains(kinds[i]))
              'days': int.tryParse(days[i].text),
            'label': labels[i].text.trim(),
            'icon': icons[i].text.trim(),
            'coins': value,
            'weight': weight,
          });
        }
        body.addAll({'mode': mode, 'dailyLimit': n, 'prizes': prizes});
      } else if (action == 'random') {
        final n = int.tryParse(pool.text), k = int.tryParse(count.text);
        if (n == null ||
            k == null ||
            n < 1 ||
            n > 10000 ||
            k < 1 ||
            k > 1000 ||
            k > n) {
          setState(() => error = 'راجع عدد المجموعة والمستفيدين.');
          return;
        }
        body.addAll({'criterion': criterion, 'poolSize': n, 'count': k});
      } else {
        final ids = users.text
            .split(RegExp(r'[\s,،;]+'))
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        if (ids.isEmpty || ids.length > 1000) {
          setState(() => error = 'أدخل من 1 إلى 1000 اسم مستخدم أو معرّف.');
          return;
        }
        body['users'] = ids;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(
            action == 'revoke'
                ? 'سحب الروليت؟'
                : action == 'random'
                ? 'توزيع عشوائي؟'
                : action == 'grant'
                ? 'منح الروليت؟'
                : 'حفظ إعدادات الروليت؟',
          ),
          content: Text(
            action == 'random'
                ? 'اختيار ${body['count']} شخص عشوائيًا من أعلى ${body['poolSize']} مساهم حسب المعيار المحدد. المنح يضاف إلى المستفيدين الحاليين.'
                : action == 'configure'
                ? 'تُطبّق الإعدادات على المحاولات الجديدة. وضع المختارين يبقي المنح السابقة، والسحب الفردي يمنع الحساب حتى في وضع الجميع.'
                : 'يشمل الإجراء جميع الحسابات المكتوبة. لا تُسحب الجوائز السابقة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      );
      if (accepted != true || !current) return;
    }
    setState(() {
      busy = true;
      error = null;
      note = null;
    });
    try {
      final prefs = await RoulettePendingStore.getInstance();
      if (!await prefs.setString(storageKey, jsonEncode(body)))
        throw StateError('Cannot persist command');
      pending = body;
      if (!current) return;
      final data = await widget.accounts.chatRequest(
        'POST',
        '/v1/admin/roulette/actions',
        body: body,
      );
      await prefs.remove(storageKey);
      if (!current) return;
      setState(() {
        pending = null;
        applyConfig((data['config'] as Map).cast<String, dynamic>());
        selected = (data['selectedIds'] as List).cast<String>();
        note = body['action'] == 'configure'
            ? 'حُفظت إعدادات الروليت.'
            : 'تم الإجراء على ${data['count']} حساب.';
      });
      await loadCandidates();
      await loadGroups();
    } on AccountFailure catch (f) {
      if (f.status >= 400 && f.status < 500) {
        final prefs = await RoulettePendingStore.getInstance();
        await prefs.remove(storageKey);
        pending = null;
      }
      if (current) setState(() => error = f.message);
    } catch (_) {
      if (current)
        setState(
          () =>
              error = 'تعذّر تأكيد الإجراء؛ استعد نفس الطلب قبل أي إجراء جديد.',
        );
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('إدارة مدار الحظ'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'التحكم الكامل بالروليت',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const Text(
            'صلاحية اللعب والجوائز والمحاولات • داخل الغرف الصوتية فقط',
            style: TextStyle(color: TomiColors.muted, height: 1.6),
          ),
          if (loading || busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: TomiColors.pink)),
          if (note != null)
            Text(note!, style: const TextStyle(color: TomiColors.accent)),
          if (pending != null)
            FilledButton(
              onPressed: busy ? null : () => submit('recover'),
              child: const Text('استعادة نتيجة الطلب المعلّق'),
            ),
          if (config != null)
            AbsorbPointer(
              absorbing: busy || pending != null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              OutlinedButton.icon(onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => LiveRouletteControlPage(accounts: widget.accounts))), icon: const Icon(Icons.casino_outlined), label: const Text('تحكم الجولة القادمة • روليت الغرف')),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'everyone', label: Text('الجميع')),
                      ButtonSegment(
                        value: 'selected',
                        label: Text('المختارون فقط'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => setState(() => mode = s.first),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => submit('configure'), child: const Text('حفظ إتاحة اللعب')),
                  const Text('صلاحية الجميع والمختارين تشمل روليت الغرف. خانات الفواكه واللحوم ونسبها ثابتة؛ نتيجة الجولة القادمة من زر التحكم أعلاه.'),
                  ExpansionTile(title: const Text('جوائز الدوران المجاني'), subtitle: const Text('إعدادات منفصلة عن روليت الفواكه واللحوم'), children: [
                  TextField(
                    controller: daily,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'محاولات يومية لكل شخص (1–100)',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'جوائز العجلة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Text(
                    'الفرصة وزن نسبي: 40 و30 و20 و10 تعني 40% و30% و20% و10%. صفر يستبعد الجائزة. تظهر الفرص للمستخدم.',
                    style: TextStyle(color: TomiColors.muted, height: 1.6),
                  ),
                  for (var i = 0; i < labels.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TomiCard(
                        child: Column(
                          children: [
                            prizeOptions(i),
                            Row(
                              children: [
                                SizedBox(
                                  width: 68,
                                  child: TextField(
                                    controller: icons[i],
                                    decoration: const InputDecoration(
                                      labelText: 'رمز',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: labels[i],
                                    maxLength: 32,
                                    decoration: const InputDecoration(
                                      labelText: 'اسم الجائزة',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: coins[i],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'القيمة: كوينز / كارزما (0–10000)',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: weights[i],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'وزن الفرصة',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: prizeIds.length < 8 ? addPrize : null,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة جائزة (حتى 8)'),
                  ),
                  FilledButton(
                    onPressed: () => submit('configure'),
                    child: const Text('حفظ جوائز الدوران المجاني'),
                  ),
                  ]),
                  const SizedBox(height: 24),
                  const Text(
                    'منح أو سحب فردي وجماعي',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: users,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'أسماء المستخدمين أو المعرّفات',
                      hintText: 'افصل بمسافة أو سطر جديد أو فاصلة',
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => submit('grant'),
                        icon: const Icon(Icons.add),
                        label: const Text('منح'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => submit('revoke'),
                        icon: const Icon(Icons.remove),
                        label: const Text('سحب'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'توزيع على المساهمين',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'المؤهلون حسب المعيار: $total • ضمن المجموعة: $poolCount',
                    style: const TextStyle(color: TomiColors.accent),
                  ),
                  const Text(
                    'الكوينز الممنوحة: ما أضافه المالك منذ هذا التحديث. الدعم: كوينز الهدايا المرسلة. النشاط: رسائل ومنشورات آخر 30 يومًا. ليست هذه أرقام دفع موثّق من بوابة شحن.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TomiColors.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: criterion,
                    decoration: const InputDecoration(
                      labelText: 'معيار المساهمة',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'combined',
                        child: Text('المجموع الكلي'),
                      ),
                      DropdownMenuItem(
                        value: 'credits',
                        child: Text('الكوينز الممنوحة'),
                      ),
                      DropdownMenuItem(
                        value: 'support',
                        child: Text('الدعم بالهدايا'),
                      ),
                      DropdownMenuItem(
                        value: 'activity',
                        child: Text('نشاط آخر 30 يومًا'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => criterion = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pool,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'أعلى مجموعة (مثل 1000)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: count,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'عدد المختارين (مثل 200)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: showCandidates,
                    child: const Text('عرض المساهمين وتحديث العدد'),
                  ),
                  FilledButton(
                    onPressed: () => submit('random'),
                    child: const Text('توزيع عشوائي على العدد المحدد'),
                  ),
                  if (selected.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: selected.join('\n')),
                        );
                        showNote(
                          context,
                          'نُسخت معرّفات المجموعة. تگدر تلصقها بخانة السحب.',
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: Text('نسخ المجموعة (${selected.length})'),
                    ),
                  if (groups.isNotEmpty)
                    const Text(
                      'المجموعات الممنوحة سابقًا',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  for (final g in groups)
                    ListTile(
                      title: Text('${g['count']} حساب'),
                      subtitle: Text(_groupTime(g['createdAt'])),
                      trailing: TextButton(
                        onPressed: () {
                          users.text = (g['selectedIds'] as List).join('\n');
                          submit('revoke');
                        },
                        child: const Text('سحب المجموعة'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  for (final row in candidates)
                    ListTile(
                      title: Text(
                        '${row['displayName']} • @${row['username']}',
                      ),
                      subtitle: Text(
                        'كوينز ${row['credits']} • دعم ${row['support']} • نشاط ${row['activity']}',
                      ),
                      trailing: Text('${row['score']}'),
                    ),
                  if (nextOffset != null)
                    TextButton(
                      onPressed: () => showCandidates(more: true),
                      child: const Text('المزيد'),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
