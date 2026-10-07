import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// Colors: customers get a light orange app with big type, pros a dark teal one (map first).
class Pal {
  static Color get brand => isPro ? const Color(0xFF5EEAD4) : const Color(0xFFFF6A00);
  static Color get btn => isPro ? const Color(0xFF5EEAD4) : const Color(0xFFCF5200);
  static Color get onBtn => isPro ? const Color(0xFF042F2E) : Colors.white;
  static Color get brandInk => isPro ? const Color(0xFF5EEAD4) : const Color(0xFFA83A00);
  static Color get brandSoft => isPro ? const Color(0x265EEAD4) : const Color(0xFFFFF1E6);
  static Color get bg => isPro ? const Color(0xFF12151F) : const Color(0xFFF6F6F8);
  static Color get card => isPro ? const Color(0xFF181C28) : Colors.white;
  static Color get card2 => isPro ? const Color(0xFF212637) : const Color(0xFFF0F1F5);
  static Color get ink => isPro ? const Color(0xFFEEF1F8) : const Color(0xFF1D1F2B);
  static Color get muted => isPro ? const Color(0xFF9AA2B8) : const Color(0xFF5E6375);
  static Color get line => isPro ? const Color(0xFF2E3550) : const Color(0xFFE3E5EC);
  static Color get ok => isPro ? const Color(0xFF34D399) : const Color(0xFF15803D);
  static Color get okSoft => isPro ? const Color(0x2634D399) : const Color(0xFFE7F6EC);
  static Color get warn => isPro ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  static Color get warnSoft => isPro ? const Color(0x26FBBF24) : const Color(0xFFFFF4DB);
  static Color get hot => isPro ? const Color(0xFFF87171) : const Color(0xFFB42318);
  static Color get hotSoft => isPro ? const Color(0x26F87171) : const Color(0xFFFDECEA);
}

/// Bigger type for customers (many are older), compact for pros.
double get fs => isPro ? 1.0 : 1.18;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Pal.brand,
    brightness: isPro ? Brightness.dark : Brightness.light,
  ).copyWith(primary: Pal.btn, onPrimary: Pal.onBtn, surface: Pal.card, onSurface: Pal.ink, error: Pal.hot);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: Pal.bg);
  // Sizes from the Material type scale, so they can be scaled up for customers.
  final sized = Typography.englishLike2021.merge(isPro ? Typography.whiteMountainView : Typography.blackMountainView);
  final text = GoogleFonts.rubikTextTheme(sized).apply(bodyColor: Pal.ink, displayColor: Pal.ink, fontSizeFactor: fs);
  final radius = BorderRadius.circular(isPro ? 16 : 18);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Pal.bg,
      foregroundColor: Pal.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.rubik(fontSize: 22 * fs, fontWeight: FontWeight.w700, color: Pal.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(isPro ? 52 : 60),
        backgroundColor: Pal.btn,
        foregroundColor: Pal.onBtn,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: GoogleFonts.rubik(fontSize: isPro ? 16 : 20, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(isPro ? 48 : 56),
        foregroundColor: Pal.ink,
        side: BorderSide(color: Pal.line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: GoogleFonts.rubik(fontSize: isPro ? 15 : 18, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Pal.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: isPro ? 14 : 18),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Pal.line, width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Pal.line, width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Pal.brand, width: 2.5)),
      hintStyle: TextStyle(color: Pal.muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: Pal.bg, showDragHandle: true),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Pal.card,
      indicatorColor: Pal.brandSoft,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.rubik(fontSize: isPro ? 12 : 14, fontWeight: FontWeight.w600, color: Pal.ink)),
    ),
  );
}

// ---- formatting
String ils(dynamic v) {
  final n = asNum(v);
  if (n == null) return '–';
  final s = n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);
  return '$s ש״ח';
}

/// The customer's preferred way to pay, as a short suffix for a pro's job card.
String payName(dynamic m) => const {'cash': ' · מזומן', 'bit': ' · ביט/פייבוקס', 'transfer': ' · העברה', 'card': ' · אשראי'}[m] ?? '';

String showPhone(String? p) {
  if (p == null) return '';
  final d = p.replaceAll(RegExp(r'\D'), '');
  final local = d.startsWith('972') ? '0${d.substring(3)}' : d;
  return local.length == 10 ? '${local.substring(0, 3)}-${local.substring(3)}' : p;
}

