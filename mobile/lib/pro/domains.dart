import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/ui.dart';
import 'pro_app.dart';

const reqNames = <String, String>{
  'license': 'רישיון מקצועי',
  'insurance': 'ביטוח צד ג׳',
  'criminal_record': 'אישור היעדר רישום פלילי',
  'minors_clearance': 'אישור משטרה לעבודה עם קטינים',
  'vehicle': 'רישיון רכב ונהיגה',
};

/// A license is per profession ('license:electric' -> 'רישיון חשמל'); the name comes with the categories.
String reqName(String r) =>
    Cats.byId.values.where((c) => c['requirement'] == r && c['requirementName'] != null).firstOrNull?['requirementName']?.toString() ?? reqNames[r] ?? r;

/// What I do, how I work and how far I go. A plain checklist per field.
class DomainsTab extends StatefulWidget {
  const DomainsTab({super.key});
  @override
  State<DomainsTab> createState() => _DomainsTabState();
}

class _DomainsTabState extends State<DomainsTab> {
  Set<String>? sel;
  Set<String> modes = {};
  double radius = 20;
  bool busy = false, dirty = false;
  Timer? _auto;

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  // Every change is saved by itself a moment later, so nothing is lost when leaving the screen.
  void _changed() {
    dirty = true;
    _auto?.cancel();
    _auto = Timer(const Duration(milliseconds: 800), () => _save(quiet: true));
  }

  void _init(J me) {
    if (sel != null && dirty) return;
    // a whole field selected = every specialty in it
    final cats = strList(me['categories']);
    sel = {};
    for (final c in cats) {
      final p = Cats.tree.where((t) => t['id'] == c).firstOrNull;
      if (p != null) {
        sel!.addAll(asList(p['subs']).map((s) => s['id'].toString()));
      } else {
        sel!.add(c);
      }
    }
    modes = strList(me['serviceModes']).toSet();
    radius = (asNum(me['radiusKm']) ?? 20).toDouble();
  }

