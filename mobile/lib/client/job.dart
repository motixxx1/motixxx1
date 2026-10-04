import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/map.dart';
import '../core/ui.dart';
import 'client_app.dart';

// ---- plain-language status of a request
J? acceptedOffer(J j) => asList(j['offers']).where((o) => o['status'] == 'accepted').firstOrNull;
String proName(J j) => asMap(acceptedOffer(j)?['pro'])['name']?.toString() ?? 'המקצוען';
bool needsMe(J j) =>
    (j['status'] == 'open' && asList(j['offers']).isNotEmpty) || j['status'] == 'completed' || (j['status'] == 'closed_done' && j['rated'] != true);
bool isOpenJob(J j) => !['closed_done', 'booking_failed'].contains(j['status']);
bool trackOn(J j) => j['tracking'] != null && ['en_route', 'picked_up', 'arrived'].contains(j['status']);

/// (text, color) for the status line.
(String, Color) statusOf(J j) {
  final n = asList(j['offers']).length, p = proName(j), del = j['mode'] == 'delivery';
  switch (j['status']) {
    case 'open':
      if (n > 0) return (n == 1 ? 'קיבלתם הצעה אחת' : 'קיבלתם $n הצעות', Pal.brandInk);
      return (j['clientPrice'] != null ? 'מחכים שמקצוען יאשר את המחיר' : 'מחכים להצעות ממקצוענים', Pal.warn);
    case 'assigned':
      return (acceptedOffer(j)?['instant'] == true ? '$p אישר וקיבל את העבודה' : 'בחרתם ב$p. מחכים שיתחיל', Pal.ink);
    case 'en_route':
      return (del ? '$p בדרך לאיסוף' : '$p בדרך אליכם', Pal.ink);
    case 'picked_up':
      return ('$p אסף ובדרך אליכם', Pal.ink);
    case 'arrived':
      return (del ? '$p הגיע אליכם' : '$p הגיע', Pal.brandInk);
    case 'in_progress':
      return ('$p עובד על זה', Pal.ink);
    case 'completed':
      return ('$p סיים. אשרו שהכל תקין', Pal.brandInk);
    case 'closed_done':
      return ('הסתיים', Pal.ok);
    case 'booking_failed':
      return ('ההזמנה לא אושרה. הכסף הוחזר', Pal.hot);
  }
  return (j['status'].toString(), Pal.ink);
}

class StatusLine extends StatelessWidget {
  const StatusLine(this.job, {super.key, this.size = 17});
  final J job;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (text, color) = statusOf(job);
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color == Pal.ink ? Pal.brand : color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: size * fs, fontWeight: FontWeight.w700, color: color))),
    ]);
  }
}

class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.job});
  final J job;
  @override
  Widget build(BuildContext context) {
    final s = job['status'];
    return Box(
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => JobScreen(id: job['id'].toString()))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          catTile(job['categoryId']?.toString(), size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(Cats.name(job['categoryId']?.toString()), style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w700))),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(job['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Pal.muted, fontSize: 16 * fs)),
        ),
        StatusLine(job),
        if (needsMe(job))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => JobScreen(id: job['id'].toString()))),
              child: Text(s == 'open' ? 'לראות את ההצעות' : s == 'completed' ? 'לאשר' : 'לדרג'),
            ),
          ),
      ]),
    );
  }
}

