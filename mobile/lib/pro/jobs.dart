import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/ui.dart';
import 'popup.dart';
import 'pro_app.dart';

const payLabels = <String, String>{
  'app': 'באפליקציה', 'cash': 'מזומן', 'bit': 'ביט / פייבוקס', 'transfer': 'העברה בנקאית', 'card': 'אשראי', 'other': 'אחר', 'none': 'לא נרשם',
};

/// Where the pro is heading now: the customer / pickup, or the drop-off after pickup.
J tripTarget(J j) {
  final drop = asMap(j['dropoff']);
  final toDrop = drop['location'] != null && ['picked_up', 'arrived'].contains(j['status']);
  return toDrop
      ? {'loc': drop['location'], 'address': drop['address'], 'label': 'ניווט למסירה'}
      : {'loc': j['location'], 'address': j['address'], 'label': j['dropoff'] != null ? 'ניווט לאיסוף' : 'ניווט ב-Waze'};
}

/// Moves the job to the next step (asks for the customer's name when finishing on site).
Future<void> advanceJob(BuildContext context, J j) async {
  final nx = nextOf(j);
  if (nx == null) return;
  String? signature;
  if (j['mode'] == 'onsite' && nx[0] == 'completed') {
    final name = TextEditingController();
    signature = await openSheet<String>(
      context,
      (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(ctx, 'סיום העבודה'),
        const Text('שם הלקוח, כאישור שהעבודה נעשתה'),
        const SizedBox(height: 10),
        TextField(controller: name, autofocus: true),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () {
            if (name.text.trim().isNotEmpty) Navigator.pop(ctx, name.text.trim());
          },
          icon: const Icon(Icons.check_rounded),
          label: const Text('סיימתי'),
        ),
      ]),
    );
    if (signature == null) return;
  }
  try {
    await Api.post('/api/jobs/${j['id']}/status', {'status': nx[0], if (signature != null) 'signature': signature});
    haptic();
    if (nx[0] == 'en_route') await ProStore.i.pushLocationNow();
    if (context.mounted) {
      toast(context, nx[0] == 'completed' ? 'עודכן. ממתינים לאישור הלקוח' : nx[0] == 'en_route' ? 'יצאתם. הלקוח רואה אתכם על המפה' : 'עודכן, הלקוח רואה');
    }
  } on ApiError catch (e) {
    if (context.mounted) toast(context, e.message, err: true);
  }
  await ProStore.i.load();
}

/// The job I'm on: address, navigation, call, and one big button for the next step.
class TripCard extends StatefulWidget {
  const TripCard({super.key, required this.job, required this.goTab});
  final J job;
  final void Function(int) goTab;
  @override
  State<TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<TripCard> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final j = widget.job, t = tripTarget(j), nx = nextOf(j);
    final physical = ['onsite', 'delivery'].contains(j['mode']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Pal.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Pal.brand.withValues(alpha: .5)),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, -6))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          catTile(j['categoryId']?.toString(), size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Cats.name(j['categoryId']?.toString()), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(j['description']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Pal.muted, fontSize: 13)),
            ]),
          ),
          Tag(proStatus[j['status']] ?? ''),
        ]),
        if (physical && t['address'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Icon(Icons.place_rounded, size: 18, color: Pal.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(t['address'].toString(), style: const TextStyle(fontSize: 15))),
            ]),
          ),
        const SizedBox(height: 10),
        Row(children: [
          if (physical && t['loc'] != null)
            Expanded(child: _small(Icons.navigation_rounded, t['label'].toString(), () => waze(t['loc']))),
          if (j['phone'] != null) ...[
            const SizedBox(width: 8),
            Expanded(child: _small(Icons.phone_rounded, 'ללקוח', () => callPhone(j['phone']?.toString()))),
          ],
          const SizedBox(width: 8),
          Expanded(child: _small(Icons.list_alt_rounded, 'פרטים', () => widget.goTab(2))),
        ]),
        if (nx != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(62)),
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    await advanceJob(context, j);
                    if (mounted) setState(() => busy = false);
                  },
            icon: const Icon(Icons.check_rounded, size: 26),
            label: Text(nx[1], style: const TextStyle(fontSize: 20)),
          ),
        ],
      ]),
    );
  }

  Widget _small(IconData icon, String text, VoidCallback onTap) => Material(
        color: Pal.brandSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: Pal.brand),
              const SizedBox(width: 4),
              Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(color: Pal.brand, fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
          ),
        ),
      );
}

