import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/ui.dart';
import 'pro_app.dart';

/// Identity verification: details, a selfie, an ID photo, business details and the terms.
/// No job reaches a pro until an admin approved this.
bool validIsraeliId(String v) {
  final id = v.replaceAll(RegExp(r'\D'), '').padLeft(9, '0');
  if (!RegExp(r'^\d{9}$').hasMatch(id) || RegExp(r'^0+$').hasMatch(id)) return false;
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    var d = int.parse(id[i]) * (i % 2 + 1);
    if (d > 9) d -= 9;
    sum += d;
  }
  return sum % 10 == 0;
}

/// A card for the home screen while the account isn't verified (null when nothing to show).
Widget? verifyBanner(BuildContext context) {
  final me = ProStore.i.me;
  if (me['verifyRequired'] != true) return null;
  final k = asMap(me['kyc']), st = k['status']?.toString() ?? 'none';
  if (st == 'approved') return null;
  final (text, cta, color) = switch (st) {
    'pending' => ('החשבון בבדיקה. קריאות יתחילו להגיע אחרי האישור', 'פרטים', Pal.warn),
    'rejected' => ('האימות לא אושר: ${k['reason'] ?? ''}', 'תיקון', Pal.hot),
    _ => ('השלימו אימות חשבון כדי לקבל קריאות', 'לאימות', Pal.brand),
  };
  return Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .5))),
    child: Row(children: [
      Icon(Icons.verified_user_outlined, color: color),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: color))),
      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VerifyPage())), child: Text(cta)),
    ]),
  );
}