/// One request: where it stands, live map while the pro is on the way, offers and actions.
class JobScreen extends StatefulWidget {
  const JobScreen({super.key, required this.id});
  final String id;
  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  Timer? fast;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    // While the pro is on the way the map refreshes every 3 seconds.
    fast = Timer.periodic(const Duration(seconds: 3), (_) {
      final j = ClientStore.i.job(widget.id);
      if (j != null && trackOn(j)) ClientStore.i.load();
    });
  }

  @override
  void dispose() {
    fast?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<dynamic> Function() f, String done) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await f();
      if (mounted) toast(context, done);
      await ClientStore.i.load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _accept(J j, J o) async {
    final p = asMap(o['pro']);
    final ok = await confirmSheet(context,
        title: 'לבחור ב${p['name']}?',
        text: [
          if (o['price'] != null) 'מחיר: ${ils(o['price'])}',
          if (o['eta'] != null && o['eta'].toString().isNotEmpty) 'מתי: ${o['eta']}',
          'הטלפון והכתובת שלכם יישלחו אליו. משלמים לו ישירות כשהעבודה נגמרת.',
        ].join('\n'),
        ok: 'כן, לבחור בו');
    if (!ok) return;
    await _act(() => Api.post('/api/jobs/${j['id']}/offers/${o['id']}/accept', {}), 'בחרתם. הוא יקבל הודעה');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ClientStore.i,
      builder: (ctx, _) {
        final j = ClientStore.i.job(widget.id);
        return Scaffold(
          appBar: AppBar(title: const Text('הקריאה שלי')),
          body: j == null ? const Center(child: CircularProgressIndicator()) : _body(j),
        );
      },
    );
  }

  Widget _body(J j) {
    final status = j['status'];
    final offers = asList(j['offers']);
    final accepted = acceptedOffer(j);
    final log = asList(j['workLog']);
    return RefreshIndicator(
      onRefresh: ClientStore.i.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 14), child: StatusLine(j, size: 23)),
          if (trackOn(j)) LiveMap(job: j),
          if (status == 'open' && offers.isEmpty)
            Box(
              child: Column(children: [
                CircleAvatar(radius: 34, backgroundColor: Pal.okSoft, child: Icon(Icons.check_rounded, size: 40, color: Pal.ok)),
                const SizedBox(height: 10),
                Text('הקריאה נשלחה', style: TextStyle(fontSize: 21 * fs, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  j['clientPrice'] != null
                      ? 'קבעתם ${ils(j['clientPrice'])}. המקצוען הראשון שיאשר יקבל את העבודה, ונודיע לכם כאן.'
                      : 'מקצוענים באזור קיבלו אותה. ההצעות יופיעו כאן.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Pal.muted, fontSize: 16 * fs),
                ),
              ]),
            ),
          if (status == 'completed')
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Pal.ok),
                onPressed: busy ? null : () => _act(() => Api.post('/api/jobs/${j['id']}/confirm', {}), 'תודה. העבודה אושרה'),
                icon: const Icon(Icons.check_rounded),
                label: const Text('הכל תקין, סיימנו'),
              ),
            ),
          if (status == 'closed_done' && j['rated'] != true)
            Box(
              child: Column(children: [
                Text('איך היה?', style: TextStyle(fontSize: 21 * fs, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var n = 1; n <= 5; n++)
                    IconButton(
                      iconSize: 44,
                      onPressed: busy ? null : () => _act(() => Api.post('/api/jobs/${j['id']}/rate', {'score': n}), 'תודה על הדירוג'),
                      icon: Icon(Icons.star_rounded, color: Pal.brand),
                    ),
                ]),
              ]),
            ),
          if (status == 'open' && offers.isNotEmpty) ...[
            const SectionTitle('ההצעות שקיבלתם'),
            for (final o in offers) _offer(j, o, open: true),
          ],
          if (accepted != null) ...[
            SectionTitle(accepted['instant'] == true ? 'המקצוען שלכם' : 'המקצוען שבחרתם'),
            _offer(j, accepted, open: false),
          ],
          if (status != 'booking_failed') ...[
            const SectionTitle('איפה זה עומד'),
            Box(child: Timeline(job: j)),
          ],
          if (log.isNotEmpty) ...[
            const SectionTitle('מה נעשה'),
            Box(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final l in log)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check_rounded, color: Pal.ok),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${l['text'] ?? ''}${asList(l['photos']).isNotEmpty ? ' · צורפו תמונות' : ''}', style: TextStyle(fontSize: 16 * fs))),
                    ]),
                  ),
              ]),
            ),
          ],
          const SectionTitle('מה ביקשתם'),
          Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Cats.name(j['categoryId']?.toString()), style: TextStyle(fontSize: 19 * fs, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(j['description']?.toString() ?? '', style: TextStyle(fontSize: 16 * fs)),
              mediaStrip(j['media']),
              if (j['address'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Icon(Icons.place_rounded, color: Pal.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(j['dropoff'] != null ? 'איסוף: ${j['address']}\nמסירה: ${asMap(j['dropoff'])['address'] ?? ''}' : j['address'].toString())),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${j['urgency'] == 'urgent' ? 'דחוף' : 'לא דחוף'} · ${modeLabel[j['mode']] ?? ''}', style: TextStyle(color: Pal.muted)),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _offer(J j, J o, {required bool open}) {
    final p = asMap(o['pro']);
    final won = o['status'] == 'accepted';
    final rating = p['ratingCount'] != null && (asNum(p['ratingCount']) ?? 0) > 0 ? '★ ${p['ratingAvg']} · ${p['ratingCount']} דירוגים' : 'מקצוען חדש';
    return Box(
      border: won ? Pal.ok : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(radius: 26, backgroundColor: Pal.brandSoft, child: Icon(Icons.person_rounded, color: Pal.brandInk, size: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name']?.toString() ?? '', style: TextStyle(fontSize: 20 * fs, fontWeight: FontWeight.w700)),
              Text(rating, style: TextStyle(color: Pal.muted)),
            ]),
          ),
          Text(o['price'] != null ? ils(o['price']) : 'מחיר\nאחרי בדיקה',
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: (o['price'] != null ? 24 : 14) * fs, fontWeight: FontWeight.w800, color: o['price'] != null ? Pal.ink : Pal.muted)),
        ]),
        if ((o['eta'] ?? '').toString().isNotEmpty) _line(Icons.schedule_rounded, 'מתי: ${o['eta']}'),
        if ((o['message'] ?? '').toString().isNotEmpty) _line(Icons.chat_bubble_outline_rounded, o['message'].toString()),
        if (won) _line(Icons.check_rounded, o['instant'] == true ? 'אישר את המחיר שלכם' : 'בחרתם בו', color: Pal.ok),
        if (open && !won) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : () => _accept(j, o), child: Text('לבחור ב${p['name']}')),
        ],
        if (p['phone'] != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => callPhone(p['phone']?.toString()),
            icon: const Icon(Icons.phone_rounded),
            label: Text(won ? 'להתקשר ל${p['name']}' : 'להתקשר קודם'),
          ),
        ],
      ]),
    );
  }

  Widget _line(IconData icon, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22, color: color ?? Pal.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 16 * fs, color: color, fontWeight: color != null ? FontWeight.w700 : null))),
        ]),
      );
}

