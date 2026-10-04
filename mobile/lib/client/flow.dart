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
  J? myLocation;
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
        'dropoff': mode == 'delivery' ? {'address': dropoff.text.trim().isEmpty ? 'המיקום שלי' : dropoff.text.trim()} : null,
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
    return PopScope(
      canPop: ix == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back, tooltip: 'חזרה'),
          title: const Text('קריאה חדשה'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(30),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(children: [
                Text('שלב ${ix + 1} מתוך $n', style: TextStyle(color: Pal.muted, fontSize: 14 * fs)),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: (ix + 1) / n, minHeight: 8, color: Pal.brand, backgroundColor: Pal.line),
                  ),
                ),
              ]),
            ),
          ),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _head(String title, [String? sub]) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 26 * fs, fontWeight: FontWeight.w800, height: 1.2)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(sub, style: TextStyle(fontSize: 16 * fs, color: Pal.muted))),
        ]),
      );

  Widget _page(List<Widget> children, {String? cta, VoidCallback? onCta, bool busy = false}) => Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: children)),
        if (err.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(err, style: TextStyle(color: Pal.hot, fontSize: 16 * fs))),
        if (cta != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton(
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
            if (Cats.get(o[0]) != null) ChoiceTile(title: o[1], selected: categoryId == o[0], onTap: () => _pick(o[0])),
          ChoiceTile(title: 'משהו אחר', selected: categoryId == 'other.general', onTap: () => _pick('other.general')),
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
            ChoiceTile(
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
          TextField(controller: address, style: TextStyle(fontSize: 19 * fs), decoration: InputDecoration(hintText: delivery ? 'למשל: סופר יוחננוף, הרצל 20, רחובות' : 'למשל: הרצל 10, רחובות')),
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
            TextField(controller: dropoff, style: TextStyle(fontSize: 19 * fs), decoration: const InputDecoration(hintText: 'ריק = אליי, למיקום שלי')),
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
          ChoiceTile(icon: Icons.bolt_rounded, title: 'כמה שיותר מהר', sub: 'היום, עכשיו', selected: urgency == 'urgent', onTap: () {
            urgency = 'urgent';
            _next();
          }),
          ChoiceTile(icon: Icons.event_rounded, title: 'לא דחוף', sub: 'בימים הקרובים', selected: urgency == 'normal', onTap: () {
            urgency = 'normal';
            _next();
          }),
        ]);
      case 'price':
        return _page([
          _head('כמה תרצו לשלם?'),
          ChoiceTile(
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
          ChoiceTile(
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
          Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sum(catIcon(categoryId), Cats.name(categoryId)),
              _sum(Icons.notes_rounded, desc.text.trim()),
              if (physical) _sum(Icons.place_rounded, mode == 'delivery' ? 'איסוף: ${address.text.trim()}\nמסירה: ${dropoff.text.trim().isEmpty ? 'אליי' : dropoff.text.trim()}' : address.text.trim()),
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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Pal.brandInk, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 17 * fs))),
        ]),
      );
}
