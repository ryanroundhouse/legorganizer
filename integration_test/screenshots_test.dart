// Captures App Store screenshots. Run with:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart -d <simulator>
// PNGs land in build/screenshots/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lego_bin/main.dart' as app;

Future<void> settle(WidgetTester tester, [int seconds = 3]) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture store screenshots', (tester) async {
    app.main();
    await settle(tester, 6);
    await binding.takeScreenshot('01-home');

    await tester.tap(find.byIcon(Icons.filter_list));
    await settle(tester, 2);
    await binding.takeScreenshot('02-filter');
    await tester.tapAt(const Offset(20, 100));
    await settle(tester, 1);

    await tester.enterText(find.byType(TextField).first, 'plate');
    await settle(tester, 4);
    await binding.takeScreenshot('03-search');
    await tester.enterText(find.byType(TextField).first, '');
    await settle(tester, 1);

    await tester.tap(find.text('Add'));
    await settle(tester, 3);
    await binding.takeScreenshot('04-add');

    await tester.tap(find.text('Home'));
    await settle(tester, 2);
    await tester.tap(find.byIcon(Icons.menu));
    await settle(tester, 2);
    await binding.takeScreenshot('05-menu');
  });
}
