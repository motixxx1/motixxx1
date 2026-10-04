import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

// Saves the screenshots the tests take into ../shots.
Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final f = File('../shots/$name.png');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(bytes);
        return true;
      },
    );
