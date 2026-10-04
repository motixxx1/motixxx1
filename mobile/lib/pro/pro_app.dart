import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/login.dart';
import '../core/ui.dart';
import 'background.dart';
import 'domains.dart';
import 'earnings.dart';
import 'jobs.dart';
import 'popup.dart';
import 'today.dart';

const tripStatuses = ['assigned', 'en_route', 'picked_up', 'arrived', 'in_progress'];
const movingStatuses = ['en_route', 'picked_up', 'arrived'];

/// Next step for the pro, per kind of work: [status to send, button text].
const nextStep = <String, Map<String, List<String>>>{
  'onsite': {
    'assigned': ['en_route', 'יצאתי לדרך'],
    'en_route': ['arrived', 'הגעתי'],
    'arrived': ['in_progress', 'התחלתי לטפל'],
    'in_progress': ['completed', 'סיימתי'],
  },
  'remote': {'assigned': ['in_progress', 'התחלתי'], 'in_progress': ['completed', 'סיימתי']},
  'phone': {'assigned': ['in_progress', 'התחלתי'], 'in_progress': ['completed', 'סיימתי']},
  'delivery': {
    'assigned': ['en_route', 'יצאתי לאיסוף'],
    'en_route': ['picked_up', 'אספתי'],
    'picked_up': ['arrived', 'הגעתי ליעד'],
    'arrived': ['completed', 'נמסר'],
  },
};
List<String>? nextOf(J j) => nextStep[j['mode']]?[j['status']];

const proStatus = <String, String>{
  'open': 'ממתין לבחירת הלקוח', 'assigned': 'הלקוח בחר בך', 'en_route': 'בדרך', 'arrived': 'הגעתי, מתחילים',
  'picked_up': 'נאסף', 'in_progress': 'בעבודה', 'completed': 'ממתין לאישור הלקוח', 'closed_done': 'הושלם',
  'booking_failed': 'הזמנה נכשלה',
};

/// Everything the pro screens share, refreshed every few seconds (also in the background
/// while available, thanks to the foreground service).
class ProStore extends ChangeNotifier with WidgetsBindingObserver {
  static final i = ProStore();
  J me = {};
  List<J> feed = [], jobs = [];
  J cfg = {'leadFees': false, 'payments': false};
  bool loaded = false, foreground = true;
  final Set<String> _seen = {};
  final _incoming = StreamController<J>.broadcast();
  Stream<J> get incoming => _incoming.stream;
  String? pendingPopup;
  Timer? _timer;
  int _lastPush = 0;

