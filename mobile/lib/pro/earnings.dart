import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/ui.dart';
import 'jobs.dart';
import 'pro_app.dart';

/// Income: finished jobs, how much and how they were paid. Plus credit, invites and account.
class EarningsTab extends StatefulWidget {
  const EarningsTab({super.key});
  @override
  State<EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<EarningsTab> {
  String period = 'month';
  static const periods = [MapEntry('today', 'היום'), MapEntry('week', 'שבוע'), MapEntry('month', 'החודש'), MapEntry('all', 'הכל')];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProStore.i,
      builder: (ctx, _) {
        final s = ProStore.i;
        final rows = s.earnRows(period);
        final total = s.earnTotal(rows);
        final by = <String, num>{};
        for (final r in rows) {
          if (r['pending'] == true) continue;
          by[r['method'].toString()] = (by[r['method'].toString()] ?? 0) + (asNum(r['amount']) ?? 0);
        }
        final leadFees = s.cfg['leadFees'] == true;
        return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 28), children: [
          Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ChipsRow(items: periods, value: period, onPick: (v) => setState(() => period = v)),
              const SizedBox(height: 10),
              Text('הכנסות', style: TextStyle(color: Pal.muted)),
              Text(ils(total), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Pal.brand)),
              Text('${rows.length} עבודות', style: TextStyle(color: Pal.muted)),
              if (by.isNotEmpty) const SizedBox(height: 10),
              for (final e in by.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    SizedBox(width: 110, child: Text(payLabels[e.key] ?? e.key)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: total > 0 ? (e.value / total).toDouble() : 0.0, minHeight: 8, color: Pal.brand, backgroundColor: Pal.card2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(ils(e.value), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),
          const SectionTitle('עבודות שבוצעו'),
          if (rows.isEmpty)
            const Empty(icon: Icons.account_balance_wallet_outlined, title: 'כאן יופיעו העבודות שסיימתם', text: 'עם הסכום ואיך שולם לכם.'),
          for (final r in rows) _row(context, r),
          if (leadFees) ...[
            const SectionTitle('קרדיט להצעות'),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('יתרה', style: TextStyle(color: Pal.muted)),
                Text(ils(s.me['balance']), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                Text('כל הצעה עולה קרדיט לפי התחום.', style: TextStyle(color: Pal.muted)),
                if (s.cfg['topup'] == true) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: () => topUp(context), icon: const Icon(Icons.add_rounded), label: const Text('טעינת קרדיט')),
                ],
              ]),
            ),
          ],
          const SectionTitle('הזמנת חברים'),
          _invite(context, s),
          const SectionTitle('החשבון'),
          Box(
            child: Row(children: [
              CircleAvatar(backgroundColor: Pal.brandSoft, child: Icon(Icons.person_rounded, color: Pal.brand)),
              const SizedBox(width: 12),
              Expanded(child: Text(s.me['name']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            ]),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Api.put('/api/pro/availability', {'available': false}).catchError((_) => null);
              ProStore.i.stop();
              await Api.setToken(null);
              Api.onLoggedOut?.call();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('יציאה'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Pal.hot),
            onPressed: () async {
              final ok = await confirmSheet(context,
                  title: 'למחוק את החשבון?',
                  text: 'השם, הטלפון, המיקום והמסמכים יימחקו, ולא תקבלו יותר קריאות. אי אפשר לבטל את זה. אי אפשר למחוק כשיש עבודה בביצוע.',
                  ok: 'כן, למחוק',
                  danger: true);
              if (!ok) return;
              try {
                await Api.delete('/api/me');
                ProStore.i.stop();
                await Api.setToken(null);
                Api.onLoggedOut?.call();
              } on ApiError catch (e) {
                if (context.mounted) toast(context, e.message, err: true);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('מחיקת החשבון'),
          ),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
            TextButton(onPressed: () => openLink(Api.url('/privacy')), child: const Text('מדיניות פרטיות')),
            TextButton(onPressed: () => openLink(Api.url('/terms')), child: const Text('תנאי שימוש')),
          ]),
        ]);
      },
    );
  }

  Widget _row(BuildContext context, J r) {
    final j = asMap(r['j']);
    final method = r['method'].toString();
    return Box(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        catTile(j['categoryId']?.toString(), size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Cats.name(j['categoryId']?.toString()), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${dayLabel(r['when'])} · ${r['pending'] == true ? 'ממתין לאישור הלקוח' : payLabels[method] ?? method}', style: TextStyle(color: Pal.muted, fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(ils(r['amount']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (method == 'none')
            InkWell(
              onTap: () => recordPayment(context, j),
              child: Text('לרשום תשלום', style: TextStyle(color: Pal.brand, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      ]),
    );
  }

  Widget _invite(BuildContext context, ProStore s) {
    final link = Api.url('/pro?ref=${s.me['refCode'] ?? ''}');
    return Box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.card_giftcard_rounded, color: Pal.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.cfg['leadFees'] == true ? '25 ש״ח קרדיט כשהחבר מסיים עבודה ראשונה' : 'שלחו לבעלי מקצוע שאתם מכירים. ההרשמה בדקה',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text('הקוד שלכם: ${s.me['refCode'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: 'מקבלים עבודות באזור שלכם עם זריז מקצוענים. קוד הצטרפות: ${s.me['refCode'] ?? ''}\n$link'));
            if (context.mounted) toast(context, 'הועתק. אפשר להדביק בוואטסאפ');
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('העתקת הזמנה'),
        ),
      ]),
    );
  }
}