// ---- open requests
class FeedTab extends StatefulWidget {
  const FeedTab({super.key, required this.onOpen, required this.goTab});
  final void Function(J job) onOpen;
  final void Function(int) goTab;
  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  String f = 'all';
  static const filters = [
    MapEntry('all', 'הכל'), MapEntry('fixed', 'מחיר קבוע'), MapEntry('urgent', 'דחוף'), MapEntry('onsite', 'אצל הלקוח'),
    MapEntry('delivery', 'משלוחים'), MapEntry('remote', 'מרחוק'), MapEntry('phone', 'בטלפון'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProStore.i,
      builder: (ctx, _) {
        final s = ProStore.i;
        final list = s.feed.where((j) => f == 'all' || (f == 'fixed' ? j['clientPrice'] != null : f == 'urgent' ? j['urgency'] == 'urgent' : j['mode'] == f)).toList();
        return RefreshIndicator(
          onRefresh: s.load,
          child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
            ChipsRow(items: filters, value: f, onPick: (v) => setState(() => f = v)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              asList(s.me['categories']).isEmpty
                  ? Empty(icon: Icons.layers_rounded, title: 'בחרו תחומים כדי לראות עבודות',
                      action: FilledButton(onPressed: () => widget.goTab(3), child: const Text('בחירת תחומים')))
                  : Empty(icon: Icons.inbox_rounded, title: s.feed.isEmpty ? 'אין כרגע קריאות שמתאימות לך' : 'אין קריאות בסינון הזה',
                      text: s.available ? 'נודיע כשתגיע אחת.' : 'סמנו שאתם זמינים במסך "היום".'),
            for (final j in list)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Box(
                  onTap: () => widget.onOpen(j),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      catTile(j['categoryId']?.toString(), size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(Cats.name(j['categoryId']?.toString()), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text('${modeLabel[j['mode']] ?? ''}${j['distanceKm'] != null ? ' · ${j['distanceKm']} ק״מ' : ''} · ${dayLabel(j['createdAt'])}',
                              style: TextStyle(color: Pal.muted, fontSize: 12)),
                        ]),
                      ),
                      if (j['urgency'] == 'urgent') Tag('דחוף', color: Pal.hot, bg: Pal.hotSoft),
                    ]),
                    const SizedBox(height: 8),
                    Text(j['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: j['clientPrice'] != null
                            ? Text('הלקוח משלם ${ils(j['clientPrice'])}', style: TextStyle(color: Pal.brand, fontWeight: FontWeight.w800, fontSize: 16))
                            : Text('נשארו ${j['offersLeft'] ?? ''} מקומות להצעות', style: TextStyle(color: Pal.muted, fontSize: 13)),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                        onPressed: () => widget.onOpen(j),
                        icon: Icon(j['clientPrice'] != null ? Icons.check_rounded : Icons.send_rounded, size: 18),
                        label: Text(j['clientPrice'] != null ? 'לאשר' : 'להציע מחיר'),
                      ),
                    ]),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

// ---- my jobs
class JobsTab extends StatefulWidget {
  const JobsTab({super.key, required this.goTab});
  final void Function(int) goTab;
  @override
  State<JobsTab> createState() => _JobsTabState();
}

String bucketOf(J j) {
  final my = asMap(j['myOffer']);
  if (my['status'] == 'rejected') return 'lost';
  final s = j['status'];
  if (s == 'assigned') return 'won';
  if (s == 'en_route' || s == 'picked_up') return 'road';
  if (s == 'arrived' || s == 'in_progress') return 'work';
  if (s == 'open' || s == 'completed') return 'wait';
  return 'done';
}

class _JobsTabState extends State<JobsTab> {
  String f = 'all';
  static const order = ['won', 'road', 'work', 'wait', 'done', 'lost'];
  static const names = {'all': 'הכל', 'won': 'נבחרו בי', 'road': 'בדרך', 'work': 'בטיפול', 'wait': 'ממתינות ללקוח', 'done': 'נסגרו', 'lost': 'נדחו'};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProStore.i,
      builder: (ctx, _) {
        final s = ProStore.i;
        final list = s.jobs.where((j) => f == 'all' || bucketOf(j) == f).toList()
          ..sort((a, b) {
            final c = order.indexOf(bucketOf(a)).compareTo(order.indexOf(bucketOf(b)));
            return c != 0 ? c : (asNum(b['createdAt']) ?? 0).compareTo(asNum(a['createdAt']) ?? 0);
          });
        final chips = [
          for (final k in ['all', ...order])
            MapEntry(k, k == 'all' ? names[k]! : '${names[k]}${s.jobs.where((j) => bucketOf(j) == k).isNotEmpty ? ' · ${s.jobs.where((j) => bucketOf(j) == k).length}' : ''}'),
        ];
        return RefreshIndicator(
          onRefresh: s.load,
          child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
            ChipsRow(items: chips, value: f, onPick: (v) => setState(() => f = v)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Empty(
                icon: Icons.work_outline_rounded,
                title: s.jobs.isEmpty ? 'עוד לא שלחתם הצעות' : 'אין עבודות במצב הזה',
                text: s.jobs.isEmpty ? 'קריאות פתוחות מחכות בלשונית קריאות.' : null,
                action: s.jobs.isEmpty ? FilledButton(onPressed: () => widget.goTab(1), child: const Text('לקריאות')) : null,
              ),
            for (final j in list) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: JobCard(job: j)),
          ]),
        );
      },
    );
  }
}