  bool get available => me['available'] == true;
  J? get location => Bg.last ?? (me['location'] is Map ? asMap(me['location']) : null);
  J? get trip => jobs.where((j) => asMap(j['myOffer'])['status'] == 'accepted' && tripStatuses.contains(j['status'])).firstOrNull;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    _seen.addAll(Api.prefs.getStringList('seen') ?? []);
    // what was here last time shows right away, then the server's answer replaces it
    final cached = asMap(Api.readCache('pro'));
    if (me.isEmpty && cached.isNotEmpty) {
      feed = asList(cached['feed']);
      jobs = asList(cached['jobs']);
      me = asMap(cached['me']);
      notifyListeners();
    }
    if (Api.config.isNotEmpty) cfg = Api.config;
    cfg = await Api.refreshConfig().then((c) => c.isEmpty ? cfg : c);
    await load(first: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => load());
    Bg.onPosition = _onPosition;
    await syncService();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    Bg.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) load();
  }

  Future<void> load({bool first = false}) async {
    try {
      final r = await Future.wait([Api.get('/api/pro/feed'), Api.get('/api/pro/jobs'), Api.get('/api/pro/me')]);
      feed = asList(r[0]);
      jobs = asList(r[1]);
      me = asMap(r[2]);
      loaded = true;
      Api.writeCache('pro', {'feed': feed, 'jobs': jobs, 'me': me});
      notifyListeners();
      _checkNew(silent: first);
      await syncService();
    } catch (_) {}
  }

  // New request in my area: popup in the app, loud notification when in the background.
  void _checkNew({bool silent = false}) {
    if (!available) return;
    final fresh = feed.where((j) => !_seen.contains(j['id'])).toList();
    if (fresh.isEmpty) return;
    for (final j in fresh) {
      _seen.add(j['id'].toString());
    }
    Api.prefs.setStringList('seen', _seen.toList().reversed.take(300).toList());
    if (silent) return;
    final j = fresh.first;
    if (foreground) {
      _incoming.add(j);
    } else {
      pendingPopup = j['id'].toString();
      final price = j['clientPrice'] != null ? ' · ${ils(j['clientPrice'])}' : '';
      final km = j['distanceKm'] != null ? ' · ${j['distanceKm']} ק״מ' : '';
      Bg.alertJob(j, 'קריאה חדשה: ${Cats.name(j['categoryId']?.toString())}$price', '${j['description'] ?? ''}$km');
    }
  }

  void markSeen(String id) => _seen.add(id);

  /// The foreground service runs while available or while on the way / on site.
  Future<void> syncService() async {
    final t = trip;
    final need = available || (t != null && movingStatuses.contains(t['status']));
    if (need && !Bg.running) {
      await Bg.start(onJob: t != null);
    } else if (!need && Bg.running) {
      await Bg.stop();
    }
  }

  // Position updates: every few seconds while the customer is watching, otherwise once a minute.
  void _onPosition(J loc) {
    final t = trip;
    final now = DateTime.now().millisecondsSinceEpoch;
    final every = t != null && movingStatuses.contains(t['status']) ? 4000 : 60000;
    if (now - _lastPush < every) return;
    _lastPush = now;
    Api.put('/api/pro/location', loc).catchError((_) => null);
    notifyListeners();
  }

  Future<void> pushLocationNow() async {
    final l = Bg.last ?? await currentLocation(precise: true);
    if (l == null) return;
    _lastPush = DateTime.now().millisecondsSinceEpoch;
    try {
      await Api.put('/api/pro/location', l);
    } catch (_) {}
  }

  Future<void> setAvailable(bool on) async {
    if (on) {
      await Bg.init();
      final l = await currentLocation(precise: true);
      if (l != null) await Api.put('/api/pro/location', l);
    }
    await Api.put('/api/pro/availability', {'available': on});
    await load();
  }

  /// Earnings rows: finished jobs with how much and how they were paid.
  List<J> earnRows(String period) {
    final now = DateTime.now();
    final from = switch (period) {
      'today' => DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
      'week' => now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
      'month' => DateTime(now.year, now.month).millisecondsSinceEpoch,
      _ => 0,
    };
    final rows = <J>[];
    for (final j in jobs) {
      if (asMap(j['myOffer'])['status'] != 'accepted' || !['completed', 'closed_done'].contains(j['status'])) continue;
      final when = asNum(j['closedAt'] ?? j['completedAt'] ?? j['createdAt']) ?? 0;
      if (when < from) continue;
      final escrow = asMap(j['escrow']), pay = asMap(j['proPayment']);
      if (j['paymentMode'] == 'in_app') {
        final paid = escrow['payout'] != null;
        rows.add({'j': j, 'when': when, 'method': 'app', 'amount': paid ? escrow['payout'] : (escrow['amount'] ?? asMap(j['myOffer'])['price'] ?? 0), 'pending': !paid});
      } else if (pay.isNotEmpty) {
        rows.add({'j': j, 'when': when, 'method': pay['method'], 'amount': pay['amount']});
      } else {
        rows.add({'j': j, 'when': when, 'method': 'none', 'amount': asMap(j['myOffer'])['price'] ?? 0});
      }
    }
    rows.sort((a, b) => (b['when'] as num).compareTo(a['when'] as num));
    return rows;
  }

  num earnTotal(List<J> rows) => rows.where((r) => r['pending'] != true).fold<num>(0, (s, r) => s + (asNum(r['amount']) ?? 0));
}

class ProRoot extends StatefulWidget {
  const ProRoot({super.key});
  @override
  State<ProRoot> createState() => _ProRootState();
}

class _ProRootState extends State<ProRoot> {
  Future<void>? ready;

  @override
  void initState() {
    super.initState();
    Api.onLoggedOut = () {
      ProStore.i.stop();
      if (mounted) setState(() {});
    };
    ready = Cats.load();
  }