String dayLabel(dynamic ms) {
  final n = asNum(ms);
  if (n == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(n.toInt());
  final now = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return 'היום $hm';
  return '${d.day}.${d.month} $hm';
}

const modeLabel = {'onsite': 'אצל הלקוח', 'remote': 'מרחוק', 'phone': 'בטלפון', 'delivery': 'איסוף ומשלוח'};
const modeIcon = {'onsite': Icons.home_rounded, 'remote': Icons.computer_rounded, 'phone': Icons.phone_rounded, 'delivery': Icons.inventory_2_rounded};

// ---- categories (loaded once from the server)
class Cats {
  static List<J> tree = [];
  static final Map<String, J> byId = {};

  static Future<void> load() async {
    if (tree.isNotEmpty) return;
    tree = asList(await Api.get('/api/categories'));
    for (final p in tree) {
      byId[p['id']] = {...p, 'parent': null, 'parentName': p['name']};
      for (final s in asList(p['subs'])) {
        byId[s['id']] = {
          ...s,
          'parent': p['id'],
          'parentName': p['name'],
          'modes': s['modes'] ?? p['modes'],
          'requirement': s['requirement'] ?? p['requirement'],
          'leadPrice': s['leadPrice'] ?? p['leadPrice'],
          'starter': p['starter'] == true,
          'payment': p['payment'],
        };
      }
    }
  }

  static J? get(String? id) => id == null ? null : byId[id];
  static String name(String? id) => get(id)?['name']?.toString() ?? '';
  static String parentOf(String? id) => get(id)?['parent']?.toString() ?? id?.split('.').first ?? '';
  static List<String> modes(String? id) => (get(id)?['modes'] as List?)?.map((e) => e.toString()).toList() ?? ['onsite'];
}

const _catIcons = <String, IconData>{
  'delivery': Icons.inventory_2_rounded, 'errands': Icons.directions_walk_rounded, 'plumbing': Icons.plumbing_rounded,
  'electric': Icons.electrical_services_rounded, 'renovation': Icons.format_paint_rounded, 'carpentry': Icons.carpenter_rounded,
  'locksmith': Icons.key_rounded, 'hvac': Icons.ac_unit_rounded, 'appliances': Icons.local_laundry_service_rounded,
  'help': Icons.handyman_rounded, 'cleaning': Icons.cleaning_services_rounded, 'garden': Icons.yard_rounded,
  'pest': Icons.pest_control_rounded, 'moving': Icons.local_shipping_rounded, 'auto': Icons.directions_car_rounded,
  'computers': Icons.computer_rounded, 'digital': Icons.design_services_rounded, 'legal': Icons.gavel_rounded,
  'professional': Icons.business_center_rounded, 'tutoring': Icons.school_rounded, 'care': Icons.favorite_rounded,
  'wellness': Icons.spa_rounded, 'beauty': Icons.content_cut_rounded, 'events': Icons.celebration_rounded,
  'travel': Icons.flight_rounded, 'other': Icons.more_horiz_rounded,
};
const _catColors = <String, int>{
  'delivery': 0xFFFF6A00, 'errands': 0xFFDB2777, 'plumbing': 0xFF0284C7, 'electric': 0xFFCA8A04, 'renovation': 0xFF9333EA,
  'carpentry': 0xFFB45309, 'locksmith': 0xFF475569, 'hvac': 0xFF0891B2, 'appliances': 0xFF2563EB, 'help': 0xFF16A34A,
  'cleaning': 0xFF0D9488, 'garden': 0xFF65A30D, 'auto': 0xFFDC2626, 'computers': 0xFF4F46E5, 'care': 0xFFE11D48,
};
IconData catIcon(String? id) => _catIcons[Cats.parentOf(id)] ?? Icons.work_rounded;
Color catColor(String? id) => Color(_catColors[Cats.parentOf(id)] ?? 0xFF64748B);

Widget catTile(String? id, {double size = 44}) {
  final c = catColor(id);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: c.withValues(alpha: isPro ? .22 : .12), borderRadius: BorderRadius.circular(size * .32)),
    child: Icon(catIcon(id), color: isPro ? Color.lerp(c, Colors.white, .35) : c, size: size * .52),
  );
}

// ---- building blocks
class Box extends StatelessWidget {
  const Box({super.key, required this.child, this.padding, this.color, this.border, this.onTap, this.margin});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(isPro ? 18 : 22);
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: color ?? Pal.card, borderRadius: r, border: Border.all(color: border ?? Pal.line, width: isPro ? 1 : 2)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.bg, this.icon});
  final String text;
  final Color? color;
  final Color? bg;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg ?? Pal.brandSoft, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color ?? Pal.brandInk), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color ?? Pal.brandInk, fontWeight: FontWeight.w700, fontSize: 13 * fs)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Text(text, style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w700)),
      );
}

class Empty extends StatelessWidget {
  const Empty({super.key, required this.icon, required this.title, this.text, this.action});
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: Column(children: [
          Icon(icon, size: 52, color: Pal.muted),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w700)),
          if (text != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(text!, textAlign: TextAlign.center, style: TextStyle(color: Pal.muted))),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 18), child: action),
        ]),
      );
}

