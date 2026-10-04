import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/ui.dart';
import 'background.dart';
import 'pro_app.dart';

/// Full-screen new request (Wolt Partner style): accept in one tap; if someone else was
/// faster, it says so ("missed").
class JobPopup extends StatefulWidget {
  const JobPopup({super.key, required this.job, this.ring = false});
  final J job;
  final bool ring;
  @override
  State<JobPopup> createState() => _JobPopupState();
}

class _JobPopupState extends State<JobPopup> {
  String state = 'open'; // open | won | missed | sent
  J won = {};
  bool busy = false;
  int left = 45;
  Timer? tick;

  J get j => widget.job;
  bool get fixed => j['clientPrice'] != null;

  @override
  void initState() {
    super.initState();
    ProStore.i.markSeen(j['id'].toString());
    ProStore.i.addListener(_watch);
    if (widget.ring) {
      SystemSound.play(SystemSoundType.alert);
      ringOnce(j); // notification sound + vibration (louder than the system click)
      HapticFeedback.heavyImpact();
      tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state != 'open') return;
        if (left <= 1) {
          tick?.cancel();
          if (mounted) Navigator.pop(context);
        } else {
          setState(() => left -= 1);
          if (left % 10 == 0) HapticFeedback.mediumImpact();
        }
      });
    }
  }

  @override
  void dispose() {
    tick?.cancel();
    ProStore.i.removeListener(_watch);
    super.dispose();
  }

  // The request left the feed while it was on screen: someone else took it.
  void _watch() {
    if (state != 'open' || busy) return;
    final still = ProStore.i.feed.any((x) => x['id'] == j['id']);
    if (!still && mounted) setState(() => state = 'missed');
  }

  Future<void> _take() async {
    setState(() => busy = true);
    try {
      won = asMap(await Api.post('/api/jobs/${j['id']}/take', {}));
      HapticFeedback.heavyImpact();
      setState(() => state = 'won');
      ProStore.i.load();
    } on ApiError catch (e) {
      if (e.code == 'taken' || e.code == 'closed') {
        setState(() => state = 'missed');
      } else if (mounted) {
        toast(context, e.message, err: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _offer() async {
    final sent = await offerSheet(context, j);
    if (sent == true && mounted) setState(() => state = 'sent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(state == 'won' ? 'העבודה שלך' : state == 'missed' ? 'פספסת' : 'קריאה חדשה'),
        actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), tooltip: 'סגירה')],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 18), children: _content())),
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 16), child: Column(mainAxisSize: MainAxisSize.min, children: _buttons())),
        ]),
      ),
    );
  }

  List<Widget> _content() {
    final km = j['distanceKm'];
    final head = <Widget>[
      if (state == 'open' && widget.ring)
        Center(
          child: SizedBox(
            width: 86,
            height: 86,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(width: 86, height: 86, child: CircularProgressIndicator(value: left / 45, strokeWidth: 6, color: Pal.brand, backgroundColor: Pal.line)),
              Text('$left', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      if (state == 'won')
        Center(child: CircleAvatar(radius: 44, backgroundColor: Pal.okSoft, child: Icon(Icons.check_rounded, size: 54, color: Pal.ok))),
      if (state == 'missed')
        Column(children: [
          CircleAvatar(radius: 44, backgroundColor: Pal.hotSoft, child: Icon(Icons.timer_off_rounded, size: 50, color: Pal.hot)),
          const SizedBox(height: 12),
          const Text('מישהו אישר לפניך', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('בפעם הבאה כדאי לאשר מהר. קריאות חדשות יקפצו כאן.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
        ]),
      if (state == 'sent')
        Column(children: [
          CircleAvatar(radius: 44, backgroundColor: Pal.okSoft, child: Icon(Icons.send_rounded, size: 46, color: Pal.ok)),
          const SizedBox(height: 12),
          const Text('ההצעה נשלחה', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('נודיע לך כשהלקוח יבחר.', style: TextStyle(color: Pal.muted)),
        ]),
      const SizedBox(height: 16),
    ];
    if (state == 'missed' || state == 'sent') return head;
    final src = state == 'won' ? won : j;
    return [
      ...head,
      Row(children: [
        catTile(j['categoryId']?.toString(), size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Cats.name(j['categoryId']?.toString()), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            Text('${modeLabel[j['mode']] ?? ''}${km != null ? ' · $km ק״מ ממך' : ''}', style: TextStyle(color: Pal.muted)),
          ]),
        ),
        if (j['urgency'] == 'urgent') Tag('דחוף', icon: Icons.local_fire_department_rounded, color: Pal.hot, bg: Pal.hotSoft),
      ]),
      const SizedBox(height: 16),
      Box(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(j['description']?.toString() ?? '', style: const TextStyle(fontSize: 18, height: 1.4)),
          mediaStrip(j['media']),
        ]),
      ),
      if (fixed)
        Box(
          color: Pal.brandSoft,
          border: Pal.brand.withValues(alpha: .5),
          child: Row(children: [
            Expanded(child: Text('הלקוח משלם', style: TextStyle(color: Pal.muted, fontSize: 16))),
            Text(ils(j['clientPrice']), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Pal.brand)),
          ]),
        )
      else
        Box(
          child: Row(children: [
            Icon(Icons.groups_rounded, color: Pal.muted),
            const SizedBox(width: 10),
            Expanded(child: Text('הלקוח מחכה להצעות מחיר · נשארו ${j['offersLeft'] ?? ''} מקומות', style: const TextStyle(fontSize: 16))),
          ]),
        ),
      if (state == 'won') ...[
        if (src['address'] != null)
          Box(
            child: Row(children: [
              Icon(Icons.place_rounded, color: Pal.brand),
              const SizedBox(width: 10),
              Expanded(child: Text(src['address'].toString(), style: const TextStyle(fontSize: 16))),
            ]),
          ),
        Row(children: [
          if (src['location'] != null)
            Expanded(child: OutlinedButton.icon(onPressed: () => waze(src['location']), icon: const Icon(Icons.navigation_rounded), label: const Text('Waze'))),
          if (src['location'] != null && src['phone'] != null) const SizedBox(width: 10),
          if (src['phone'] != null)
            Expanded(child: OutlinedButton.icon(onPressed: () => callPhone(src['phone']?.toString()), icon: const Icon(Icons.phone_rounded), label: const Text('ללקוח'))),
        ]),
      ],
    ];
  }

  List<Widget> _buttons() {
    if (state == 'won') {
      return [FilledButton.icon(onPressed: () => Navigator.pop(context, 'today'), icon: const Icon(Icons.work_rounded), label: const Text('לעבודה'))];
    }
    if (state == 'missed' || state == 'sent') {
      return [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('הבנתי'))];
    }
    return [
      if (fixed)
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: busy ? null : _take,
          icon: const Icon(Icons.check_rounded, size: 28),
          label: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)) : Text('לאשר ולקבל · ${ils(j['clientPrice'])}', style: const TextStyle(fontSize: 19)),
        )
      else
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: _offer,
          icon: const Icon(Icons.send_rounded),
          label: const Text('להציע מחיר', style: TextStyle(fontSize: 19)),
        ),
      const SizedBox(height: 8),
      Row(children: [
        if (fixed) Expanded(child: OutlinedButton(onPressed: _offer, child: const Text('הצעה במחיר אחר'))),
        if (fixed) const SizedBox(width: 10),
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('לדלג'))),
      ]),
    ];
  }
}