  @override
  Widget build(BuildContext context) {
    if (Api.token == null) return LoginScreen(onDone: (_) => setState(() {}));
    return FutureBuilder<void>(
      future: ready,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snap.hasError) {
          return Scaffold(
            body: Empty(
              icon: Icons.wifi_off_rounded,
              title: 'אין חיבור לשרת',
              text: 'בדקו שיש אינטרנט ונסו שוב',
              action: FilledButton(onPressed: () => setState(() => ready = Cats.load()), child: const Text('לנסות שוב')),
            ),
          );
        }
        return const ProShell();
      },
    );
  }
}

class ProShell extends StatefulWidget {
  const ProShell({super.key});
  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int tab = 0;
  StreamSubscription<J>? sub;
  bool popupOpen = false;

  static const titles = ['היום', 'קריאות', 'עבודות', 'תחומים', 'הכנסות'];

  @override
  void initState() {
    super.initState();
    final s = ProStore.i;
    s.start();
    sub = s.incoming.listen(_popup);
    Bg.onTap = (id) {
      s.pendingPopup = id;
      _openPending();
    };
    s.addListener(_openPending);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context));
  }

  @override
  void dispose() {
    sub?.cancel();
    ProStore.i.removeListener(_openPending);
    ProStore.i.stop();
    super.dispose();
  }

  // Back from the background (or a notification tap): show the request that rang.
  void _openPending() {
    final s = ProStore.i;
    final id = s.pendingPopup;
    if (id == null || !s.foreground || popupOpen) return;
    s.pendingPopup = null;
    final j = s.feed.where((x) => x['id'] == id).firstOrNull;
    if (j != null) _popup(j);
  }

  Future<void> _popup(J j) async {
    if (popupOpen || !mounted) return;
    popupOpen = true;
    haptic();
    final go = await Navigator.push<String>(context, MaterialPageRoute<String>(fullscreenDialog: true, builder: (_) => JobPopup(job: j, ring: true)));
    popupOpen = false;
    if (go == 'today' && mounted) setState(() => tab = 0);
  }

  void goTab(int i) => setState(() => tab = i);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProStore.i,
      builder: (ctx, _) {
        final s = ProStore.i;
        final today = s.earnTotal(s.earnRows('today'));
        final won = s.jobs.where((j) => j['status'] == 'assigned' && asMap(j['myOffer'])['status'] == 'accepted').length;
        final leadFees = s.cfg['leadFees'] == true;
        final balance = asNum(s.me['balance']) ?? 0;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            titleSpacing: 12,
            title: Row(children: [
              const Logo(size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titles[tab], style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: s.available ? Pal.ok : Pal.muted)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('${s.available ? 'זמינים לקריאות' : 'לא זמינים'} · ${s.me['name'] ?? ''}',
                          overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Pal.muted)),
                    ),
                  ]),
                ]),
              ),
            ]),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: ActionChip(
                  onPressed: () => goTab(4),
                  avatar: Icon(Icons.account_balance_wallet_rounded, size: 18, color: leadFees && balance < 10 ? Pal.warn : Pal.brand),
                  label: Text(leadFees ? ils(balance) : 'היום ${ils(today)}',
                      style: TextStyle(color: leadFees && balance < 10 ? Pal.warn : Pal.brand, fontWeight: FontWeight.w700)),
                  backgroundColor: Pal.brandSoft,
                  side: BorderSide(color: Pal.brand.withValues(alpha: .35)),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          body: IndexedStack(index: tab, children: [
            TodayTab(goTab: goTab, onOpen: _popup),
            FeedTab(onOpen: _popup, goTab: goTab),
            JobsTab(goTab: goTab),
            const DomainsTab(),
            const EarningsTab(),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            height: 66,
            onDestinationSelected: goTab,
            destinations: [
              const NavigationDestination(icon: Icon(Icons.power_settings_new_rounded), label: 'היום'),
              NavigationDestination(
                icon: Badge(isLabelVisible: s.feed.isNotEmpty, label: Text('${s.feed.length}'), child: const Icon(Icons.inbox_rounded)),
                label: 'קריאות',
              ),
              NavigationDestination(
                icon: Badge(isLabelVisible: won > 0, label: Text('$won'), child: const Icon(Icons.work_rounded)),
                label: 'עבודות',
              ),
              const NavigationDestination(icon: Icon(Icons.layers_rounded), label: 'תחומים'),
              const NavigationDestination(icon: Icon(Icons.account_balance_wallet_rounded), label: 'הכנסות'),
            ],
          ),
        );
      },
    );
  }
}
