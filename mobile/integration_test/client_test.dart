import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zariz/main.dart' as app;

import 'helpers.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer: login, new request, live tracking', (t) async {
    // a pro near the customer, available for plumbing
    final pro = await login('0502222222', 'pro', 'יוסי כהן');
    await call('PUT', '/api/pro/me', token: pro, body: {'categories': ['plumbing'], 'serviceModes': ['onsite'], 'radiusKm': 30, 'location': {'lat': 32.09, 'lng': 34.79}});
    await call('PUT', '/api/pro/availability', token: pro, body: {'available': true});

    app.main();
    await settle(t, 3000);
    await b.convertFlutterSurfaceToImage();
    await waitFor(t, find.text('שלחו לי קוד'));
    await shot(b, t, 'c1-login');
    await typeInto(t, loginField(0), 'רחל');
    await typeInto(t, loginField(1), '0501111111');
    await tapOn(t, find.text('שלחו לי קוד'));
    await waitFor(t, loginField(2));
    await settle(t, 800);
    await tapOn(t, find.widgetWithText(FilledButton, 'כניסה'));

    await waitFor(t, find.text('במה אפשר לעזור?'));
    await waitFor(t, find.text('אחר כך'), secs: 10).then((_) => shot(b, t, 'c2-promo')).catchError((_) {});
    if (find.text('אחר כך').evaluate().isNotEmpty) await tapOn(t, find.text('אחר כך'));
    await shot(b, t, 'c3-home');

    await tapOn(t, find.text('משהו התקלקל בבית'));
    await shot(b, t, 'c4-what');
    await tapOn(t, find.text('סתימה בכיור או באסלה'));
    await typeInto(t, field(0), 'הכיור במטבח סתום');
    await shot(b, t, 'c5-desc');
    await tapUntil(t, find.text('המשך'), find.text('לאיזו כתובת להגיע?'));
    await typeInto(t, field(0), 'הרצל 10, תל אביב');
    await tapUntil(t, find.text('המשך'), find.text('כמה שיותר מהר'));
    await tapOn(t, find.text('כמה שיותר מהר'));
    await tapOn(t, find.text('אני קובע/ת מחיר'));
    await typeInto(t, field(0), '300');
    await shot(b, t, 'c6-price');
    await tapOn(t, find.text('המשך'));
    await waitFor(t, find.text('הכל נכון?'));
    await shot(b, t, 'c7-summary');
    await tapOn(t, find.text('שליחת הקריאה'));
    await waitFor(t, find.text('הקריאה נשלחה'));
    await shot(b, t, 'c8-sent');

    // the pro takes it and drives over: the customer sees him on the map
    final feed = await call('GET', '/api/pro/feed', token: pro) as List;
    final id = feed.first['id'];
    await call('POST', '/api/jobs/$id/take', token: pro, body: {});
    await call('PUT', '/api/pro/location', token: pro, body: {'lat': 32.095, 'lng': 34.795});
    await call('POST', '/api/jobs/$id/status', token: pro, body: {'status': 'en_route'});
    await waitFor(t, find.text('דקות'), secs: 30);
    await settle(t, 9000); // let the map tiles load
    await shot(b, t, 'c9-live');
    await call('PUT', '/api/pro/location', token: pro, body: {'lat': 32.0805, 'lng': 34.7805});
    await call('POST', '/api/jobs/$id/status', token: pro, body: {'status': 'arrived'});
    await waitFor(t, find.text('צאו לפגוש אותו'), secs: 30);
    await settle(t, 5000);
    await shot(b, t, 'c10-arrived');
    await call('POST', '/api/jobs/$id/status', token: pro, body: {'status': 'in_progress'});
    await call('POST', '/api/jobs/$id/status', token: pro, body: {'status': 'completed', 'signature': 'רחל'});
    await waitFor(t, find.text('הכל תקין, סיימנו'), secs: 30);
    await tapOn(t, find.text('הכל תקין, סיימנו'));
    await waitFor(t, find.text('איך היה?'), secs: 30);
    await shot(b, t, 'c11-rate');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
