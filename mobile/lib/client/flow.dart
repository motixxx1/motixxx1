import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/device.dart';
import '../core/ui.dart';
import 'client_app.dart';
import 'home.dart';
import 'job.dart';

void startRequest(BuildContext context, {String? group, String? categoryId, bool replace = false}) {
  final route = MaterialPageRoute<void>(builder: (_) => NewRequestScreen(group: group, categoryId: categoryId));
  replace ? Navigator.pushReplacement(context, route) : Navigator.push(context, route);
}

const _photoParents = ['plumbing', 'electric', 'renovation', 'carpentry', 'locksmith', 'hvac', 'appliances', 'help', 'cleaning',
  'garden', 'pest', 'moving', 'auto', 'computers', 'other'];
const _modeAsk = {
  'onsite': [Icons.home_rounded, 'שיבוא אליי', 'מקצוען מגיע לכתובת שלכם'],
  'phone': [Icons.phone_rounded, 'בשיחת טלפון', 'בלי שמישהו יגיע'],
  'remote': [Icons.computer_rounded, 'מרחוק', 'דרך המחשב או שיחת וידאו'],
  'delivery': [Icons.inventory_2_rounded, 'לאסוף ולהביא', 'ממקום אחד למקום אחר'],
};

/// Colors of a request's steps: the same color as the home tile it came from.
class FlowTheme {
  const FlowTheme(this.soft, this.ink, this.accent);
  final Color soft, ink, accent;
}
const _bg = Color(0xFFF4F1EA);
const _dark = Color(0xFF1B1A20);
FlowTheme flowTheme(String? group, String? categoryId) {
  if (categoryId == 'errands.queue') return const FlowTheme(Color(0xFFD9ECFF), Color(0xFF12245C), Color(0xFF1D4ED8));
  if (categoryId == 'errands.home_wait') return const FlowTheme(Color(0xFFE6F9C4), Color(0xFF2F4A00), Color(0xFF3F6212));
  switch (group ?? Cats.parentOf(categoryId)) {
    case 'errand': case 'delivery': case 'errands':
      return const FlowTheme(Color(0xFFFFE58A), Color(0xFF3D2A00), Color(0xFF9A6700));
    case 'home': case 'cleaning': case 'help': case 'moving':
      return const FlowTheme(Color(0xFFFFD9E4), Color(0xFF4A0A24), Color(0xFFBE185D));
    case 'tech': case 'computers': case 'tutoring':
      return const FlowTheme(Color(0xFFD6F5E3), Color(0xFF063B2A), Color(0xFF047857));
    case 'car': case 'auto':
      return const FlowTheme(Color(0xFFE3E8F4), Color(0xFF1E293B), Color(0xFF334155));
    case 'care': case 'beauty':
      return const FlowTheme(Color(0xFFFCE1F0), Color(0xFF500B34), Color(0xFFA21CAF));
    case 'expert': case 'legal': case 'professional':
      return const FlowTheme(Color(0xFFEDE6FF), Color(0xFF2A1466), Color(0xFF5B3DF5));
    default:
      return const FlowTheme(Color(0xFFFFE6D1), Color(0xFF5A2300), Color(0xFFE25C00));
  }
}

