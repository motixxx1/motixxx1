import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/ui.dart';
import 'client_app.dart';
import 'flow.dart';
import 'job.dart';

/// Plain-language groups instead of a wall of professions. Each option is one real category.
class Group {
  const Group(this.id, this.icon, this.title, this.sub, this.ex, this.opts);
  final String id, title, sub, ex;
  final IconData icon;
  final List<List<String>> opts;
}

const groups = <Group>[
  Group('fix', Icons.build_rounded, 'משהו התקלקל בבית', 'מים, חשמל, מזגן, מכשירים', 'למשל: הכיור במטבח סתום והמים לא יורדים', [
    ['plumbing.unclog', 'סתימה בכיור או באסלה'], ['plumbing.leak_camera', 'נזילת מים'], ['plumbing.boiler', 'דוד ומים חמים'],
    ['electric.short', 'תקלת חשמל'], ['hvac.repair', 'המזגן לא עובד'], ['appliances.washer', 'מכונת כביסה או מייבש'],
    ['appliances.fridge', 'מקרר או מקפיא'], ['locksmith.door', 'דלת נעולה או מנעול'], ['help.handyman', 'תיקון קטן אחר'],
  ]),
  Group('errand', Icons.shopping_bag_rounded, 'משלוח או סידור', 'קניות, תרופות, דואר, בנק', 'למשל: לקנות לחם, חלב וביצים ולהביא הביתה', [
    ['delivery.groceries', 'קניות מהסופר או מהמכולת'], ['delivery.pharmacy', 'תרופות מבית המרקחת'], ['delivery.food', 'אוכל ממסעדה'],
    ['delivery.package', 'חבילה או מסמכים'], ['errands.queue', 'לעמוד בתור במקומי'], ['errands.post', 'דואר ודואר רשום'],
    ['errands.office', 'סידור בבנק או במשרד ממשלתי'], ['errands.home_wait', 'מישהו שיחכה בבית לטכנאי'],
  ]),
  Group('home', Icons.cleaning_services_rounded, 'ניקיון ועזרה בבית', 'ניקיון, רהיטים, תלייה, הובלה', 'למשל: ניקיון דירת 3 חדרים, פעם אחת', [
    ['cleaning.home', 'ניקיון הבית'], ['cleaning.windows', 'ניקוי חלונות'], ['cleaning.ironing', 'כביסה וגיהוץ'],
    ['help.furniture', 'הרכבת רהיטים'], ['help.tv_mount', 'תליית תמונות, מדפים או טלוויזיה'], ['help.garden', 'עבודה בגינה'],
    ['moving.small', 'הובלה קטנה'],
  ]),
  Group('tech', Icons.smartphone_rounded, 'טלפון ומחשב', 'תקלה, אינטרנט, הדרכה', 'למשל: הטלפון לא נדלק מאז אתמול', [
    ['computers.phone_repair', 'הטלפון לא עובד'], ['computers.repair', 'המחשב לא עובד'], ['computers.network', 'אינטרנט ו-WiFi'],
    ['tutoring.tech_seniors', 'ללמוד להשתמש בטלפון או במחשב'],
  ]),
  Group('car', Icons.directions_car_rounded, 'רכב', 'לא מניע, פנצ׳ר, גרירה', 'למשל: הרכב לא מניע, נראה שהמצבר נגמר', [
    ['auto.battery', 'הרכב לא מניע'], ['auto.tire', 'פנצ׳ר'], ['auto.mechanic', 'מכונאי עד הבית'], ['auto.towing', 'גרירה'],
  ]),
  Group('care', Icons.favorite_rounded, 'ליווי וטיפול', 'ליווי לבדיקות, מטפל, כלב', 'למשל: ליווי לבדיקה בבית החולים ביום שלישי בבוקר', [
    ['errands.elderly_companion', 'ליווי לבדיקות ולסידורים'], ['care.elderly', 'מטפל או מטפלת'], ['care.dog_walking', 'להוציא את הכלב'],
    ['beauty.hair', 'תספורת בבית'],
  ]),
  Group('expert', Icons.description_rounded, 'עזרה ממומחה', 'טפסים, עורך דין, מס', 'למשל: צריך עזרה במילוי טופס לביטוח לאומי', [
    ['legal.documents', 'מילוי טפסים ומסמכים'], ['legal.consult', 'עורך דין'], ['professional.tax', 'החזרי מס'], ['professional.insurance', 'ביטוח'],
  ]),
];