class JobCard extends StatefulWidget {
  const JobCard({super.key, required this.job});
  final J job;
  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  final log = TextEditingController();
  bool busy = false;

  Future<void> _addLog() async {
    if (log.text.trim().isEmpty) return;
    try {
      await Api.post('/api/jobs/${widget.job['id']}/log', {'text': log.text.trim()});
      log.clear();
      if (mounted) toast(context, 'נוסף לתיעוד');
      await ProStore.i.load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job, my = asMap(j['myOffer']);
    final lost = my['status'] == 'rejected', accepted = my['status'] == 'accepted';
    final nx = nextOf(j);
    final physical = ['onsite', 'delivery'].contains(j['mode']);
    final done = accepted && ['completed', 'closed_done'].contains(j['status']);
    final pay = asMap(j['proPayment']);
    return Opacity(
      opacity: lost ? .55 : 1,
      child: Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            catTile(j['categoryId']?.toString(), size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(j['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text('${Cats.name(j['categoryId']?.toString())} · ${modeLabel[j['mode']] ?? ''}', style: TextStyle(color: Pal.muted, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Tag(lost ? 'הלקוח בחר הצעה אחרת' : proStatus[j['status']] ?? j['status'].toString(),
                color: j['status'] == 'closed_done' ? Pal.ok : null, bg: j['status'] == 'closed_done' ? Pal.okSoft : null),
            Text('${my['instant'] == true ? 'מחיר הלקוח' : 'ההצעה שלך'}: ${my['price'] != null ? ils(my['price']) : 'מחיר אחרי בדיקה'}', style: TextStyle(color: Pal.muted, fontSize: 13)),
          ]),
          mediaStrip(j['media']),
          if (j['phone'] != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => callPhone(j['phone']?.toString()), icon: const Icon(Icons.phone_rounded), label: Text(showPhone(j['phone']?.toString()))),
          ],
          if (j['address'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.place_rounded, size: 18, color: Pal.muted),
                const SizedBox(width: 6),
                Expanded(child: Text('${j['dropoff'] != null ? 'איסוף: ' : ''}${j['address']}')),
                if (physical && j['location'] != null) TextButton.icon(onPressed: () => waze(j['location']), icon: const Icon(Icons.navigation_rounded, size: 16), label: const Text('Waze')),
              ]),
            ),
          if (asMap(j['dropoff'])['address'] != null)
            Row(children: [
              Icon(Icons.flag_rounded, size: 18, color: Pal.muted),
              const SizedBox(width: 6),
              Expanded(child: Text('מסירה: ${asMap(j['dropoff'])['address']}')),
              if (asMap(j['dropoff'])['location'] != null)
                TextButton.icon(onPressed: () => waze(asMap(j['dropoff'])['location']), icon: const Icon(Icons.navigation_rounded, size: 16), label: const Text('Waze')),
            ]),
          if (asMap(j['escrow'])['payout'] != null) _note(Icons.check_rounded, 'שולם לך ${ils(asMap(j['escrow'])['payout'])}', Pal.ok),
          if (pay.isNotEmpty) _note(Icons.check_rounded, 'שולם לך ${ils(pay['amount'])} · ${payLabels[pay['method']] ?? ''}', Pal.ok),
          for (final l in asList(j['workLog'])) _note(Icons.notes_rounded, l['text']?.toString() ?? '', Pal.muted),
          if (accepted && nx != null && j['status'] != 'booking_failed') ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: log, decoration: const InputDecoration(hintText: 'תיעוד: מה עשיתם, מה צריך', isDense: true))),
              const SizedBox(width: 8),
              OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(70, 48)), onPressed: _addLog, child: const Text('הוספה')),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await advanceJob(context, j);
                      if (mounted) setState(() => busy = false);
                    },
              icon: const Icon(Icons.check_rounded),
              label: Text(nx[1]),
            ),
          ],
          if (done && j['paymentMode'] == 'direct' && pay.isEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => recordPayment(context, j),
              icon: const Icon(Icons.payments_rounded),
              label: const Text('לרשום כמה שולם ואיך'),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _note(IconData icon, String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(color: color == Pal.muted ? null : color, fontWeight: color == Pal.muted ? null : FontWeight.w700))),
        ]),
      );
}

/// After a job paid directly: how much and how (for the earnings history).
Future<void> recordPayment(BuildContext context, J j) async {
  final amount = TextEditingController(text: (asNum(asMap(j['myOffer'])['price']) ?? '').toString());
  var method = 'cash';
  await openSheet<void>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(ctx, 'כמה שולם ואיך'),
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'סכום', suffixText: 'ש״ח')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in ['cash', 'bit', 'transfer', 'card', 'other'])
            ChoiceChip(label: Text(payLabels[m]!), selected: method == m, onSelected: (_) => set(() => method = m)),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            try {
              await Api.post('/api/jobs/${j['id']}/paid', {'method': method, 'amount': asNum(amount.text.trim()) ?? 0});
              await ProStore.i.load();
              if (ctx.mounted) Navigator.pop(ctx);
            } on ApiError catch (e) {
              if (ctx.mounted) toast(ctx, e.message, err: true);
            }
          },
          child: const Text('שמירה'),
        ),
      ]),
    ),
  );
}

/// Opens the offer sheet from anywhere (feed card long-press, etc.).
Future<void> quickOffer(BuildContext context, J j) async {
  final sent = await offerSheet(context, j);
  if (sent == true && context.mounted) toast(context, 'ההצעה נשלחה');
}