/// New request: one question per screen, big buttons, nothing extra.
class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key, this.group, this.categoryId});
  final String? group;
  final String? categoryId;
  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  String? group, categoryId, mode, urgency, priceMode;
  final desc = TextEditingController(), address = TextEditingController(), dropoff = TextEditingController();
  final itemsCost = TextEditingController(), price = TextEditingController();
  final List<J> photos = [];
  bool allowCalls = true, uploading = false, sending = false;
  J? myLocation, addrLoc, dropLoc;
  int ix = 0;
  String err = '';

  @override
  void initState() {
    super.initState();
    group = widget.group;
    _pick(widget.categoryId, advance: false);
    currentLocation().then((l) => myLocation = l);
  }

  void _pick(String? id, {bool advance = true}) {
    categoryId = id;
    if (id != null) {
      final modes = Cats.modes(id);
      mode = modes.length == 1 ? modes.first : null;
    }
    if (advance) _next();
  }

  List<String> get steps {
    List<String> after(String cat) {
      final modes = Cats.modes(cat);
      final m = mode ?? modes.first;
      return [
        'desc',
        if (modes.length > 1) 'mode',
        if (m == 'onsite' || m == 'delivery') 'place',
        'when',
        if (Cats.parentOf(cat) != 'travel') 'price',
        'summary',
      ];
    }

    final g = groupOf(group);
    if (g != null && categoryId == null) return ['sub', ...after(g.opts.first.first)];
    return [if (g != null) 'sub', ...after(categoryId ?? 'other.general')];
  }

  String get step => steps[ix.clamp(0, steps.length - 1)];

  void _next() => setState(() {
        err = '';
        ix = (ix + 1).clamp(0, steps.length - 1);
      });

  void _back() {
    if (ix == 0) {
      Navigator.pop(context);
    } else {
      setState(() {
        err = '';
        ix -= 1;
      });
    }
  }

  Future<void> _addPhoto(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 80);
      if (x == null) return;
      setState(() => uploading = true);
      final saved = await Api.upload(await x.readAsBytes());
      setState(() => photos.add(saved));
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } catch (_) {
      if (mounted) toast(context, 'לא הצלחנו לצרף את התמונה', err: true);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _send() async {
    setState(() => sending = true);
    final physical = mode == 'onsite' || mode == 'delivery';
    try {
      myLocation ??= await currentLocation();
      final job = asMap(await Api.post('/api/jobs', {
        'media': photos.map((p) => p['id']).toList(),
        'categoryId': categoryId,
        'mode': mode ?? Cats.modes(categoryId).first,
        'description': desc.text.trim(),
        'address': physical && address.text.trim().isNotEmpty ? address.text.trim() : null,
        'myLocation': physical ? myLocation : null,
        if (physical && addrLoc != null) 'location': addrLoc,
        'dropoff': mode == 'delivery' ? {'address': dropoff.text.trim().isEmpty ? 'המיקום שלי' : dropoff.text.trim(), if (dropLoc != null) 'location': dropLoc} : null,
        'itemsCost': mode == 'delivery' ? asNum(itemsCost.text.trim()) : null,
        'urgency': urgency ?? 'normal',
        'paymentMode': 'direct',
        'allowCalls': allowCalls,
        'clientPrice': priceMode == 'fixed' ? asNum(price.text.trim()) : null,
      }));
      await ClientStore.i.load();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => JobScreen(id: job['id'].toString())));
    } on ApiError catch (e) {
      if (mounted) setState(() => err = e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = steps.length;
    final th = flowTheme(group, categoryId);
    return PopScope(
      canPop: ix == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: _bg,
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back, tooltip: 'חזרה'),
          title: Text('קריאה חדשה', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19 * fs, color: _dark)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(34),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Row(children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 8,
                      decoration: BoxDecoration(
                        color: i <= ix ? th.accent : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: i <= ix ? null : Border.all(color: const Color(0xFFE6E1D6)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Text('${ix + 1}/$n', style: TextStyle(color: th.ink, fontSize: 14 * fs, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  FlowTheme get th => flowTheme(group, categoryId);

  Widget _head(String title, [String? sub]) => Container(
        margin: const EdgeInsets.fromLTRB(0, 4, 0, 18),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(color: th.soft, borderRadius: BorderRadius.circular(28)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (sub != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .7), borderRadius: BorderRadius.circular(14)),
                  child: Text(sub, style: TextStyle(fontSize: 14 * fs, fontWeight: FontWeight.w700, color: th.ink)),
                ),
              Text(title, style: TextStyle(fontSize: 27 * fs, fontWeight: FontWeight.w900, height: 1.15, color: th.ink, letterSpacing: -.3)),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Icon(categoryId != null ? catIcon(categoryId) : (groupOf(group)?.icon ?? Icons.bolt_rounded), color: th.accent, size: 30),
          ),
        ]),
      );

  /// One answer: white card with a colored icon square; the chosen one takes the step's color.
  Widget _opt({IconData? icon, required String title, String? sub, required bool selected, required VoidCallback onTap, Color? tint}) {
    final c = tint ?? th.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? th.soft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: selected ? c : const Color(0xFFE9E4DA), width: selected ? 2.5 : 1.2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: selected ? Colors.white : th.soft, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon ?? Icons.circle_outlined, color: c, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w800, color: _dark)),
                  if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: TextStyle(fontSize: 14.5 * fs, color: const Color(0xFF5C5966)))),
                ]),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.chevron_left_rounded, color: selected ? c : const Color(0xFFB9B4AA), size: 28),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _page(List<Widget> children, {String? cta, VoidCallback? onCta, bool busy = false}) => Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: children)),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(err, style: TextStyle(color: Pal.hot, fontSize: 16 * fs))),
        if (cta != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _dark, minimumSize: const Size.fromHeight(60), shape: const StadiumBorder(),
                  textStyle: TextStyle(fontSize: 19 * fs, fontWeight: FontWeight.w800)),
              onPressed: busy ? null : onCta,
              child: busy ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)) : Text(cta),
            ),
          ),
      ]);

  Widget _body() {
    final g = groupOf(group);
    switch (step) {
      case 'sub':
        return _page([
          _head(g?.title ?? 'מה צריך?', 'מה בדיוק?'),
          for (final o in g?.opts ?? <List<String>>[])
            if (Cats.get(o[0]) != null) _opt(icon: catIcon(o[0]), title: o[1], selected: categoryId == o[0], onTap: () => _pick(o[0])),
          _opt(icon: Icons.more_horiz_rounded, title: 'משהו אחר', selected: categoryId == 'other.general', onTap: () => _pick('other.general')),
        ]);
      case 'desc':
        final photosOk = _photoParents.contains(Cats.parentOf(categoryId));
        return _page([
          _head(categoryId == 'errands.queue' ? 'איפה לעמוד בתור, ומתי?' : 'ספרו במילים שלכם', Cats.name(categoryId)),
          TextField(
            controller: desc,
            maxLines: 5,
            minLines: 4,
            textInputAction: TextInputAction.newline,
            style: TextStyle(fontSize: 19 * fs),
            decoration: InputDecoration(hintText: categoryId == 'errands.queue' ? 'למשל: בנק הפועלים ברחוב הרצל, מחר ב-8:30' : g?.ex ?? 'מה צריך לעשות?'),
          ),
          if (photosOk) ...[
            const SizedBox(height: 16),
            Text('תמונה עוזרת להבין מהר (לא חובה)', style: TextStyle(color: Pal.muted, fontSize: 15 * fs)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in photos)
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(Api.url(p['url'].toString()), width: 84, height: 84, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 2,
                    left: 2,
                    child: InkWell(
                      onTap: () => setState(() => photos.remove(p)),
                      child: const CircleAvatar(radius: 13, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
                    ),
                  ),
                ]),
              if (photos.length < 6)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(84, 84)),
                  onPressed: uploading ? null : () => _addPhoto(ImageSource.camera),
                  icon: uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera_rounded),
                  label: const Text('צילום'),
                ),
              if (photos.length < 6)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(84, 84)),
                  onPressed: uploading ? null : () => _addPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('מהגלריה'),
                ),
            ]),
          ],
        ], cta: 'המשך', onCta: () {
          if (desc.text.trim().length < 3) {
            setState(() => err = 'כתבו כמה מילים על מה שצריך');
          } else {
            _next();
          }
        });
      case 'mode':
        return _page([
          _head('איך זה יעבוד?'),
          for (final m in Cats.modes(categoryId))
            _opt(
              icon: _modeAsk[m]?[0] as IconData?,
              title: (_modeAsk[m]?[1] ?? modeLabel[m] ?? m).toString(),
              sub: _modeAsk[m]?[2] as String?,
              selected: mode == m,
              onTap: () {
                mode = m;
                _next();
              },
            ),
        ]);
      case 'place':
        final delivery = mode == 'delivery';
        return _page([
          _head(delivery ? 'מאיפה לאסוף ולאן להביא?' : 'לאיזו כתובת להגיע?', 'רחוב, מספר ועיר'),
          if (delivery) _label('איפה לאסוף'),
          AddressField(controller: address, hint: delivery ? 'למשל: סופר יוחננוף, הרצל 20, רחובות' : 'מתחילים להקליד רחוב ועיר', onLoc: (l) => addrLoc = l),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final l = await currentLocation(precise: true);
              if (!mounted) return;
              if (l == null) {
                toast(context, 'לא הצלחנו לקבל מיקום. כתבו כתובת', err: true);
              } else {
                myLocation = l;
                // turn the position into a street address the customer can check
                String? street;
                try {
                  street = asMap(await Api.get('/api/geocode/reverse?lat=${l['lat']}&lng=${l['lng']}'))['address']?.toString();
                } catch (_) {}
                if (!mounted) return;
                setState(() => address.text = street ?? 'המיקום שלי');
                toast(context, street != null ? 'מצאנו: $street. אפשר לתקן' : 'המיקום נשמר');
              }
            },
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('להשתמש במיקום שלי'),
          ),
          if (delivery) ...[
            _label('לאן להביא'),
            AddressField(controller: dropoff, hint: 'ריק = אליי, למיקום שלי', onLoc: (l) => dropLoc = l),
            _label('כמה בערך תעלה הקנייה? (לא חובה)'),
            TextField(controller: itemsCost, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: 'ש״ח')),
          ],
        ], cta: 'המשך', onCta: () {
          if (address.text.trim().isEmpty && myLocation == null) {
            setState(() => err = 'כתבו כתובת או השתמשו במיקום שלכם');
          } else {
            _next();
          }
        });
      case 'when':
        return _page([
          _head('כמה זה דחוף?'),
          _opt(icon: Icons.bolt_rounded, tint: const Color(0xFFE25C00), title: 'כמה שיותר מהר', sub: 'היום, עכשיו', selected: urgency == 'urgent', onTap: () {
            urgency = 'urgent';
            _next();
          }),
          _opt(icon: Icons.event_rounded, tint: const Color(0xFF1D4ED8), title: 'לא דחוף', sub: 'בימים הקרובים', selected: urgency == 'normal', onTap: () {
            urgency = 'normal';
            _next();
          }),
        ]);
      case 'price':
        return _page([
          _head('כמה תרצו לשלם?'),
          _opt(
            icon: Icons.sell_rounded,
            title: 'אני קובע/ת מחיר',
            sub: 'המקצוען הראשון שמאשר מקבל את העבודה. הכי מהיר',
            selected: priceMode == 'fixed',
            onTap: () => setState(() => priceMode = 'fixed'),
          ),
          if (priceMode == 'fixed') ...[
            _label('המחיר שאתם משלמים'),
            TextField(
              controller: price,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 26 * fs, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(suffixText: 'ש״ח'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text('מקצוען שמאשר מתחייב למחיר הזה. אפשר שיציעו גם במחיר אחר, ואתם תחליטו.', style: TextStyle(color: Pal.muted, fontSize: 15 * fs)),
            ),
          ],
          _opt(
            icon: Icons.format_list_bulleted_rounded,
            title: 'שהמקצוענים יציעו מחיר',
            sub: 'מקבלים כמה הצעות ובוחרים',
            selected: priceMode == 'quotes',
            onTap: () {
              priceMode = 'quotes';
              _next();
            },
          ),
        ], cta: priceMode == 'fixed' ? 'המשך' : null, onCta: () {
          final v = asNum(price.text.trim());
          if (v == null || v <= 0) {
            setState(() => err = 'כתבו מחיר');
          } else {
            _next();
          }
        });
      default: // summary
        final physical = mode == 'onsite' || mode == 'delivery';
        return _page([
          _head('הכל נכון?'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE9E4DA))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sum(catIcon(categoryId), Cats.name(categoryId)),
              _sum(Icons.notes_rounded, desc.text.trim()),
              if (physical) _sum(Icons.place_rounded, mode == 'delivery' ? 'איסוף: ${address.text.trim()}\nמסירה: ${dropoff.text.trim().isEmpty ? 'אליי' : dropoff.text.trim()}' : (address.text.trim().isEmpty ? 'המיקום שלי' : address.text.trim())),
              _sum(Icons.schedule_rounded, urgency == 'urgent' ? 'דחוף' : 'לא דחוף'),
              _sum(Icons.sell_rounded, priceMode == 'fixed' ? 'מחיר קבוע: ${ils(asNum(price.text.trim()))}' : 'מקבלים הצעות מחיר'),
              if (photos.isNotEmpty) _sum(Icons.photo_rounded, 'צורפו ${photos.length} תמונות'),
            ]),
          ),
          SwitchListTile(
            value: allowCalls,
            onChanged: (v) => setState(() => allowCalls = v),
            title: Text('מותר למקצוענים להתקשר אליי', style: TextStyle(fontSize: 17 * fs, fontWeight: FontWeight.w600)),
            subtitle: const Text('אחרת הטלפון נמסר רק למי שתבחרו'),
          ),
        ], cta: priceMode == 'fixed' ? 'שליחת הקריאה' : 'שליחה לקבלת הצעות', onCta: _send, busy: sending);
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16 * fs)),
      );

  Widget _sum(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: th.soft, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: th.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 17 * fs, fontWeight: FontWeight.w600, color: _dark))),
        ]),
      );
}