/// Buy credit: pick a package, pay on the provider's page, the credit arrives by itself.
Future<void> topUp(BuildContext context) async {
  final packs = asList(ProStore.i.cfg['topupPackages']).isEmpty
      ? <num>[50, 100, 200, 500]
      : (ProStore.i.cfg['topupPackages'] as List).map((e) => asNum(e) ?? 0).toList();
  var amount = packs.length > 1 ? packs[1] : packs.first;
  var busy = false, waiting = false;
  var err = '';
  Timer? poll;
  await openSheet<void>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, set) {
      if (waiting) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sheetTitle(ctx, 'ממתינים לתשלום'),
          const Empty(icon: Icons.schedule_rounded, title: 'משלימים את התשלום בדף שנפתח', text: 'הקרדיט יתווסף כאן אוטומטית.'),
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('סגירה')),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(ctx, 'טעינת קרדיט'),
        Text('כל הצעה שאתם שולחים עולה קרדיט לפי התחום. בוחרים סכום ומשלמים בכרטיס אשראי.', style: TextStyle(color: Pal.muted)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            for (final a in packs)
              Material(
                color: a == amount ? Pal.brandSoft : Pal.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: a == amount ? Pal.brand : Pal.line)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => set(() => amount = a),
                  child: Center(child: Text(ils(a), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: a == amount ? Pal.brand : Pal.ink))),
                ),
              ),
          ],
        ),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: TextStyle(color: Pal.hot))),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  set(() => busy = true);
                  try {
                    final r = asMap(await Api.post('/api/pro/wallet/topup', {'amount': amount}));
                    if (r['payUrl'] == null) {
                      await ProStore.i.load();
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        toast(context, 'נוספו ${ils(amount)} לקרדיט');
                      }
                      return;
                    }
                    await openLink(r['payUrl'].toString());
                    set(() => waiting = true);
                    final started = DateTime.now();
                    poll = Timer.periodic(const Duration(seconds: 3), (_) async {
                      if (DateTime.now().difference(started).inMinutes > 10) {
                        poll?.cancel();
                        return;
                      }
                      try {
                        final x = asMap(await Api.get('/api/pro/wallet/topups/${r['id']}'));
                        if (x['status'] == 'paid') {
                          poll?.cancel();
                          await ProStore.i.load();
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) toast(context, 'נוספו ${ils(x['amount'])} לקרדיט');
                        }
                      } catch (_) {}
                    });
                  } on ApiError catch (e) {
                    set(() {
                      busy = false;
                      err = e.message;
                    });
                  }
                },
          icon: const Icon(Icons.credit_card_rounded),
          label: const Text('לתשלום'),
        ),
      ]);
    }),
  );
  poll?.cancel();
}
