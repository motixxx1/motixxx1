import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'client/client_app.dart';
import 'core/api.dart';
import 'core/ui.dart';
import 'pro/pro_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const ZarizApp());
}

class ZarizApp extends StatelessWidget {
  const ZarizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: isPro ? 'זריז מקצוענים' : 'זריז',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: isPro ? const ProRoot() : const ClientRoot(),
    );
  }
}
