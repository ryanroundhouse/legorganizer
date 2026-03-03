import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lego_bin/main.dart';

void main() {
  testWidgets('shows lego pieces from provided loader', (
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

    expect(find.text('Lego Pieces'), findsOneWidget);
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

  testWidgets('supports category filtering with clear control', (
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

    await tester.tap(find.byTooltip('Filter category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('brick'));
    await tester.pumpAndSettle();

    expect(find.text('Test Brick'), findsOneWidget);
    expect(find.text('Test Plate'), findsNothing);

    await tester.enterText(find.byType(TextField), 'test');
    await tester.pumpAndSettle();

    expect(find.text('Test Brick'), findsOneWidget);
    expect(find.text('Test Plate'), findsNothing);

    await tester.tap(find.byTooltip('Filter category'));
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

    await tester.tap(find.byTooltip('Filter category'));
    await tester.pumpAndSettle();
    expect(find.text('Box A'), findsOneWidget);
    expect(find.text('Box B'), findsOneWidget);

    await tester.tap(find.text('Box A'));
    await tester.pumpAndSettle();

    expect(find.text('Box A Brick'), findsOneWidget);
    expect(find.text('Box B Plate'), findsNothing);

    await tester.tap(find.byTooltip('Filter category'));
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
    expect(find.text('Delete'), findsOneWidget);
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

  testWidgets('long press allows deleting a piece',
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

    await tester.longPress(find.text('Test Part'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(savedPieces, isNotNull);
    expect(savedPieces, isEmpty);
    expect(find.text('No lego pieces found in JSON.'), findsOneWidget);
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
}
