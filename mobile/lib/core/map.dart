import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'ui.dart';

LatLng? toLatLng(dynamic l) {
  final m = asMap(l);
  final lat = asNum(m['lat']), lng = asNum(m['lng']);
  return lat == null || lng == null ? null : LatLng(lat.toDouble(), lng.toDouble());
}

/// Map tiles: OpenStreetMap; the pro app shows them dark.
TileLayer tiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.promarket.app',
      maxZoom: 19,
      tileBuilder: isPro ? darkModeTileBuilder : null,
    );

Widget attribution() => Positioned(
      left: 6,
      bottom: 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Pal.card.withValues(alpha: .8), borderRadius: BorderRadius.circular(6)),
          child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Pal.muted)),
        ),
      ),
    );

/// Round marker with an icon (the pro, the customer, me).
Widget dotMarker(IconData icon, Color color, {double size = 44}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Icon(icon, color: Colors.white, size: size * .5),
    );

/// Destination pin.
Widget pinMarker(Color color, {double size = 40}) => Icon(Icons.location_on_rounded, color: color, size: size,
    shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3))]);