Group? groupOf(String? id) => groups.where((g) => g.id == id).firstOrNull;

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.onMine});
  final VoidCallback onMine;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 1200), _promo));
  }

  // Shown once: someone can stand in line for you.
  Future<void> _promo() async {
    if (!mounted || Api.prefs.getBool('queuePromo') == true) return;
    await Api.prefs.setBool('queuePromo', true);
    if (!mounted) return;
    final go = await openSheet<bool>(
      context,
      (ctx) => Column(children: [
        const QueueArt(),
        const SizedBox(height: 12),
        Text('מישהו יעמוד בתור במקומכם', textAlign: TextAlign.center, style: TextStyle(fontSize: 26 * fs, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('בנק, משרד הפנים, קופת חולים. אתם ממשיכים עם היום שלכם, ואדם אחר עומד בתור בשבילכם.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 17 * fs, color: Pal.muted, height: 1.4)),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('פתיחת קריאה')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('אחר כך')),
      ]),
    );
    if (go == true && mounted) startRequest(context, categoryId: 'errands.queue');
  }

  void _search(String q) {
    if (q.trim().length < 2) return;
    search.clear();
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SearchScreen(query: q.trim())));
  }

  bool searching = false;

  @override
  Widget build(BuildContext context) {
    final jobs = ClientStore.i.jobs;
    final top = [...jobs.where(needsMe), ...jobs.where((j) => isOpenJob(j) && !needsMe(j))].take(2).toList();
    final name = Api.prefs.getString('name') ?? '';
    const ink = Color(0xFF1B1A20);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1EA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            // greeting + logo
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (name.isNotEmpty) Text('שלום $name', style: TextStyle(fontSize: 15 * fs, color: const Color(0xFF5C5966))),
                  Text('במה נעזור היום?', style: TextStyle(fontSize: 27 * fs, fontWeight: FontWeight.w900, color: ink, letterSpacing: -.5)),
                ]),
              ),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: Pal.brand, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 30),
              ),
            ]),
            if (top.isNotEmpty) ...[
              const SectionTitle('הקריאות שלכם'),
              ...top.map((j) => RequestCard(job: j)),
            ],
            const SizedBox(height: 16),
            // bento: the big "something broke" tile, queue and delivery beside it
            SizedBox(
              height: 246,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: BentoTile(
                    color: Pal.brand,
                    big: true,
                    badge: 'הכי נפוץ',
                    icon: Icons.build_rounded,
                    title: 'משהו\nהתקלקל\nבבית',
                    textColor: Colors.white,
                    onTap: () => startRequest(context, group: 'fix'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: BentoTile(
                        color: const Color(0xFFD9ECFF),
                        icon: Icons.groups_rounded,
                        iconColor: const Color(0xFF1D4ED8),
                        title: 'לעמוד בתור במקומי',
                        textColor: const Color(0xFF12245C),
                        onTap: () => startRequest(context, categoryId: 'errands.queue'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: BentoTile(
                        color: const Color(0xFFFFE58A),
                        icon: Icons.local_shipping_rounded,
                        iconColor: const Color(0xFF7A5200),
                        title: 'משלוח או סידור',
                        textColor: const Color(0xFF3D2A00),
                        onTap: () => startRequest(context, group: 'errand'),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            // wide dark tile: someone waits at home
            Material(
              color: ink,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => startRequest(context, categoryId: 'errands.home_wait'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(color: const Color(0xFFC6F36B), borderRadius: BorderRadius.circular(18)),
                      child: const Icon(Icons.home_rounded, color: ink, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('מישהו שיחכה בבית', style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w800, color: Colors.white)),
                        Text('לטכנאי, למשלוח גדול, להובלה', style: TextStyle(fontSize: 13.5 * fs, color: const Color(0xFFC9C6D3))),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 118,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: BentoTile(
                    color: const Color(0xFFFFD9E4),
                    icon: Icons.cleaning_services_rounded,
                    iconColor: const Color(0xFF9D174D),
                    title: 'ניקיון ועזרה בבית',
                    textColor: const Color(0xFF4A0A24),
                    onTap: () => startRequest(context, group: 'home'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BentoTile(
                    color: const Color(0xFFD6F5E3),
                    icon: Icons.smartphone_rounded,
                    iconColor: const Color(0xFF047857),
                    title: 'טלפון ומחשב',
                    textColor: const Color(0xFF063B2A),
                    onTap: () => startRequest(context, group: 'tech'),
                  ),
                ),
              ]),
            ),
            // the other groups, smaller
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
              child: Text('עוד שירותים', style: TextStyle(fontSize: 17 * fs, fontWeight: FontWeight.w800, color: ink)),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in groups.where((g) => ['car', 'care', 'expert'].contains(g.id)))
                _Pill(icon: g.icon, label: g.title, onTap: () => startRequest(context, group: g.id)),
              _Pill(icon: Icons.more_horiz_rounded, label: 'משהו אחר', onTap: () => startRequest(context, categoryId: 'other.general')),
            ]),
            const SizedBox(height: 14),
            if (!searching)
              OutlinedButton.icon(
                onPressed: () => setState(() => searching = true),
                icon: const Icon(Icons.search_rounded),
                label: const Text('חיפוש בכל השירותים'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: ink, width: 2),
                  shape: const StadiumBorder(),
                ),
              )
            else
              TextField(
                controller: search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'למשל: אינסטלטור, שליח, עורך דין',
                  prefixIcon: const Icon(Icons.search_rounded, size: 28),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _search(search.text)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One tile of the home "bento": colored block, icon on top, title at the bottom.
class BentoTile extends StatelessWidget {
  const BentoTile({super.key, required this.color, required this.icon, required this.title, required this.onTap,
      this.iconColor, this.textColor = const Color(0xFF1B1A20), this.big = false, this.badge});
  final Color color, textColor;
  final Color? iconColor;
  final IconData icon;
  final String title;
  final String? badge;
  final bool big;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            if (big) Positioned(left: -18, bottom: -14, child: Icon(icon, size: 130, color: Colors.white.withValues(alpha: .25))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .22), borderRadius: BorderRadius.circular(12)),
                    child: Text(badge!, style: TextStyle(fontSize: 13 * fs, fontWeight: FontWeight.w600, color: textColor)),
                  )
                else
                  Icon(icon, size: 30, color: iconColor ?? textColor),
                Text(title, style: TextStyle(fontSize: (big ? 26 : 17) * fs, height: big ? 1.05 : 1.15, fontWeight: big ? FontWeight.w900 : FontWeight.w800, color: textColor)),
              ]),
            ),
          ]),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const StadiumBorder(side: BorderSide(color: Color(0xFFE6E1D6))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: Pal.brandInk),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 15 * fs, fontWeight: FontWeight.w600, color: const Color(0xFF1B1A20))),
            ]),
          ),
        ),
      );
}

