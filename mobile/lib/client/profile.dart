import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/api.dart';
import '../core/ui.dart';
import 'flow.dart';

/// The customer's profile settings: saved addresses, preferred payment method, notifications.
class Profile {
  static J data = {};
  static List<J> get addresses => asList(data['addresses']).map(asMap).toList();
  static String? get payMethod => data['payMethod']?.toString();
  static J get notify => {'offers': true, 'status': true, 'promos': false, ...asMap(data['notify'])};

  static Future<J> load() async {
    try {
      data = asMap(await Api.get('/api/client/profile'));
      Api.writeCache('profile', data);
    } catch (_) {
      if (data.isEmpty) data = asMap(Api.readCache('profile'));
    }
    return data;
  }

  static Future<J> settings(J body) async {
    data = asMap(await Api.post('/api/client/settings', body));
    Api.writeCache('profile', data);
    return data;
  }
}

const payMethods = <String, (String, String)>{
  'cash': ('מזומן', 'משלמים לבעל המקצוע במקום'),
  'bit': ('ביט או פייבוקס', 'העברה מהטלפון בסיום העבודה'),
  'transfer': ('העברה בנקאית', 'לחשבון של בעל המקצוע'),
  'card': ('כרטיס אשראי', 'אצל בעל המקצוע, אם הוא מכבד'),
  'other': ('נסגור ביננו', 'מסכמים מול בעל המקצוע'),
};

/// Local notifications for the customer: a request got an offer or changed status.
class ClientNotes {
  static final _n = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(String? jobId)? onTap;

  static Future<void> init({bool ask = false}) async {
    if (!_ready) {
      _ready = true;
      try {
        await _n.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('@drawable/ic_stat'),
            iOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false),
          ),
          onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
        );
        await _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
            const AndroidNotificationChannel('updates', 'עדכונים על הקריאות', description: 'הצעות חדשות ושינויים בקריאות שלכם', importance: Importance.high));
      } catch (_) {}
    }
    if (ask) {
      try {
        await _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
        await _n.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true);
      } catch (_) {}
    }
  }

  static Future<void> show(String jobId, String title, String body) async {
    await init();
    try {
      await _n.show(
        jobId.hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails('updates', 'עדכונים על הקריאות', importance: Importance.high, priority: Priority.high, icon: 'ic_stat'),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jobId,
      );
    } catch (_) {}
  }
}

/// Settings rows for the account screen.
class ProfileSection extends StatefulWidget {
  const ProfileSection({super.key});
  @override
  State<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<ProfileSection> {
  @override
  void initState() {
    super.initState();
    if (Profile.data.isEmpty) Profile.data = asMap(Api.readCache('profile'));
    Profile.load().then((_) => mounted ? setState(() {}) : null);
  }

  Widget _row({required IconData icon, required Color bg, required Color fg, required String title, required String sub, VoidCallback? onTap}) => Box(
        onTap: onTap,
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: fg)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w800)),
              Text(sub, style: TextStyle(fontSize: 14 * fs, color: Pal.muted)),
            ]),
          ),
          Icon(Icons.chevron_left_rounded, color: Pal.muted),
        ]),
      );

  Future<void> _setNotify(String k, bool on) async {
    if (on && k != 'promos') await ClientNotes.init(ask: true);
    try {
      await Profile.settings({'notify': {k: on}});
      if (mounted) {
        setState(() {});
        toast(context, on ? 'ההתראות הופעלו' : 'ההתראות כובו');
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    }
  }

  Future<void> _pay() async {
    final cur = Profile.payMethod;
    final pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('אמצעי תשלום', style: TextStyle(fontSize: 22 * fs, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('התשלום עובר ישירות לבעל המקצוע בסוף העבודה. מה שתבחרו יופיע לו בקריאה, כדי שיידע מראש.', style: TextStyle(color: Pal.muted, fontSize: 15 * fs)),
            const SizedBox(height: 12),
            for (final e in payMethods.entries)
              Box(
                onTap: () => Navigator.pop(ctx, e.key),
                border: cur == e.key ? Pal.brand : null,
                color: cur == e.key ? Pal.brandSoft : null,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(cur == e.key ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: cur == e.key ? Pal.btn : Pal.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.value.$1, style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w700)),
                      Text(e.value.$2, style: TextStyle(fontSize: 14 * fs, color: Pal.muted)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
    if (pick == null) return;
    try {
      await Profile.settings({'payMethod': pick});
      if (mounted) {
        setState(() {});
        toast(context, 'אמצעי התשלום נשמר');
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = Profile.addresses, pm = payMethods[Profile.payMethod], nt = Profile.notify;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _row(
        icon: Icons.place_rounded,
        bg: const Color(0xFFD9ECFF),
        fg: const Color(0xFF1D4ED8),
        title: 'הכתובות שלי',
        sub: a.isEmpty ? 'בית, עבודה, ההורים. בוחרים בקליק בקריאה חדשה' : '${a.length == 1 ? 'כתובת שמורה אחת' : '${a.length} כתובות שמורות'} · ${a.map((x) => x['label']).join(', ')}',
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressesPage()));
          if (mounted) setState(() {});
        },
      ),
      _row(
        icon: Icons.credit_card_rounded,
        bg: const Color(0xFFD6F5E3),
        fg: const Color(0xFF047857),
        title: 'אמצעי תשלום',
        sub: pm == null ? 'איך נוח לכם לשלם לבעל המקצוע' : '${pm.$1} · בעל המקצוע רואה את זה בקריאה',
        onTap: _pay,
      ),
      Box(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
                width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFFFE58A), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.notifications_rounded, color: Color(0xFF7A5200))),
            const SizedBox(width: 14),
            Text('התראות', style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w800)),
          ]),
          for (final (k, t, sub) in const [
            ('status', 'עדכונים על הקריאות שלי', 'מקצוען אישר, בדרך אליכם, הגיע, סיים'),
            ('offers', 'הצעות מחיר חדשות', 'כשמקצוען שולח הצעה'),
            ('promos', 'מבצעים וחדשות', 'פעם בכמה זמן, לא יותר'),
          ])
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: nt[k] == true,
              onChanged: (v) => _setNotify(k, v),
              title: Text(t, style: TextStyle(fontSize: 17 * fs)),
              subtitle: Text(sub, style: TextStyle(fontSize: 13 * fs, color: Pal.muted)),
            ),
        ]),
      ),
    ]);
  }
}

