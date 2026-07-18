import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/interactive_prop_builder.dart';

void main() {
  for (final size in <Size>[const Size(1000, 720), const Size(520, 760)]) {
    testWidgets('prop builder is usable at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InteractiveConstructorEngineWidget()),
        ),
      );

      expect(find.text('PROP BUILDER'), findsOneWidget);
      expect(find.text('Choose a market'), findsOneWidget);
      expect(find.text('Set the line'), findsOneWidget);
      expect(find.text('ADD TO ACTIVE SLIP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
