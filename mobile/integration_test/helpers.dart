import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

const server = 'http://10.0.2.2:3000';

Future<void> waitFor(WidgetTester t, Finder f, {int secs = 40}) async {
  for (var i = 0; i < secs * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Not found on screen: $f');
}

/// Only what is actually on screen (tabs and earlier pages stay in the tree, hidden).
Finder vis(Finder f) => f.hitTestable();
Finder field(int i) => find.byType(TextField).hitTestable().at(i);
Finder lastField() => find.byType(TextField).hitTestable().last;

Future<void> tapOn(WidgetTester t, Finder f0) async {
  final f = f0.hitTestable();
  await waitFor(t, f);
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pump(const Duration(milliseconds: 400));
  try {
    await t.ensureVisible(f.first);
  } catch (_) {}
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> typeInto(WidgetTester t, Finder f, String text) async {
  await waitFor(t, f);
  await t.enterText(f, text);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> settle(WidgetTester t, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(IntegrationTestWidgetsFlutterBinding b, WidgetTester t, String name) async {
  await settle(t, 1200);
  await b.takeScreenshot(name);
  // ignore: avoid_print
  print('SHOT $name');
}

/// Direct calls to the server, playing the other side (customer or pro).
Future<dynamic> call(String method, String path, {Object? body, String? token}) async {
  final req = http.Request(method, Uri.parse('$server$path'));
  req.headers['content-type'] = 'application/json';
  if (token != null) req.headers['authorization'] = 'Bearer $token';
  if (body != null) req.body = jsonEncode(body);
  final r = await http.Response.fromStream(await req.send());
  final data = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  if (r.statusCode >= 400) throw Exception('$method $path -> ${r.statusCode} ${r.body}');
  return data;
}

Future<String> login(String phone, String role, String name) async {
  final c = await call('POST', '/api/auth/request', body: {'phone': phone});
  final r = await call('POST', '/api/auth/verify', body: {'phone': phone, 'code': c['devCode'], 'role': role, 'name': name});
  return r['token'] as String;
}
