import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/map.dart';
import '../core/ui.dart';
import 'jobs.dart';
import 'pro_app.dart';

/// Wolt Partner style: the map with my area and the requests around me, and one panel at
/// the bottom: go available, or (on a job) the trip card with the next step.
class TodayTab extends StatefulWidget {
  const TodayTab({super.key, required this.goTab, required this.onOpen});
  final void Function(int) goTab;
  final void Function(J job) onOpen;
  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  final ctl = MapController();
  bool ready = false, busy = false;
  String fitted = '';

  void _fit(ProStore s, LatLng center, LatLng? target) {
    if (!ready) return;
    final t = s.trip;
    final key = target != null ? 'trip${t?['id']}${t?['status']}' : 'area${s.me['radiusKm']}';
    if (key == fitted) return;
    fitted = key;
    if (target != null) {
      ctl.fitCamera(CameraFit.bounds(bounds: LatLngBounds(center, target), padding: const EdgeInsets.fromLTRB(50, 90, 50, 320), maxZoom: 16));
    } else {
      final km = (asNum(s.me['radiusKm']) ?? 10).toDouble();
      final d = km / 111.0;
      ctl.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(LatLng(center.latitude - d, center.longitude - d), LatLng(center.latitude + d, center.longitude + d)),
        padding: const EdgeInsets.fromLTRB(30, 70, 30, 260),
      ));
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() => busy = true);
    try {
      await ProStore.i.setAvailable(on);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProStore.i,
      builder: (ctx, _) {
        final s = ProStore.i;
        final me = toLatLng(s.location) ?? const LatLng(32.0853, 34.7818);
        final trip = s.trip;
        final physical = trip != null && ['onsite', 'delivery'].contains(trip['mode']);
        final target = physical ? toLatLng(tripTarget(trip)['loc']) : null;
        final pins = trip != null ? <J>[] : s.feed.where((j) => j['location'] != null && ['onsite', 'delivery'].contains(j['mode'])).toList();
        final radius = (asNum(s.me['radiusKm']) ?? 10).toDouble();
        WidgetsBinding.instance.addPostFrameCallback((_) => _fit(s, me, target));
        return Stack(children: [
          FlutterMap(
            mapController: ctl,
            options: MapOptions(
              initialCenter: me,
              initialZoom: 12,
              onMapReady: () {
                ready = true;
                _fit(s, me, target);
              },
            ),
            children: [
              tiles(),
              if (trip == null)
                CircleLayer(circles: [
                  CircleMarker(
                    point: me,
                    radius: radius * 1000,
                    useRadiusInMeter: true,
                    color: Pal.brand.withValues(alpha: .06),
                    borderColor: Pal.brand.withValues(alpha: .7),
                    borderStrokeWidth: 1.5,
                  ),
                ]),
              if (target != null)
                PolylineLayer(polylines: [
                  Polyline(points: [me, target], color: Pal.brand, strokeWidth: 3, pattern: StrokePattern.dashed(segments: const [8, 8])),
                ]),
              MarkerLayer(markers: [
                for (final j in pins)
                  if (toLatLng(j['location']) != null)
                    Marker(
                      point: toLatLng(j['location'])!,
                      width: j['clientPrice'] != null ? 84 : 30,
                      height: j['clientPrice'] != null ? 34 : 30,
                      child: GestureDetector(onTap: () => widget.onOpen(j), child: _pin(j)),
                    ),
                if (target != null) Marker(point: target, width: 44, height: 44, alignment: Alignment.topCenter, child: pinMarker(Colors.white)),
                Marker(point: me, width: 26, height: 26, child: _me(s.available)),
              ]),
            ],
          ),
          attribution(),
          Positioned(
            top: 10,
            right: 12,
            left: 64,
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(Icons.radar_rounded, 'רדיוס ${radius.round()} ק״מ'),
              _chip(Icons.inbox_rounded, s.feed.isEmpty ? 'אין קריאות כרגע' : '${s.feed.length} קריאות פתוחות'),
            ]),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              backgroundColor: Pal.card,
              foregroundColor: Pal.ink,
              onPressed: () {
                fitted = '';
                _fit(s, me, target);
              },
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
          Positioned(left: 10, right: 10, bottom: 10, child: trip != null ? TripCard(job: trip, goTab: widget.goTab) : _panel(s)),
        ]);
      },
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Pal.card.withValues(alpha: .92), borderRadius: BorderRadius.circular(20), border: Border.all(color: Pal.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Pal.muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: Pal.ink, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _pin(J j) {
    if (j['clientPrice'] != null) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Pal.brand, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 8)]),
        child: Text(ils(j['clientPrice']), style: TextStyle(color: Pal.onBtn, fontWeight: FontWeight.w800, fontSize: 13)),
      );
    }
    final hot = j['urgency'] == 'urgent';
    return Container(
      decoration: BoxDecoration(
        color: hot ? Pal.hot : Pal.brand,
        shape: BoxShape.circle,
        border: Border.all(color: Pal.bg, width: 3),
        boxShadow: [BoxShadow(color: (hot ? Pal.hot : Pal.brand).withValues(alpha: .6), blurRadius: 10)],
      ),
    );
  }

  Widget _me(bool on) => Container(
        decoration: BoxDecoration(
          color: on ? Pal.brand : Pal.muted,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [BoxShadow(color: (on ? Pal.brand : Pal.muted).withValues(alpha: .5), blurRadius: 12, spreadRadius: 4)],
        ),
      );

  Widget _panel(ProStore s) {
    final on = s.available;
    final rows = s.earnRows('today');
    final notes = <(String, int, String)>[
      if (asList(s.me['categories']).isEmpty) ('עוד לא בחרתם תחומים', 3, 'בחירה'),
      if (s.location == null) ('אין מיקום. אפשרו גישה למיקום', 3, 'עדכון'),
      if (s.cfg['leadFees'] == true && (asNum(s.me['balance']) ?? 0) < 10) ('הקרדיט נמוך: ${ils(s.me['balance'])}', 4, 'טעינה'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Pal.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Pal.line),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, -6))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (on)
          Row(children: [
            _Pulse(color: Pal.ok),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('זמינים · מחפשים קריאות', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('קריאה חדשה תקפוץ כאן עם צליל, גם כשהאפליקציה ברקע', style: TextStyle(fontSize: 12, color: Pal.muted)),
              ]),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(90, 44)),
              onPressed: busy ? null : () => _toggle(false),
              child: const Text('הפסקה'),
            ),
          ])
        else ...[
          const Text('אתם לא זמינים', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('כשתהיו זמינים, קריאות באזור שלכם יקפצו עם צליל', style: TextStyle(color: Pal.muted, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
            onPressed: busy ? null : () => _toggle(true),
            icon: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.power_settings_new_rounded),
            label: const Text('להתחיל לקבל קריאות', style: TextStyle(fontSize: 18)),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          _kpi('הכנסות היום', ils(s.earnTotal(rows)), () => widget.goTab(4)),
          const SizedBox(width: 8),
          _kpi('עבודות היום', '${rows.length}', () => widget.goTab(4)),
          const SizedBox(width: 8),
          _kpi('דירוג', (asNum(s.me['ratingCount']) ?? 0) > 0 ? '★ ${s.me['ratingAvg']}' : 'חדש', () => widget.goTab(2)),
        ]),
        if (notes.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            decoration: BoxDecoration(color: Pal.warnSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Pal.warn),
              const SizedBox(width: 8),
              Expanded(child: Text(notes.first.$1, style: TextStyle(color: Pal.warn, fontWeight: FontWeight.w600))),
              TextButton(onPressed: () => widget.goTab(notes.first.$2), child: Text(notes.first.$3)),
            ]),
          ),
      ]),
    );
  }

  Widget _kpi(String label, String value, VoidCallback onTap) => Expanded(
        child: Material(
          color: Pal.card2,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Column(children: [
                Text(label, style: TextStyle(fontSize: 11, color: Pal.muted)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      );
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});
  final Color color;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: AnimatedBuilder(
          animation: a,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            Container(
              width: 10 + 12 * a.value,
              height: 10 + 12 * a.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: .5 * (1 - a.value))),
            ),
            Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ]),
        ),
      );
}
