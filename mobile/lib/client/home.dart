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
    ['errands.office', 'סידור בבנק או במשרד ממשלתי'],
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

  @override
  Widget build(BuildContext context) {
    final jobs = ClientStore.i.jobs;
    final top = [...jobs.where(needsMe), ...jobs.where((j) => isOpenJob(j) && !needsMe(j))].take(2).toList();
    final name = Api.prefs.getString('name') ?? '';
    return Scaffold(
      appBar: AppBar(title: const Brand(size: 40), toolbarHeight: 68),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          if (name.isNotEmpty) Text('שלום $name', style: TextStyle(fontSize: 19 * fs, color: Pal.muted)),
          if (top.isNotEmpty) ...[
            const SectionTitle('הקריאות שלכם'),
            ...top.map((j) => RequestCard(job: j)),
          ],
          const SizedBox(height: 10),
          Material(
            color: const Color(0xFFFFE6D1),
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => startRequest(context, categoryId: 'errands.queue'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const QueueArt(width: 96),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('לא בא לכם לעמוד בתור?', style: TextStyle(fontSize: 19 * fs, fontWeight: FontWeight.w800, color: const Color(0xFF1D1F2B))),
                      const SizedBox(height: 4),
                      Text('מישהו יעמוד במקומכם. בנק, משרד ממשלתי, קופת חולים',
                          style: TextStyle(fontSize: 15 * fs, color: const Color(0xFF6B4A30))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
            child: Text('במה אפשר לעזור?', style: TextStyle(fontSize: 26 * fs, fontWeight: FontWeight.w800)),
          ),
          for (final g in groups)
            ChoiceTile(icon: g.icon, title: g.title, sub: g.sub, onTap: () => startRequest(context, group: g.id)),
          ChoiceTile(
            icon: Icons.more_horiz_rounded,
            title: 'משהו אחר',
            sub: 'ספרו במילים שלכם',
            onTap: () => startRequest(context, categoryId: 'other.general'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
            child: Text('לא מצאתם? חפשו', style: TextStyle(fontSize: 17 * fs, color: Pal.muted, fontWeight: FontWeight.w600)),
          ),
          TextField(
            controller: search,
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
    );
  }
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