/// Steps of the request; done ones are ticked, the current one is highlighted.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.job});
  final J job;
  @override
  Widget build(BuildContext context) {
    final mode = job['mode'], status = job['status'];
    final del = mode == 'delivery', remote = mode == 'remote' || mode == 'phone';
    final labels = del
        ? ['הקריאה נשלחה', 'נבחר שליח', 'בדרך לאיסוף', 'אסף, בדרך אליכם', 'הגיע', 'נמסר']
        : remote
            ? ['הקריאה נשלחה', 'נבחר מקצוען', 'בטיפול', 'הסתיים']
            : ['הקריאה נשלחה', 'נבחר מקצוען', 'בדרך אליכם', 'הגיע', 'בטיפול', 'הסתיים'];
    final pos = (del
            ? {'open': 1, 'assigned': 2, 'en_route': 2, 'picked_up': 3, 'arrived': 4, 'completed': 5, 'closed_done': 6}
            : remote
                ? {'open': 1, 'assigned': 2, 'in_progress': 2, 'completed': 3, 'closed_done': 4}
                : {'open': 1, 'assigned': 2, 'en_route': 2, 'arrived': 3, 'in_progress': 4, 'completed': 5, 'closed_done': 6})[status] ??
        0;
    final now = ['en_route', 'picked_up', 'arrived', 'in_progress'].contains(status);
    return Column(children: [
      for (var i = 0; i < labels.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < pos ? Pal.ok : (i == pos && now ? Pal.brand : Pal.card),
                border: Border.all(color: i < pos ? Pal.ok : (i == pos ? Pal.brand : Pal.line), width: i == pos ? 3 : 2),
                boxShadow: i == pos && now ? [BoxShadow(color: Pal.brandSoft, spreadRadius: 5)] : null,
              ),
              child: i < pos ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
            ),
            const SizedBox(width: 14),
            Text(labels[i],
                style: TextStyle(
                  fontSize: 17 * fs,
                  color: i <= pos ? Pal.ink : Pal.muted,
                  fontWeight: i == pos ? FontWeight.w800 : FontWeight.w500,
                )),
          ]),
        ),
    ]);
  }
}

