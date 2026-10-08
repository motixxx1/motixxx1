import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/login.dart';
import '../core/ui.dart';
import 'flow.dart';
import 'home.dart';
import 'job.dart';
import 'profile.dart';

/// Customer data shared by the screens: my requests, refreshed every few seconds.
class ClientStore extends ChangeNotifier {
  static final i = ClientStore();
  List<J> jobs = [];
  J cfg = {};
  bool loaded = false;
  Timer? _timer;

  Map<String, (String, int)>? _seen;

  /// A local notification when a request gets a new offer or moves on (per the customer's settings).
  void _notifyChanges(List<J> list) {
    final prev = _seen;
    _seen = {for (final j in list) j['id'].toString(): (j['status'].toString(), asList(j['offers']).length)};
    if (prev == null) return;
    final nt = Profile.notify;
    for (final j in list) {
      final old = prev[j['id'].toString()];
      if (old == null) continue;
      final more = asList(j['offers']).length > old.$2 && nt['offers'] == true;
      final moved = j['status'].toString() != old.$1 && nt['status'] == true;
      if (more || moved) ClientNotes.show(j['id'].toString(), 'זריז · ${jobTitle(j)}', statusOf(j).$1);
    }
  }

  Future<void> load() async {
    try {
      final list = asList(await Api.get('/api/client/jobs'));
      list.sort((a, b) => (asNum(b['createdAt']) ?? 0).compareTo(asNum(a['createdAt']) ?? 0));
      _notifyChanges(list);
      jobs = list;
      loaded = true;
      Api.writeCache('jobs', list.map((j) => {...j, 'tracking': null}).toList());
      notifyListeners();
    } catch (_) {}
  }

  void start() {
    // what was here last time shows right away, then the server's answer replaces it
    if (jobs.isEmpty) {
      jobs = asList(Api.readCache('jobs'));
      loaded = jobs.isNotEmpty;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => load());
    load();
    cfg = Api.config;
    Api.refreshConfig().then((c) => cfg = c);
    Profile.load();
    // ask once for permission to show updates about the customer's requests
    final ask = Api.prefs.getBool('notifAsked') != true;
    Api.prefs.setBool('notifAsked', true);
    ClientNotes.init(ask: ask);
  }

  void stop() => _timer?.cancel();
  J? job(String id) => jobs.where((j) => j['id'] == id).firstOrNull;
}

class ClientRoot extends StatefulWidget {
  const ClientRoot({super.key});
  @override
  State<ClientRoot> createState() => _ClientRootState();
}

class _ClientRootState extends State<ClientRoot> {
  bool get logged => Api.token != null;
  Future<void>? ready;

  @override
  void initState() {
    super.initState();
    Api.onLoggedOut = () {
      ClientStore.i.stop();
      if (mounted) setState(() {});
    };
    ready = Cats.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!logged) return LoginScreen(onDone: (_) => setState(() {}));
    return FutureBuilder<void>(
      future: ready,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
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
        return const ClientShell();
      },
    );
  }
}

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});
  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    ClientStore.i.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context));
  }

  @override
  void dispose() {
    ClientStore.i.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ClientStore.i,
      builder: (ctx, _) {
        final waiting = ClientStore.i.jobs.where(needsMe).length;
        return Scaffold(
          body: IndexedStack(index: tab, children: [
            HomeTab(onMine: () => setState(() => tab = 1)),
            const MineTab(),
            const AccountTab(),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            height: 74,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_rounded, size: 30), label: 'בית'),
              NavigationDestination(
                icon: Badge(isLabelVisible: waiting > 0, label: Text('$waiting'), child: const Icon(Icons.list_alt_rounded, size: 30)),
                label: 'הקריאות שלי',
              ),
              const NavigationDestination(icon: Icon(Icons.person_rounded, size: 30), label: 'חשבון'),
            ],
          ),
        );
      },
    );
  }
}

