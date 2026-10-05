import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'api.dart';
import 'ui.dart';

/// Asks for location permission when needed. Returns true when the app may read the position.
Future<bool> locationAllowed() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}

/// The phone's position as {lat, lng}, or null.
Future<J?> currentLocation({bool precise = false}) async {
  if (!await locationAllowed()) return null;
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: precise ? LocationAccuracy.high : LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      ),
    );
    return {'lat': p.latitude, 'lng': p.longitude};
  } catch (_) {
    try {
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : {'lat': p.latitude, 'lng': p.longitude};
    } catch (_) {
      return null;
    }
  }
}

/// APKs downloaded from our server: offer the newer APK when the server says there is one.
/// (Google Play builds update through the store.)
Future<void> checkForUpdate(BuildContext context) async {
  if (!sideload) return;
  try {
    final v = asMap(await Api.get('/api/version'));
    final latest = asNum(v['apk'])?.toInt() ?? 0;
    final dismissed = Api.prefs.getInt('update_dismissed') ?? 0;
    if (latest <= appBuild || dismissed >= latest || !context.mounted) return;
    final go = await confirmSheet(context,
        title: 'גרסה חדשה של האפליקציה',
        text: 'יש גרסה חדשה. מורידים, מתקינים, וזהו. הנתונים והחשבון נשארים.',
        ok: 'להורדה');
    if (go) {
      await openLink(Api.url('/download/ProMarket-$appKind.apk'));
    } else {
      await Api.prefs.setInt('update_dismissed', latest);
    }
  } catch (_) {}
}