/// Saved addresses: list, delete, add with suggestions from public address data.
class AddressesPage extends StatefulWidget {
  const AddressesPage({super.key});
  @override
  State<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends State<AddressesPage> {
  final label = TextEditingController(text: 'בית');
  final address = TextEditingController();
  J? loc;
  bool busy = false;

  Future<void> _add() async {
    final a = address.text.trim();
    if (a.length < 3) {
      toast(context, 'צריך כתובת', err: true);
      return;
    }
    setState(() => busy = true);
    try {
      Profile.data = asMap(await Api.post('/api/client/addresses', {'label': label.text.trim(), 'address': a, 'location': loc}));
      Api.writeCache('profile', Profile.data);
      address.clear();
      loc = null;
      if (mounted) toast(context, 'הכתובת נשמרה');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _del(String id) async {
    try {
      Profile.data = asMap(await Api.delete('/api/client/addresses/$id'));
      Api.writeCache('profile', Profile.data);
      if (mounted) setState(() {});
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = Profile.addresses;
    return Scaffold(
      appBar: AppBar(title: const Text('הכתובות שלי')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        if (list.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('עוד אין כתובות שמורות.', style: TextStyle(color: Pal.muted, fontSize: 16 * fs))),
        for (final a in list)
          Box(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(children: [
              Icon(Icons.place_rounded, color: Pal.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['label']?.toString() ?? '', style: TextStyle(fontSize: 17 * fs, fontWeight: FontWeight.w800)),
                  Text(a['address']?.toString() ?? '', style: TextStyle(fontSize: 14 * fs, color: Pal.muted)),
                ]),
              ),
              IconButton(onPressed: () => _del(a['id'].toString()), icon: Icon(Icons.delete_outline_rounded, color: Pal.hot), tooltip: 'מחיקה'),
            ]),
          ),
        const SizedBox(height: 14),
        Text('כתובת חדשה', style: TextStyle(fontSize: 19 * fs, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final l in const ['בית', 'עבודה', 'הורים']) ActionChip(label: Text(l), onPressed: () => setState(() => label.text = l)),
        ]),
        const SizedBox(height: 10),
        TextField(controller: label, maxLength: 30, decoration: const InputDecoration(labelText: 'שם לכתובת')),
        const SizedBox(height: 6),
        AddressField(controller: address, hint: 'מתחילים להקליד רחוב ועיר', onLoc: (l) => loc = l),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: busy ? null : _add, icon: const Icon(Icons.add_rounded), label: const Text('שמירת הכתובת')),
      ]),
    );
  }
}

/// Saved addresses as one-tap chips above an address field.
class SavedAddressChips extends StatelessWidget {
  const SavedAddressChips({super.key, required this.onPick});
  final void Function(J address) onPick;
  @override
  Widget build(BuildContext context) {
    final list = Profile.addresses;
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in list)
          ActionChip(
            avatar: Icon(Icons.place_rounded, size: 18, color: Pal.brand),
            label: Text(a['label']?.toString() ?? ''),
            onPressed: () => onPick(a),
          ),
      ]),
    );
  }
}