class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key});
  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  final name = TextEditingController(), id = TextEditingController(), city = TextEditingController();
  final bizId = TextEditingController(), exp = TextEditingController(), bio = TextEditingController();
  DateTime? birth;
  String? biz;
  bool terms = false, busy = false;
  String? err;
  final photos = <String, String?>{'selfie': null, 'id': null};
  final previews = <String, Uint8List?>{'selfie': null, 'id': null};
  final uploading = <String>{};

  @override
  void initState() {
    super.initState();
    final me = ProStore.i.me, k = asMap(me['kyc']);
    name.text = k['fullName']?.toString() ?? me['name']?.toString() ?? '';
    city.text = k['city']?.toString() ?? '';
    biz = k['businessType']?.toString();
    if (k['experienceYears'] != null) exp.text = '${k['experienceYears']}';
    bio.text = k['bio']?.toString() ?? '';
    birth = DateTime.tryParse(k['birthDate']?.toString() ?? '');
  }

  Future<void> _photo(String which) async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.camera, preferredCameraDevice: which == 'selfie' ? CameraDevice.front : CameraDevice.rear, maxWidth: 1600, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        previews[which] = bytes;
        uploading.add(which);
      });
      final saved = await Api.upload(bytes);
      photos[which] = saved['url']?.toString();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, err: true);
    } catch (_) {
      if (mounted) toast(context, 'לא הצלחנו לצרף את התמונה', err: true);
    }
    if (mounted) setState(() => uploading.remove(which));
  }

  Future<void> _send() async {
    String? e;
    if (name.text.trim().split(RegExp(r'\s+')).length < 2) {
      e = 'כתבו שם פרטי ושם משפחה';
    } else if (!validIsraeliId(id.text)) {
      e = 'מספר תעודת זהות לא תקין';
    } else if (birth == null) {
      e = 'בחרו תאריך לידה';
    } else if (city.text.trim().isEmpty) {
      e = 'כתבו עיר';
    } else if (photos['selfie'] == null) {
      e = 'צריך סלפי';
    } else if (photos['id'] == null) {
      e = 'צריך צילום של תעודת הזהות';
    } else if (biz == null) {
      e = 'בחרו סוג עסק';
    } else if (biz != 'none' && !RegExp(r'^\d{8,9}$').hasMatch(bizId.text.trim())) {
      e = 'מספר עוסק או ח״פ לא תקין';
    } else if (!terms) {
      e = 'צריך לאשר את התנאים';
    }
    setState(() => err = e);
    if (e != null) return;
    setState(() => busy = true);
    try {
      await Api.post('/api/pro/kyc', {
        'fullName': name.text.trim(),
        'idNumber': id.text.trim(),
        'birthDate': birth!.toIso8601String().substring(0, 10),
        'city': city.text.trim(),
        'businessType': biz,
        'businessId': bizId.text.trim(),
        'experienceYears': int.tryParse(exp.text) ?? 0,
        'bio': bio.text.trim(),
        'selfieUrl': photos['selfie'],
        'idPhotoUrl': photos['id'],
        'acceptTerms': true,
      });
      await ProStore.i.load();
      if (mounted) {
        toast(context, 'נשלח לאימות. נעדכן כשיאושר');
        Navigator.pop(context);
      }
    } on ApiError catch (x) {
      setState(() => err = x.message);
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _photoBox(String which, String title, String sub) {
    final p = previews[which], done = photos[which] != null;
    return Expanded(
      child: InkWell(
        onTap: uploading.contains(which) ? null : () => _photo(which),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Pal.card2, borderRadius: BorderRadius.circular(16), border: Border.all(color: done ? Pal.brand : Pal.line, width: 1.5)),
          child: Column(children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: p != null
                    ? Stack(fit: StackFit.expand, children: [
                        Image.memory(p, fit: BoxFit.cover),
                        if (uploading.contains(which)) const Center(child: CircularProgressIndicator()),
                      ])
                    : Container(color: Pal.card, child: Icon(which == 'selfie' ? Icons.face_rounded : Icons.badge_rounded, size: 40, color: Pal.muted)),
              ),
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Pal.muted)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = asMap(ProStore.i.me['kyc']), st = k['status']?.toString() ?? 'none';
    final locked = st == 'pending' || st == 'approved';
    return Scaffold(
      appBar: AppBar(title: const Text('אימות חשבון')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Pal.brandSoft, borderRadius: BorderRadius.circular(16)),
          child: Text(
            switch (st) {
              'pending' => 'בבדיקה. נעדכן כשיאושר, בדרך כלל עד יום עסקים. בינתיים אפשר לבחור תחומים ולהעלות מסמכים.',
              'approved' => 'החשבון מאומת. לשינוי פרטים פנו אלינו.',
              'rejected' => 'האימות לא אושר: ${k['reason'] ?? ''}. תקנו ושלחו שוב.',
              _ => 'כדי שלקוחות יסמכו עליכם, כל מקצוען בזריז עובר אימות: פרטים, סלפי ותעודת זהות. זה לוקח 2 דקות, והבדיקה בדרך כלל עד יום עסקים.',
            },
            style: const TextStyle(height: 1.4),
          ),
        ),
        if (!locked) ...[
          const SectionTitle('פרטים אישיים'),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'שם מלא כמו בתעודת הזהות')),
          const SizedBox(height: 10),
          TextField(controller: id, keyboardType: TextInputType.number, maxLength: 9, decoration: const InputDecoration(labelText: 'מספר תעודת זהות', counterText: '')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            label: Text(birth == null ? 'תאריך לידה' : 'תאריך לידה: ${birth!.day}.${birth!.month}.${birth!.year}'),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: birth ?? DateTime(1990), firstDate: DateTime(1925), lastDate: DateTime.now(), initialDatePickerMode: DatePickerMode.year);
              if (d != null) setState(() => birth = d);
            },
          ),
          const SizedBox(height: 10),
          TextField(controller: city, decoration: const InputDecoration(labelText: 'עיר מגורים')),
          const SectionTitle('צילומים לאימות'),
          Text('משמשים רק לבדיקה שלנו. הלקוחות לא רואים אותם.', style: TextStyle(color: Pal.muted, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            _photoBox('selfie', 'סלפי', 'פנים ברורות, בלי משקפי שמש'),
            const SizedBox(width: 10),
            _photoBox('id', 'תעודת זהות', 'הצד עם התמונה, כל הפרטים קריאים'),
          ]),
          const SectionTitle('העסק'),
          DropdownButtonFormField<String>(
            initialValue: biz,
            decoration: const InputDecoration(labelText: 'סוג העסק'),
            items: const [
              DropdownMenuItem(value: 'none', child: Text('פרטי, בלי עסק (סידורים, שליחויות)')),
              DropdownMenuItem(value: 'exempt', child: Text('עוסק פטור')),
              DropdownMenuItem(value: 'licensed', child: Text('עוסק מורשה')),
              DropdownMenuItem(value: 'company', child: Text('חברה בע״מ')),
            ],
            onChanged: (v) => setState(() => biz = v),
          ),
          if (biz != null && biz != 'none') ...[
            const SizedBox(height: 10),
            TextField(controller: bizId, keyboardType: TextInputType.number, maxLength: 9, decoration: const InputDecoration(labelText: 'מספר עוסק / ח״פ', counterText: '')),
          ],
          const SizedBox(height: 10),
          TextField(controller: exp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'שנות ניסיון')),
          const SizedBox(height: 10),
          TextField(controller: bio, maxLength: 300, maxLines: 3, decoration: const InputDecoration(labelText: 'כמה מילים עליכם (לא חובה)')),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: terms,
            onChanged: (v) => setState(() => terms = v == true),
            title: const Text('קראתי ואני מסכים/ה לתנאי השימוש. הפרטים נכונים, אני מעל גיל 18, ואעבוד רק בתחומים שיש לי בהם הכשרה ורישיון כנדרש בחוק.',
                style: TextStyle(fontSize: 13, height: 1.4)),
          ),
          TextButton(onPressed: () => openLink(Api.url('/terms')), child: const Text('לקריאת תנאי השימוש')),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(err!, style: TextStyle(color: Pal.hot, fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: busy || uploading.isNotEmpty ? null : _send,
            icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.verified_user_rounded),
            label: const Text('שליחה לאימות', style: TextStyle(fontSize: 17)),
          ),
        ],
      ]),
    );
  }
}
