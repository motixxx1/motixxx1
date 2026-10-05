import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/login.dart';
import '../core/ui.dart';
import 'home.dart';
import 'job.dart';

/// Customer data shared by the screens: my requests, refreshed every few seconds.
class ClientStore extends ChangeNotifier {
  static final i = ClientStore();
  List<J> jobs = [];
  J cfg = {};
  bool loaded = false;
  Timer? _timer;

  Future<void> load() async {
    try {
      final list = asList(await Api.get('/api/client/jobs'));
      list.sort((a, b) => (asNum(b['createdAt']) ?? 0).compareTo(asNum(a['createdAt']) ?? 0));
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

class MineTab extends StatelessWidget {
  const MineTab({super.key});
  @override
  Widget build(BuildContext context) {
    final jobs = ClientStore.i.jobs;
    final open = jobs.where(isOpenJob).toList(), done = jobs.where((j) => !isOpenJob(j)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('הקריאות שלי')),
      body: RefreshIndicator(
        onRefresh: ClientStore.i.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (jobs.isEmpty)
              Empty(
                icon: Icons.list_alt_rounded,
                title: ClientStore.i.loaded ? 'עוד לא פתחתם קריאה' : 'טוען…',
                text: 'כשתפתחו, היא תופיע כאן.',
              ),
            ...open.map((j) => RequestCard(job: j)),
            if (done.isNotEmpty) const SectionTitle('הסתיימו'),
            ...done.map((j) => RequestCard(job: j)),
          ],
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
            ]),
          ),
          Box(
            onTap: () => openLink(Api.url('/download/ProMarket-pro.apk')),
            child: Row(children: [
              Icon(Icons.handyman_rounded, color: Pal.brandInk),
              const SizedBox(width: 12),
              Expanded(child: Text('יש לכם מקצוע? הורידו את זריז מקצוענים', style: TextStyle(fontSize: 17 * fs, fontWeight: FontWeight.w600))),
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
