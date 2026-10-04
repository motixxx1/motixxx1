import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/device.dart';

/// Native side of the pro app:
/// - while available (or on a job) a foreground service keeps the app running with a
///   persistent notification, shares the position, and lets new requests ring even when
///   the app is in the background or the screen is off;
/// - new requests show a loud notification with sound and vibration.
class Bg {
  static final _n = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static StreamSubscription<Position>? _sub;
  static J? last;
  static void Function(J loc)? onPosition;
  static void Function(String? payload)? onTap;

  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _n.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat')),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
      final android = _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'jobs',
        'קריאות חדשות',
        description: 'קריאה חדשה באזור שלכם',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ));
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Start sharing the position with a foreground service ("you're available").
  static Future<bool> start({required bool onJob}) async {
    if (!await locationAllowed()) return false;
    await _sub?.cancel();
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 4),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: onJob ? 'זריז · בעבודה' : 'זריז · זמינים לקריאות',
        notificationText: onJob ? 'הלקוח רואה אתכם על המפה' : 'נודיע מיד כשתגיע קריאה באזור שלכם',
        notificationIcon: const AndroidResource(name: 'ic_stat', defType: 'drawable'),
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    try {
      _sub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
        last = {'lat': p.latitude, 'lng': p.longitude};
        onPosition?.call(last!);
      }, onError: (_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  static bool get running => _sub != null;

  static Future<void> alertJob(J job, String title, String body) async {
    try {
      await _n.show(
        job['id'].hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jobs',
            'קריאות חדשות',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.message,
            playSound: true,
            enableVibration: true,
            ticker: 'קריאה חדשה',
            icon: '@drawable/ic_stat',
          ),
        ),
        payload: job['id']?.toString(),
      );
    } catch (_) {}
  }
}