/// Send a price offer. Returns true when sent.
Future<bool?> offerSheet(BuildContext context, J j) {
  final price = TextEditingController();
  final eta = TextEditingController();
  final msg = TextEditingController();
  var later = false, busy = false;
  var err = '';
  final lead = asNum(j['leadPrice']) ?? 0;
  final paid = ProStore.i.cfg['leadFees'] == true && lead > 0;
  final needPrice = j['paymentMode'] == 'in_app';
  return openSheet<bool>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(ctx, 'הצעת מחיר'),
        Text(Cats.name(j['categoryId']?.toString()), style: TextStyle(color: Pal.muted)),
        const SizedBox(height: 12),
        TextField(
          controller: price,
          enabled: !later,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(labelText: 'המחיר', suffixText: 'ש״ח'),
        ),
        if (!needPrice)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: later,
            onChanged: (v) => set(() => later = v == true),
            title: const Text('מחיר אחרי בדיקה במקום'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final e in ['עכשיו', 'היום', 'מחר', 'השבוע'])
            ChoiceChip(label: Text(e), selected: eta.text == e, onSelected: (_) => set(() => eta.text = e)),
        ]),
        const SizedBox(height: 8),
        TextField(controller: eta, decoration: const InputDecoration(labelText: 'מתי אפשר להגיע')),
        const SizedBox(height: 10),
        TextField(controller: msg, maxLines: 2, decoration: const InputDecoration(labelText: 'הודעה ללקוח (לא חובה)')),
        if (paid)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('שליחת ההצעה עולה ${ils(lead)} מהקרדיט. יתרה: ${ils(ProStore.i.me['balance'])}', style: TextStyle(color: Pal.muted)),
          ),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: TextStyle(color: Pal.hot))),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final p = asNum(price.text.trim());
                  if (!later && (p == null || p <= 0)) {
                    set(() => err = needPrice ? 'כתבו מחיר' : 'כתבו מחיר, או סמנו "מחיר אחרי בדיקה"');
                    return;
                  }
                  set(() => busy = true);
                  try {
                    await Api.post('/api/jobs/${j['id']}/offers', {
                      'price': later ? null : p,
                      'eta': eta.text.trim().isEmpty ? null : eta.text.trim(),
                      'message': msg.text.trim(),
                    });
                    ProStore.i.load();
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on ApiError catch (e) {
                    set(() {
                      busy = false;
                      err = e.message;
                    });
                  }
                },
          icon: const Icon(Icons.send_rounded),
          label: const Text('שליחת ההצעה'),
        ),
      ]),
    ),
  );
}

/// Sound and vibration through the notification channel.
void ringOnce(J j) => Bg.alertJob(j, 'קריאה חדשה', j['description']?.toString() ?? '');