/// A row of selectable chips (filters, periods).
class ChipsRow extends StatelessWidget {
  const ChipsRow({super.key, required this.items, required this.value, required this.onPick});
  final List<MapEntry<String, String>> items;
  final String value;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final e in items)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: e.key == value,
                  onSelected: (_) => onPick(e.key),
                  showCheckmark: false,
                  selectedColor: Pal.brandSoft,
                  labelStyle: TextStyle(color: e.key == value ? Pal.brandInk : Pal.ink, fontWeight: FontWeight.w600),
                  side: BorderSide(color: e.key == value ? Pal.brand : Pal.line),
                  backgroundColor: Pal.card,
                ),
              ),
          ],
        ),
      );
}

void toast(BuildContext context, String msg, {bool err = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: TextStyle(fontSize: 15 * fs, color: Colors.white)),
    backgroundColor: err ? const Color(0xFFB42318) : const Color(0xFF1D1F2B),
    duration: const Duration(seconds: 3),
  ));
}

/// Bottom sheet that grows with its content and moves above the keyboard.
Future<T?> openSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 22), child: builder(ctx)),
      ),
    );

Widget sheetTitle(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(child: Text(title, style: TextStyle(fontSize: 22 * fs, fontWeight: FontWeight.w700))),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), tooltip: 'סגירה'),
      ]),
    );

Future<bool> confirmSheet(BuildContext context, {required String title, required String text, required String ok, bool danger = false}) async {
  final r = await openSheet<bool>(
    context,
    (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(ctx, title),
      Text(text, style: TextStyle(fontSize: 16 * fs)),
      const SizedBox(height: 18),
      FilledButton(
        style: danger ? FilledButton.styleFrom(backgroundColor: Pal.hot, foregroundColor: Colors.white) : null,
        onPressed: () => Navigator.pop(ctx, true),
        child: Text(ok),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
    ]),
  );
  return r == true;
}

Future<void> openLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> callPhone(String? phone) async {
  if (phone == null || phone.isEmpty) return;
  await openLink('tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}');
}

Future<void> waze(dynamic loc) async {
  final l = asMap(loc);
  if (l['lat'] == null) return;
  await openLink('https://waze.com/ul?ll=${l['lat']},${l['lng']}&navigate=yes');
}

void haptic() => HapticFeedback.mediumImpact();

/// The Zariz mark: a location pin with a lightning bolt, on a rounded square.
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 42});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    final bg = isPro ? const Color(0xFF5EEAD4) : const Color(0xFFFF6A00);
    final fgBolt = isPro ? const Color(0xFF0F766E) : const Color(0xFFE85A00);
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * .3));
    canvas.drawRRect(rect, Paint()..color = bg);
    canvas.save();
    // the 64-unit artwork is drawn at 70% in the middle of the tile
    canvas.translate(size.width * .15, size.height * .15);
    canvas.scale(s * .7);
    final pin = Path()
      ..moveTo(32, 4)
      ..cubicTo(19.8, 4, 10, 13.6, 10, 25.6)
      ..cubicTo(10, 41.2, 32, 60, 32, 60)
      ..cubicTo(32, 60, 54, 41.2, 54, 25.6)
      ..cubicTo(54, 13.6, 44.2, 4, 32, 4)
      ..close();
    canvas.drawPath(pin, Paint()..color = isPro ? const Color(0xFF042F2E) : Colors.white);
    final bolt = Path()
      ..moveTo(35, 12)
      ..lineTo(22, 30)
      ..lineTo(31, 30)
      ..lineTo(28, 46)
      ..lineTo(42, 26)
      ..lineTo(33, 26)
      ..close();
    canvas.drawPath(bolt, Paint()..color = isPro ? const Color(0xFF5EEAD4) : fgBolt);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Logo + name, as in the header.
class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Logo(size: size),
        const SizedBox(width: 10),
        Text('זריז', style: TextStyle(fontSize: size * .68, fontWeight: FontWeight.w800, color: Pal.brandInk, letterSpacing: -.5)),
      ]);
}

/// Photo or video from the server.
Widget mediaStrip(dynamic media) {
  final items = asList(media).where((m) => m['kind'] == 'image').toList();
  if (items.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => showDialog<void>(
            context: ctx,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              child: InteractiveViewer(child: Image.network(Api.url(items[i]['url'].toString()), fit: BoxFit.contain)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(Api.url(items[i]['url'].toString()), width: 84, height: 84, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 84, height: 84, color: Pal.card2)),
          ),
        ),
      ),
    ),
  );
}
