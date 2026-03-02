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
  });

  testWidgets('long press allows editing and saving bin value', (
    WidgetTester tester,
  ) async {
    List<LegoPiece>? savedPieces;

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
}