/// Address with suggestions from public address data while typing; picking one also gives the exact spot.
class AddressField extends StatefulWidget {
  const AddressField({super.key, required this.controller, required this.hint, required this.onLoc});
  final TextEditingController controller;
  final String hint;
  final void Function(J?) onLoc;
  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  final focus = FocusNode();
  String picked = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      if (widget.controller.text != picked) widget.onLoc(null);
    });
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  Future<List<J>> _options(TextEditingValue v) async {
    final q = v.text.trim();
    if (q.length < 3 || q == picked) return const [];
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (widget.controller.text.trim() != q) return const [];
    try {
      return asList(await Api.get('/api/geocode/suggest?q=${Uri.encodeQueryComponent(q)}')).map(asMap).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<J>(
        textEditingController: widget.controller,
        focusNode: focus,
        optionsBuilder: _options,
        displayStringForOption: (o) => o['label']?.toString() ?? '',
        onSelected: (o) {
          picked = o['label']?.toString() ?? '';
          widget.onLoc({'lat': o['lat'], 'lng': o['lng']});
        },
        fieldViewBuilder: (ctx, c, f, submit) => TextField(
          controller: c,
          focusNode: f,
          style: TextStyle(fontSize: 19 * fs),
          decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.place_rounded)),
        ),
        optionsViewBuilder: (ctx, select, options) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: Colors.white,
              elevation: 8,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 300, maxWidth: MediaQuery.of(ctx).size.width - 32),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        leading: Icon(Icons.place_outlined, color: Pal.brand),
                        title: Text(o['label']?.toString() ?? '', style: TextStyle(fontSize: 16 * fs)),
                        onTap: () => select(o),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