/// A big, easy row to tap: icon, title, a short line, arrow.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({super.key, this.icon, required this.title, this.sub, required this.onTap, this.selected = false});
  final IconData? icon;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => Box(
        onTap: onTap,
        border: selected ? Pal.brand : null,
        color: selected ? Pal.brandSoft : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icon != null) ...[
            CircleAvatar(radius: 25, backgroundColor: Pal.brandSoft, child: Icon(icon, color: Pal.brandInk, size: 26)),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 19 * fs, fontWeight: FontWeight.w700)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: TextStyle(fontSize: 15 * fs, color: Pal.muted))),
            ]),
          ),
          Icon(selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: selected ? Pal.brand : Pal.muted, size: 30),
        ]),
      );
}

/// Three people in line; the first one (in the brand color) has a check mark.
class QueueArt extends StatelessWidget {
  const QueueArt({super.key, this.width = 130});
  final double width;
  @override
  Widget build(BuildContext context) {
    final s = width / 120;
    Widget person(Color c, double size) => Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: size * .55, height: size * .55, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          SizedBox(height: size * .06),
          Container(width: size, height: size * .6, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.vertical(top: Radius.circular(size)))),
        ]);
    return SizedBox(
      width: width,
      height: 64 * s,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(right: 0, bottom: 0, child: person(const Color(0xFFD9DCE6), 28 * s)),
        Positioned(right: 30 * s, bottom: 0, child: person(const Color(0xFFD9DCE6), 28 * s)),
        Positioned(right: 62 * s, bottom: 0, child: person(Pal.brand, 36 * s)),
        Positioned(
          right: 70 * s,
          top: 0,
          child: Container(
            width: 20 * s,
            height: 20 * s,
            decoration: BoxDecoration(color: Pal.ok, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
            child: Icon(Icons.check_rounded, color: Colors.white, size: 14 * s),
          ),
        ),
      ]),
    );
  }
}

/// Search when none of the groups fits.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.query});
  final String query;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final q = TextEditingController(text: widget.query);
  List<J> hits = [];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => busy = true);
    try {
      final tree = asList(await Api.get('/api/categories?q=${Uri.encodeQueryComponent(q.text.trim())}'));
      hits = [
        for (final p in tree)
          for (final s in asList(p['subs'])) <String, dynamic>{...s, 'parentName': p['name']},
      ];
    } catch (_) {
      hits = [];
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('חיפוש')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            controller: q,
            autofocus: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 14),
          if (busy) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (!busy)
            for (final h in hits.take(20))
              ChoiceTile(
                title: h['name'].toString(),
                sub: h['parentName']?.toString(),
                onTap: () => startRequest(context, categoryId: h['id'].toString(), replace: true),
              ),
          if (!busy)
            ChoiceTile(
              title: hits.isEmpty ? 'לא מצאנו. לפתוח קריאה כללית' : 'משהו אחר',
              sub: 'ספרו במילים שלכם',
              onTap: () => startRequest(context, categoryId: 'other.general', replace: true),
            ),
        ],
      ),
    );
  }
}
