import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/pages/search_players_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clearing player search resets its field and semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchPlayersPage(props: []))),
    );
    await tester.pump();

    final initialField = find.byKey(const ValueKey('player-search-input-0'));
    expect(initialField, findsOneWidget);
    await tester.enterText(initialField, 'Brandon Lowe');
    await tester.pump();
    expect(
      tester.widget<TextField>(initialField).controller?.text,
      'Brandon Lowe',
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    final clearedField = find.byType(TextField);
    expect(clearedField, findsOneWidget);
    semantics.dispose();
    expect(tester.widget<TextField>(clearedField).controller?.text, isEmpty);
    expect(tester.getSemantics(clearedField).value, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
