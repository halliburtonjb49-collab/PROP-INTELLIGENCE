import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/board_category_chip.dart';

void main() {
  testWidgets('category count uses the verdict-chip typography', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BoardCategoryChip(
            category: 'REBOUNDS',
            count: 18,
            icon: Icons.sports_basketball,
            selected: true,
            onPressed: () => selected = true,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('REBOUNDS 18'));
    expect(text.style?.fontSize, 9);
    expect(text.style?.fontWeight, FontWeight.w900);

    await tester.tap(find.byKey(const ValueKey('category-filter-REBOUNDS')));
    expect(selected, isTrue);
  });
}