class MineTab extends StatefulWidget {
  const MineTab({super.key});
  @override
  State<MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<MineTab> {
  bool showDone = false;

  @override
  Widget build(BuildContext context) {
    final jobs = ClientStore.i.jobs;
    final open = jobs.where(isOpenJob).toList(), done = jobs.where((j) => !isOpenJob(j)).toList();
    final list = showDone ? done : open;
    Widget tab(String label, int n, bool on, VoidCallback tap) => Expanded(
          child: Material(
            color: on ? const Color(0xFF1B1A20) : Colors.white,
            shape: StadiumBorder(side: BorderSide(color: on ? const Color(0xFF1B1A20) : const Color(0xFFE6E1D6))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: tap,
              child: SizedBox(
                height: 46,
                child: Center(
                  child: Text('$label · $n', style: TextStyle(fontSize: 15 * fs, fontWeight: FontWeight.w700, color: on ? Colors.white : const Color(0xFF1B1A20))),
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1EA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ClientStore.i.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            children: [
              Text('הקריאות שלי', style: TextStyle(fontSize: 28 * fs, fontWeight: FontWeight.w900, color: const Color(0xFF1B1A20), letterSpacing: -.5)),
              const SizedBox(height: 4),
              Text('לוחצים על העיפרון כדי לתת לקריאה שם משלכם', style: TextStyle(fontSize: 14 * fs, color: const Color(0xFF5C5966))),
              const SizedBox(height: 16),
              Row(children: [
                tab('פתוחות', open.length, !showDone, () => setState(() => showDone = false)),
                const SizedBox(width: 10),
                tab('הסתיימו', done.length, showDone, () => setState(() => showDone = true)),
              ]),
              const SizedBox(height: 16),
              if (list.isEmpty)
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: const Color(0xFFE9E4DA))),
                  child: Column(children: [
                    Icon(showDone ? Icons.task_alt_rounded : Icons.list_alt_rounded, size: 44, color: Pal.brand),
                    const SizedBox(height: 10),
                    Text(!ClientStore.i.loaded ? 'טוען…' : showDone ? 'עוד אין קריאות שהסתיימו' : 'אין קריאות פתוחות',
                        style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w800)),
                    if (!showDone && ClientStore.i.loaded) ...[
                      const SizedBox(height: 14),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Pal.brand, shape: const StadiumBorder()),
                        onPressed: () => startRequest(context),
                        child: const Text('פתיחת קריאה'),
                      ),
                    ],
                  ]),
                ),
              ...list.map((j) => RequestCard(job: j)),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  Future<void> _logout() async {
    ClientStore.i.stop();
    ClientStore.i.jobs = [];
    await Api.setToken(null);
    Api.onLoggedOut?.call();
  }

  Future<void> _rename(BuildContext context) async {
    final c = TextEditingController(text: Api.prefs.getString('name') ?? '');
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('השם שלכם'),
        content: TextField(controller: c, autofocus: true, maxLength: 40, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('שמירה')),
        ],
      ),
    );
    if (n == null || n.trim().isEmpty) return;
    try {
      final r = asMap(await Api.post('/api/me/name', {'name': n.trim()}));
      await Api.prefs.setString('name', r['name']?.toString() ?? n.trim());
      if (context.mounted) toast(context, 'השם עודכן');
      await ClientStore.i.load();
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('חשבון')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Box(
            child: Row(children: [
              CircleAvatar(radius: 28, backgroundColor: Pal.brandSoft, child: Icon(Icons.person_rounded, color: Pal.brandInk, size: 30)),
              const SizedBox(width: 14),
              Expanded(child: Text(Api.prefs.getString('name') ?? '', style: TextStyle(fontSize: 20 * fs, fontWeight: FontWeight.w700))),
              TextButton.icon(onPressed: () => _rename(context), icon: const Icon(Icons.edit_rounded, size: 20), label: const Text('עריכה')),
            ]),
          ),
          const ProfileSection(),
          Box(
            // APK builds download the pros' APK; iPhone and store builds open the pros' web app
            onTap: () => openLink(Api.url(sideload ? '/download/ProMarket-pro.apk' : '/pro')),
            child: Row(children: [
              Icon(Icons.handyman_rounded, color: Pal.brandInk),
              const SizedBox(width: 12),
              Expanded(child: Text(sideload ? 'יש לכם מקצוע? הורידו את זריז מקצוענים' : 'יש לכם מקצוע? הצטרפו לזריז מקצוענים', style: TextStyle(fontSize: 17 * fs, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout_rounded), label: const Text('יציאה מהחשבון')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Pal.hot),
            onPressed: () async {
              final ok = await confirmSheet(context,
                  title: 'למחוק את החשבון?',
                  text: 'השם, הטלפון והקריאות שלכם יימחקו. אי אפשר לבטל את זה. אי אפשר למחוק כשיש עבודה בביצוע.',
                  ok: 'כן, למחוק',
                  danger: true);
              if (!ok) return;
              try {
                await Api.delete('/api/me');
                if (context.mounted) toast(context, 'החשבון נמחק');
                await _logout();
              } on ApiError catch (e) {
                if (context.mounted) toast(context, e.message, err: true);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('מחיקת החשבון'),
          ),
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
            TextButton(onPressed: () => openLink(Api.url('/privacy')), child: const Text('מדיניות פרטיות')),
            TextButton(onPressed: () => openLink(Api.url('/terms')), child: const Text('תנאי שימוש')),
          ]),
        ],
      ),
    );
  }
}
