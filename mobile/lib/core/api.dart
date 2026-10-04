import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Which app this build is: 'client' (customers) or 'pro' (pros, couriers, agents).
const appKind = String.fromEnvironment('APP', defaultValue: 'client');
bool get isPro => appKind == 'pro';

/// Build number of this APK (compared with the server's to offer a new version).
const appBuild = int.fromEnvironment('BUILD', defaultValue: 0);

/// Downloaded from GitHub (not from Google Play): may offer new APKs itself.
const sideload = bool.fromEnvironment('SIDELOAD', defaultValue: true);

const _primary = String.fromEnvironment('SERVER_URL', defaultValue: 'http://87.68.15.249:3000');
// Tried when the first address can't be reached (at home the router often won't loop back).
const _fallback = String.fromEnvironment('FALLBACK_URL', defaultValue: 'http://192.168.1.244:3000');

class ApiError implements Exception {
  ApiError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Hebrew text for the server's error codes.
const errText = <String, String>{
  'offline': 'אין חיבור לשרת. בדקו את האינטרנט ונסו שוב',
  'bad_phone': 'מספר הטלפון לא נכון',
  'bad_code': 'הקוד לא נכון',
  'code_expired': 'הקוד כבר לא בתוקף. בקשו קוד חדש',
  'too_soon': 'חכו רגע לפני שמבקשים קוד נוסף',
  'too_many_attempts': 'יותר מדי ניסיונות. בקשו קוד חדש',
  'bad_name': 'צריך שם',
  'bad_description': 'צריך לכתוב מה צריך',
  'bad_location': 'לא הצלחנו למצוא את הכתובת',
  'bad_dropoff': 'צריך כתובת איסוף וכתובת מסירה',
  'closed': 'הקריאה כבר נסגרה',
  'price_required': 'בתשלום מאובטח אפשר לבחור רק הצעה עם מחיר',
  'already_rated': 'כבר דירגתם',
  'active_jobs': 'יש עבודה בביצוע. סיימו אותה ואז אפשר למחוק',
  'payments_disabled': 'האפשרות הזו עוד לא פתוחה',
  'bad_price': 'מחיר לא תקין',
  'insufficient_credit': 'אין מספיק קרדיט',
  'full': 'כל המקומות להצעות כבר נתפסו',
  'already_offered': 'כבר שלחתם הצעה לקריאה הזו',
  'not_eligible': 'הקריאה לא מתאימה לתחומים או לרדיוס שלכם',
  'taken': 'מישהו אחר אישר לפניך',
  'no_price': 'לקריאה הזו אין מחיר קבוע',
  'bad_radius': 'רדיוס 1 עד 500 ק״מ',
  'bad_mode': 'בחרו לפחות אופן עבודה אחד',
  'signature_required': 'נדרשת חתימת לקוח',
  'empty_log': 'כתבו מה עשיתם',
  'bad_transition': 'אי אפשר לעבור לשלב הזה עכשיו',
  'bad_amount': 'סכום לא תקין',
  'too_large': 'הקובץ גדול מדי',
  'bad_type': 'אפשר לצרף רק תמונה',
  'unauthorized': 'צריך להתחבר מחדש',
  'forbidden': 'אין הרשאה',
  'not_found': 'לא נמצא',
};

/// Talks to the Zariz server. One instance for the whole app.
class Api {
  static late SharedPreferences prefs;
  static String? token;
  static String base = _primary;
  static void Function()? onLoggedOut;

  static Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token_$appKind');
    final saved = prefs.getString('server');
    if (saved != null && saved.isNotEmpty) base = saved;
  }

  static Future<void> setToken(String? t) async {
    token = t;
    if (t == null) {
      await prefs.remove('token_$appKind');
    } else {
      await prefs.setString('token_$appKind', t);
    }
  }

  static String url(String path) => path.startsWith('http') ? path : '$base$path';

  static Future<dynamic> get(String path) => _call('GET', path);
  static Future<dynamic> post(String path, [Object? body]) => _call('POST', path, body ?? const {});
  static Future<dynamic> put(String path, Object body) => _call('PUT', path, body);
  static Future<dynamic> delete(String path) => _call('DELETE', path);

  static Future<dynamic> _call(String method, String path, [Object? body]) async {
    http.Response r;
    try {
      r = await _send(base, method, path, body);
    } on ApiError {
      rethrow;
    } catch (_) {
      // Unreachable: try the other address once and stay on it if it answers.
      final other = base == _fallback ? _primary : _fallback;
      if (other.isEmpty || other == base) throw ApiError('offline', errText['offline']!);
      try {
        r = await _send(other, method, path, body);
        base = other;
      } catch (_) {
        throw ApiError('offline', errText['offline']!);
      }
    }
    dynamic data;
    try {
      data = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (r.statusCode == 401 && token != null) {
      await setToken(null);
      onLoggedOut?.call();
    }
    if (r.statusCode >= 400) {
      final code = data is Map ? (data['error'] ?? 'error').toString() : 'error';
      final msg = errText[code] ?? (data is Map ? data['message']?.toString() : null) ?? 'שגיאה';
      throw ApiError(code, msg);
    }
    return data;
  }

  static Future<http.Response> _send(String host, String method, String path, Object? body) {
    final req = http.Request(method, Uri.parse('$host$path'));
    req.headers['content-type'] = 'application/json';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null && method != 'GET') req.body = jsonEncode(body);
    return req.send().then(http.Response.fromStream).timeout(const Duration(seconds: 12));
  }

  /// Uploads one photo; returns {id, kind, url}.
  static Future<Map<String, dynamic>> upload(Uint8List bytes, {String type = 'image/jpeg'}) async {
    try {
      final r = await http
          .post(Uri.parse('$base/api/uploads'),
              headers: {'content-type': type, if (token != null) 'authorization': 'Bearer $token'}, body: bytes)
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode >= 400) {
        final code = (data['error'] ?? 'error').toString();
        throw ApiError(code, errText[code] ?? data['message']?.toString() ?? 'ההעלאה נכשלה');
      }
      return Map<String, dynamic>.from(data as Map);
    } on ApiError {
      rethrow;
    } on SocketException {
      throw ApiError('offline', errText['offline']!);
    } on TimeoutException {
      throw ApiError('offline', errText['offline']!);
    }
  }
}

// ---- small helpers for the JSON maps the server returns
typedef J = Map<String, dynamic>;
J asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<J> asList(dynamic v) => v is List ? v.whereType<Map>().map(asMap).toList() : <J>[];
List<String> strList(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];
num? asNum(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
