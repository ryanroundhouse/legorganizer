import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lego_bin/main.dart';
import 'package:lego_bin/ui/design_tokens.dart';

void _noop() {}

class _TestAssetBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'assets/data/parts.csv') {
      return 'part_num,name,part_cat_id,part_material\n3009,Brick 1 x 6,7,Plastic\n';
    }
    if (key == PieceGridScreen.dataPath) {
      return '[]';
    }
    return super.loadString(key, cache: cache);
  }

  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/data/parts.csv') {
      final bytes = Uint8List.fromList(
        utf8.encode(
          'part_num,name,part_cat_id,part_material\n3009,Brick 1 x 6,7,Plastic\n',
        ),
      );
      return ByteData.view(bytes.buffer);
    }
    if (key == PieceGridScreen.dataPath) {
      final bytes = Uint8List.fromList(utf8.encode('[]'));
      return ByteData.view(bytes.buffer);
    }
    throw FlutterError('Asset not found: $key');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('donation prompt waits 30 days, then repeats every 30 days', () async {
    final controller = DonationPromptController();
    final prefs = await SharedPreferences.getInstance();
    final installDate = DateTime(2026, 1, 1);

    expect(
      await controller.shouldShowPrompt(now: installDate, prefs: prefs),
      isFalse,
    );

    expect(
      await controller.shouldShowPrompt(
        now: installDate.add(const Duration(days: 29)),
        prefs: prefs,
      ),
      isFalse,
    );

    expect(
      await controller.shouldShowPrompt(
        now: installDate.add(const Duration(days: 30)),
        prefs: prefs,
      ),
      isTrue,
    );

    await controller.markPromptShown(
      now: installDate.add(const Duration(days: 30)),
      prefs: prefs,
    );

    expect(
      await controller.shouldShowPrompt(
        now: installDate.add(const Duration(days: 59)),
        prefs: prefs,
      ),
      isFalse,
    );

    expect(
      await controller.shouldShowPrompt(
        now: installDate.add(const Duration(days: 60)),
        prefs: prefs,
      ),
      isTrue,
    );
  });

  testWidgets('shows LEGO pieces from provided loader', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 99',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
            LegoPiece(
              name: 'Slope Brick',
              bin: 'Bin 17',
              legoId: '12345',
              present: true,
              imageAsset: 'assets/pieces/12345.png',
            ),
          ],
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Legorganizer'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Test Part'), findsOneWidget);
    expect(find.text('ID: 99999'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'slope');
    await tester.pump();

    expect(find.text('Slope Brick'), findsOneWidget);
    expect(find.text('Test Part'), findsNothing);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();

    expect(find.text('Slope Brick'), findsOneWidget);
    expect(find.text('Test Part'), findsNothing);
  });

  testWidgets('uses adaptive grid delegate', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Adaptive Brick',
              bin: 'Bin 1',
              legoId: '11111',
              present: true,
              imageAsset: 'assets/pieces/11111.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      grid.gridDelegate,
      isA<SliverGridDelegateWithMaxCrossAxisExtent>(),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.maxCrossAxisExtent, AppGrid.maxCrossAxisExtent);
  });

  testWidgets('supports category filtering with chips and clear control', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Brick',
              bin: 'Bin 1',
              legoId: '11111',
              present: true,
              imageAsset: 'assets/pieces/11111.png',
              partCatId: '11',
            ),
            LegoPiece(
              name: 'Test Plate',
              bin: 'Bin 2',
              legoId: '22222',
              present: true,
              imageAsset: 'assets/pieces/22222.png',
              partCatId: '14',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Test Brick'), findsOneWidget);
    expect(find.text('Test Plate'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter pieces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('brick'));
    await tester.pumpAndSettle();

    expect(find.text('Test Brick'), findsOneWidget);
    expect(find.text('Test Plate'), findsNothing);
    expect(find.text('Clear all'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'test');
    await tester.pumpAndSettle();

    expect(find.text('Test Brick'), findsOneWidget);
    expect(find.text('Test Plate'), findsNothing);

    await tester.tap(find.byTooltip('Filter pieces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear category'));
    await tester.pumpAndSettle();

    expect(find.text('Test Brick'), findsOneWidget);
    expect(find.text('Test Plate'), findsOneWidget);
  });

  testWidgets('supports box filtering from filter dialog', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Box A Brick',
              bin: 'Box A',
              legoId: '31111',
              present: true,
              imageAsset: 'assets/pieces/31111.png',
              partCatId: '11',
            ),
            LegoPiece(
              name: 'Box B Plate',
              bin: 'Box B',
              legoId: '32222',
              present: true,
              imageAsset: 'assets/pieces/32222.png',
              partCatId: '14',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter pieces'));
    await tester.pumpAndSettle();
    expect(find.text('Box A'), findsOneWidget);
    expect(find.text('Box B'), findsOneWidget);

    await tester.tap(find.text('Box A'));
    await tester.pumpAndSettle();

    expect(find.text('Box A Brick'), findsOneWidget);
    expect(find.text('Box B Plate'), findsNothing);

    await tester.tap(find.byTooltip('Filter pieces'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear box'));
    await tester.pumpAndSettle();

    expect(find.text('Box A Brick'), findsOneWidget);
    expect(find.text('Box B Plate'), findsOneWidget);
  });

  testWidgets('long press allows editing and saving bin value', (
    WidgetTester tester,
  ) async {
    List<LegoPiece>? savedPieces;
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 99',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
          piecesSaver: (pieces) async {
            savedPieces = pieces;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.longPress(find.text('Test Part'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete piece'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Shelf A',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedPieces, isNotNull);
    expect(savedPieces!.single.bin, 'Shelf A');
  });

  testWidgets('menu actions allow deleting a piece',
      (WidgetTester tester) async {
    List<LegoPiece>? savedPieces;
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 99',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
          piecesSaver: (pieces) async {
            savedPieces = pieces;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Piece actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete piece'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(savedPieces, isNotNull);
    expect(savedPieces, isEmpty);
    expect(find.text('No pieces yet'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('empty home state exposes import and add actions', (
    WidgetTester tester,
  ) async {
    var didRequestAdd = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [],
          onAddRequested: () {
            didRequestAdd = true;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No pieces yet'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(didRequestAdd, isTrue);
  });

  testWidgets('hamburger menu opens options screen with collection actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 99',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();

    expect(find.text('Options'), findsOneWidget);
    expect(find.text('Import collection'), findsOneWidget);
    expect(find.text('Export collection'), findsOneWidget);
    expect(find.text('Clear collection'), findsWidgets);
  });

  testWidgets('about dialog includes optional donation link', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 99',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('About Legorganizer'), findsOneWidget);
    expect(
      find.textContaining('independent developer building this for fun'),
      findsOneWidget,
    );
    expect(find.text('Support Legorganizer with a donation'), findsOneWidget);
  });

  testWidgets('donation prompt appears after the first 30 days', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'donation_install_timestamp_ms':
          now.subtract(const Duration(days: 31)).millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 99',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Enjoying Legorganizer?'), findsOneWidget);
    expect(find.text('Maybe later'), findsOneWidget);
    expect(find.text('Donate'), findsOneWidget);
  });

  testWidgets('clear collection requires confirmation and deletes all pieces', (
    WidgetTester tester,
  ) async {
    List<LegoPiece>? savedPieces;

    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Brick A',
              bin: 'Bin 1',
              legoId: '11111',
              present: true,
              imageAsset: 'assets/pieces/11111.png',
            ),
            LegoPiece(
              name: 'Brick B',
              bin: 'Bin 2',
              legoId: '22222',
              present: true,
              imageAsset: 'assets/pieces/22222.png',
            ),
          ],
          piecesSaver: (pieces) async {
            savedPieces = pieces;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear collection').first);
    await tester.pumpAndSettle();

    expect(find.text('Clear collection?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(savedPieces, isNull);

    await tester.tap(find.text('Clear collection').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear collection'));
    await tester.pumpAndSettle();

    expect(savedPieces, isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('No pieces yet'), findsOneWidget);
  });

  testWidgets('shows bin number badge when bin contains a number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 42',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('does not show bin number badge when bin has no number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Unknown Bin',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('bin number text scales to fit inside red circle', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Test Part',
              bin: 'Bin 123456',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('123456'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows clear empty-state action when no search results', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PieceGridScreen(
          piecesLoader: () async => const [
            LegoPiece(
              name: 'Only Part',
              bin: 'Bin 42',
              legoId: '99999',
              present: true,
              imageAsset: 'assets/pieces/99999.png',
            ),
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no-match');
    await tester.pumpAndSettle();

    expect(find.text('No matching pieces'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('add screen renders safely on compact screens', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _TestAssetBundle(),
        child: const MaterialApp(
          home: AddPieceScreen(onBackHome: _noop),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AddPieceScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