/// The pro moving on a map, with arrival time. Like a delivery app.
class LiveMap extends StatefulWidget {
  const LiveMap({super.key, required this.job});
  final J job;
  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  final ctl = MapController();
  String fitted = '';
  bool ready = false;

  void _fit() {
    final t = asMap(widget.job['tracking']);
    final me = toLatLng(t), dest = toLatLng(t['toward']);
    if (!ready || me == null) return;
    final key = '${widget.job['id']}${widget.job['status']}';
    if (key == fitted) return;
    fitted = key;
    if (dest == null) {
      ctl.move(me, 15);
    } else {
      ctl.fitCamera(CameraFit.bounds(bounds: LatLngBounds(me, dest), padding: const EdgeInsets.fromLTRB(50, 110, 50, 40), maxZoom: 17));
    }
  }

  @override
  void didUpdateWidget(covariant LiveMap old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job, t = asMap(j['tracking']);
    final me = toLatLng(t), dest = toLatLng(t['toward']);
    if (me == null) return const SizedBox.shrink();
    final km = asNum(t['km']), eta = asNum(t['etaMin']);
    final dist = km == null ? '' : (km < 1 ? '${(km * 1000).round()} מטר' : '$km ק״מ');
    final name = proName(j);
    final arrived = j['status'] == 'arrived';
    return Container(
      height: 320,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Pal.line, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          mapController: ctl,
          options: MapOptions(
            initialCenter: me,
            initialZoom: 14,
            onMapReady: () {
              ready = true;
              _fit();
            },
          ),
          children: [
            tiles(),
            if (dest != null)
              PolylineLayer(polylines: [
                Polyline(points: [me, dest], color: Pal.brand, strokeWidth: 4, pattern: StrokePattern.dashed(segments: const [10, 8])),
              ]),
            MarkerLayer(markers: [
              if (dest != null) Marker(point: dest, width: 44, height: 44, alignment: Alignment.topCenter, child: pinMarker(const Color(0xFF1D1F2B))),
              Marker(point: me, width: 48, height: 48, child: dotMarker(Icons.person_rounded, Pal.brand)),
            ]),
          ],
        ),
        attribution(),
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Row(children: [
              if (arrived)
                Icon(Icons.check_circle_rounded, color: Pal.ok, size: 34)
              else if (eta != null)
                Text('$eta', style: TextStyle(fontSize: 32 * fs, fontWeight: FontWeight.w800, color: Pal.brandInk, height: 1)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(arrived ? '$name הגיע' : (eta != null ? 'דקות' : '$name בדרך'),
                      style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w700, color: const Color(0xFF1D1F2B))),
                  Text(
                    arrived
                        ? 'צאו לפגוש אותו'
                        : '$name ${j['status'] == 'picked_up' ? 'בדרך אליכם עם המשלוח' : j['mode'] == 'delivery' ? 'בדרך לאיסוף' : 'בדרך אליכם'}${dist.isNotEmpty ? ' · $dist' : ''}',
                    style: TextStyle(fontSize: 14 * fs, color: const Color(0xFF5E6375)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