  Future<void> _save({bool quiet = false}) async {
    _auto?.cancel();
    if (modes.isEmpty) {
      toast(context, 'בחרו לפחות אופן עבודה אחד', err: true);
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      // a field with every specialty ticked is saved as the whole field (new specialties included)
      final out = <String>[];
      for (final p in Cats.tree) {
        final subs = asList(p['subs']).map((s) => s['id'].toString()).toList();
        final picked = subs.where(sel!.contains).toList();
        if (subs.isNotEmpty && picked.length == subs.length) {
          out.add(p['id'].toString());
        } else {
          out.addAll(picked);
        }
      }
      final loc = quiet ? null : await currentLocation();
      ProStore.i.me = asMap(await Api.put('/api/pro/me', {
        'categories': out,
        'serviceModes': modes.toList(),
        'radiusKm': radius.round(),
        if (loc != null) 'location': loc,
      }));
      dirty = false;
      if (mounted) toast(context, quiet ? 'נשמר' : 'נשמר, כולל המיקום. קריאות יגיעו לפי הבחירה');
      await ProStore.i.load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _uploadDoc(String type) async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 85);
      if (x == null) return;
      final saved = await Api.upload(await x.readAsBytes());
      await Api.post('/api/pro/documents', {'type': type, 'url': saved['url']});
      if (mounted) toast(context, 'המסמך נשלח לבדיקה');
      await ProStore.i.load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } catch (_) {
      if (mounted) toast(context, 'לא הצלחנו לצרף את המסמך', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProStore.i,
      builder: (ctx, _) {
        final me = ProStore.i.me;
        if (me.isEmpty) return const Center(child: CircularProgressIndicator());
        _init(me);
        final approved = strList(me['approvedRequirements']).toSet();
        final docs = asList(me['documents']);
        final needed = <String>{
          for (final id in sel!)
            if (Cats.get(id)?['requirement'] != null) Cats.get(id)!['requirement'].toString(),
        };
        return Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 110), children: [
            const SectionTitle('מה אתם עושים'),
            for (final p in Cats.tree) _group(p, approved),
            const SectionTitle('איך אתם עובדים'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in ['onsite', 'remote', 'phone', 'delivery'])
                FilterChip(
                  avatar: Icon(modeIcon[m], size: 18),
                  label: Text(m == 'delivery' ? 'שליחויות' : modeLabel[m]!),
                  selected: modes.contains(m),
                  onSelected: (v) {
                    setState(() => v ? modes.add(m) : modes.remove(m));
                    _changed();
                  },
                ),
            ]),
            const SectionTitle('עד כמה רחוק'),
            Box(
              child: Column(children: [
                Text('${radius.round()} ק״מ', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                Slider(
                  value: radius.clamp(1.0, 100.0).toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '${radius.round()} ק״מ',
                  onChanged: (v) => setState(() {
                    dirty = true;
                    radius = v;
                  }),
                  onChangeEnd: (_) => _changed(),
                ),
                Text('עבודות מרחוק ובטלפון מגיעות מכל הארץ', style: TextStyle(color: Pal.muted, fontSize: 12)),
              ]),
            ),
            if (needed.isNotEmpty) ...[
              const SectionTitle('מסמכים'),
              for (final r in needed)
                Box(
                  child: Row(children: [
                    Icon(approved.contains(r) ? Icons.verified_rounded : Icons.description_rounded, color: approved.contains(r) ? Pal.ok : Pal.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(reqName(r), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Builder(builder: (_) {
                          final last = docs.where((d) => d['type'] == r).lastOrNull;
                          final rejected = !approved.contains(r) && last?['status'] == 'rejected';
                          return Text(
                            approved.contains(r)
                                ? 'מאושר'
                                : rejected
                                    ? 'נדחה: ${last?['reason'] ?? 'העלו מסמך ברור ובתוקף'}'
                                    : last != null
                                        ? 'בבדיקה. קריאות בתחום יגיעו אחרי האישור'
                                        : 'חסר. בלי מסמך מאושר לא יגיעו קריאות בתחום',
                            style: TextStyle(color: approved.contains(r) ? Pal.ok : rejected ? Pal.hot : Pal.muted, fontSize: 12),
                          );
                        }),
                      ]),
                    ),
                    if (!approved.contains(r))
                      OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(80, 40)), onPressed: () => _uploadDoc(r), child: const Text('צילום')),
                  ]),
                ),
            ],
          ]),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: FilledButton.icon(
              onPressed: busy ? null : () => _save(),
              icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.check_rounded),
              label: Text(dirty ? 'שומר…' : 'שמירה ועדכון המיקום שלי'),
            ),
          ),
        ]);
      },
    );
  }

  Widget _group(J p, Set<String> approved) {
    final subs = asList(p['subs']);
    final n = subs.where((s) => sel!.contains(s['id'])).length;
    final req = p['requirement']?.toString();
    final locked = req != null && !approved.contains(req);
    final lead = asNum(p['leadPrice']) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
      color: Pal.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: n > 0 ? Pal.brand.withValues(alpha: .5) : Pal.line)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: catTile(p['id']?.toString(), size: 36),
          title: Text(p['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(n > 0 ? 'נבחרו $n מתוך ${subs.length}' : 'לא נבחר', style: TextStyle(color: n > 0 ? Pal.brand : Pal.muted, fontSize: 12)),
          trailing: locked ? Icon(Icons.lock_outline_rounded, color: Pal.warn, size: 20) : null,
          children: [
            CheckboxListTile(
              value: n == subs.length && subs.isNotEmpty,
              title: const Text('כל התחום', style: TextStyle(fontWeight: FontWeight.w700)),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) {
                setState(() {
                  for (final s in subs) {
                    v == true ? sel!.add(s['id'].toString()) : sel!.remove(s['id'].toString());
                  }
                });
                _changed();
              },
            ),
            for (final s in subs)
              CheckboxListTile(
                dense: true,
                value: sel!.contains(s['id']),
                title: Text(s['name'].toString()),
                secondary: (s['requirement'] ?? req) != null && !approved.contains(s['requirement'] ?? req)
                    ? Icon(Icons.lock_outline_rounded, color: Pal.warn, size: 18)
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) {
                  setState(() => v == true ? sel!.add(s['id'].toString()) : sel!.remove(s['id'].toString()));
                  _changed();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                [
                  if (ProStore.i.cfg['leadFees'] == true && lead > 0) 'כל הצעה בתחום: ${ils(lead)}',
                  if (p['starter'] == true) 'אפשר להתחיל בלי רישיון',
                  if (locked) 'קריאות יגיעו רק אחרי שנאשר ${reqName(req)}',
                ].join(' · '),
                style: TextStyle(color: Pal.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
