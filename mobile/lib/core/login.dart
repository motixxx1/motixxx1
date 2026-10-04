import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Phone + SMS code. New users are created on the first login.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onDone});
  final void Function(J result) onDone;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final code = TextEditingController();
  final ref = TextEditingController();
  bool codeSent = false, busy = false;
  String err = '';

  @override
  void initState() {
    super.initState();
    name.text = Api.prefs.getString('name') ?? '';
  }

  Future<void> submit() async {
    setState(() => err = '');
    if (name.text.trim().isEmpty) {
      setState(() => err = 'כתבו את השם שלכם');
      return;
    }
    if (phone.text.trim().length < 9) {
      setState(() => err = 'כתבו מספר טלפון נייד');
      return;
    }
    setState(() => busy = true);
    try {
      if (!codeSent) {
        final r = asMap(await Api.post('/api/auth/request', {'phone': phone.text.trim()}));
        if (r['devCode'] != null) code.text = r['devCode'].toString(); // demo server only
        setState(() => codeSent = true);
      } else {
        if (code.text.trim().isEmpty) {
          setState(() => err = 'כתבו את הקוד מההודעה');
        } else {
          final r = asMap(await Api.post('/api/auth/verify', {
            'phone': phone.text.trim(),
            'code': code.text.trim(),
            'role': appKind,
            'name': name.text.trim(),
            if (isPro && ref.text.trim().isNotEmpty) 'referralCode': ref.text.trim(),
          }));
          await Api.setToken(r['token']?.toString());
          await Api.prefs.setString('name', asMap(r['user'])['name']?.toString() ?? name.text.trim());
          widget.onDone(r);
        }
      }
    } on ApiError catch (e) {
      setState(() => err = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 28),
          children: [
            Row(children: [
              const Brand(size: 56),
              if (isPro) ...[const SizedBox(width: 10), const Tag('מקצוענים')],
            ]),
            const SizedBox(height: 26),
            Text(isPro ? 'כל מומחיות יכולה להרוויח' : 'כניסה',
                style: TextStyle(fontSize: 30 * fs, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 8),
            Text(isPro ? 'נרשמים בדקה ומתחילים לקבל קריאות באזור שלכם.' : 'שם וטלפון. נשלח לכם קוד בהודעת SMS.',
                style: TextStyle(color: Pal.muted, fontSize: 16 * fs)),
            const SizedBox(height: 24),
            _label('השם שלכם'),
            TextField(controller: name, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.name]),
            _label('מספר טלפון נייד'),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              autofillHints: const [AutofillHints.telephoneNumber],
              enabled: !codeSent,
            ),
            if (isPro && !codeSent) ...[
              _label('קוד חבר שהזמין אתכם (לא חובה)'),
              TextField(controller: ref, textCapitalization: TextCapitalization.characters),
            ],
            if (codeSent) ...[
              _label('הקוד שקיבלתם ב-SMS'),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                autofocus: true,
                autofillHints: const [AutofillHints.oneTimeCode],
                style: const TextStyle(letterSpacing: 4, fontSize: 22),
              ),
            ],
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err, style: TextStyle(color: Pal.hot, fontSize: 15 * fs))),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                  : Text(codeSent ? 'כניסה' : 'שלחו לי קוד'),
            ),
            if (codeSent)
              TextButton(
                onPressed: busy ? null : () => setState(() { codeSent = false; code.clear(); }),
                child: const Text('לשנות מספר / לשלוח קוד שוב'),
              ),
            const SizedBox(height: 24),
            Wrap(alignment: WrapAlignment.center, spacing: 16, children: [
              TextButton(onPressed: () => openLink(Api.url('/privacy')), child: const Text('מדיניות פרטיות')),
              TextButton(onPressed: () => openLink(Api.url('/terms')), child: const Text('תנאי שימוש')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16 * fs)),
      );
}
