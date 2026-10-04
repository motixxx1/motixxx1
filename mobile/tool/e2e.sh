#!/bin/bash
# Runs on the CI emulator: both apps against a local demo server, with screenshots.
set -x
adb wait-for-device
adb emu geo fix 34.7900 32.0900
mkdir -p ../shots
# grant location + notifications as soon as each app is installed (no system dialogs)
( while true; do for p in com.promarket.client com.promarket.pro; do
    for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do adb shell pm grant $p android.permission.$perm >/dev/null 2>&1; done
  done; sleep 1; done ) &
GRANT=$!
common="--dart-define=SERVER_URL=http://10.0.2.2:3000 --dart-define=FALLBACK_URL= --dart-define=SIDELOAD=false --driver=test_driver/integration_test.dart"
flutter drive --flavor pro --dart-define=APP=pro $common --target=integration_test/pro_test.dart 2>&1 | tee ../e2e-pro.txt
flutter drive --flavor client --dart-define=APP=client $common --target=integration_test/client_test.dart 2>&1 | tee ../e2e-client.txt
kill $GRANT
adb logcat -d -t 3000 > ../logcat.txt
ls -la ../shots
exit 0
