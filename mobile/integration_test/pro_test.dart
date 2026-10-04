import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zariz/main.dart' as app;

import 'helpers.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pro: go available, popup, accept, every step of the job', (t) async {
    app.main();
    await settle(t, 3000);
    await b.convertFlutterSurfaceToImage();
    await waitFor(t, find.text('שלחו לי קוד'));
    await shot(b, t, 'p1-login');
    await typeInto(t, field(0), 'דני לוי');
    await typeInto(t, field(1), '0503333333');
    await tapOn(t, find.text('שלחו לי קוד'));
    await waitFor(t, field(2));
    await settle(t, 800);
    await tapOn(t, find.widgetWithText(FilledButton, 'כניסה'));

    // fields chosen through the server (the domains screen is checked by a screenshot below)
    final pro = await login('0503333333', 'pro', 'דני לוי');
    await call('PUT', '/api/pro/me', token: pro, body: {'categories': ['plumbing'], 'serviceModes': ['onsite'], 'radiusKm': 30, 'location': {'lat': 32.09, 'lng': 34.79}});
    await waitFor(t, find.text('להתחיל לקבל קריאות'));
    await settle(t, 4000);
    await shot(b, t, 'p2-today');
    await tapOn(t, find.text('להתחיל לקבל קריאות'));
    await waitFor(t, find.text('זמינים · מחפשים קריאות'), secs: 30);
    await settle(t, 3000);
    await shot(b, t, 'p3-available');

    // a customer opens a fixed-price request nearby: it pops up
    final client = await login('0501111112', 'client', 'מירב');
    await call('POST', '/api/jobs', token: client, body: {
      'categoryId': 'plumbing.unclog', 'description': 'האסלה סתומה, צריך היום', 'address': 'דיזנגוף 80, תל אביב',
      'location': {'lat': 32.085, 'lng': 34.785}, 'clientPrice': 320, 'urgency': 'urgent',
    });
    await waitFor(t, find.textContaining('לאשר ולקבל'), secs: 30);
    await shot(b, t, 'p4-popup');
    await tapOn(t, find.textContaining('לאשר ולקבל'));
    await waitFor(t, find.text('לעבודה'), secs: 20);
    await shot(b, t, 'p5-won');
    await tapOn(t, find.text('לעבודה'));

    for (final step in ['יצאתי לדרך', 'הגעתי', 'התחלתי לטפל']) {
      await waitFor(t, find.text(step), secs: 20);
      await settle(t, 1500);
      await shot(b, t, 'p6-step-${step.hashCode.abs()}');
      await tapOn(t, find.text(step));
      await settle(t, 2500);
    }
    await waitFor(t, find.text('סיימתי'), secs: 20);
    await tapOn(t, find.text('סיימתי'));
    await waitFor(t, find.text('סיום העבודה'), secs: 10);
    await typeInto(t, lastField(), 'מירב');
    await shot(b, t, 'p7-sign');
    await tapOn(t, find.widgetWithText(FilledButton, 'סיימתי').last);
    await settle(t, 3000);
    final jobs = await call('GET', '/api/client/jobs', token: client) as List;
    expect(jobs.first['status'], 'completed');
    await shot(b, t, 'p8-done');

    await tapOn(t, find.text('עבודות'));
    await shot(b, t, 'p9-jobs');
    await tapOn(t, find.text('הכנסות'));
    await shot(b, t, 'p10-earnings');
    await tapOn(t, find.text('תחומים'));
    await shot(b, t, 'p11-domains');
    await tapOn(t, find.text('קריאות'));
    await shot(b, t, 'p12-feed');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
