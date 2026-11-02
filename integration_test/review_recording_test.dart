// Drives the app through a typical session for an App Review screen
// recording. Record the simulator while this runs:
//   xcrun simctl io <udid> recordVideo --codec h264 review.mp4 &
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/review_recording_test.dart -d <udid>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lego_bin/main.dart' as app;

Future<void> settle(WidgetTester tester, [double seconds = 3]) async {
  for (var i = 0; i < (seconds * 4).round(); i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> typeSlowly(WidgetTester tester, Finder field, String text) async {
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(field, text.substring(0, i));
    await settle(tester, 0.5);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typical user flow for App Review', (tester) async {
    app.main();
    await settle(tester, 5);

    // Add a new part (not in the starter inventory) to a bin.
    await tester.tap(find.text('Add'));
    await settle(tester, 3);
    final legoId = find.widgetWithText(TextField, 'LEGO ID');
    await typeSlowly(tester, legoId, '2357');
    await settle(tester, 4);
    final bin = find.widgetWithText(TextField, 'Bin');
    await typeSlowly(tester, bin, 'Bin A');
    await settle(tester, 2);
    await tester.tap(find.text('Add to inventory'));
    await settle(tester, 4);

    // Assign a bin to a part that is already in the inventory.
    await typeSlowly(tester, legoId, '3001');
    await settle(tester, 4);
    await typeSlowly(tester, bin, 'Bin B');
    await settle(tester, 2);
    await tester.tap(find.text('Save bin'));
    await settle(tester, 4);

    // Back home, search and filter.
    await tester.tap(find.text('Home'));
    await settle(tester, 4);
    final search = find.byType(TextField).first;
    await typeSlowly(tester, search, 'brick');
    await settle(tester, 4);
    await tester.enterText(search, '');
    await settle(tester, 2);
    await tester.tap(find.byIcon(Icons.filter_list));
    await settle(tester, 4);
    await tester.tapAt(const Offset(20, 100));
    await settle(tester, 2);

    // Menu and About.
    await tester.tap(find.byIcon(Icons.menu));
    await settle(tester, 3);
    await tester.tap(find.text('About'));
    await settle(tester, 5);
    await tester.tap(find.text('Close'));
    await settle(tester, 3);
  });
}
