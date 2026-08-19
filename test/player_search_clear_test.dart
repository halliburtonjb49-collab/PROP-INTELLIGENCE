import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('clearing player search regenerates its accessibility node', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    final initialField = find.byKey(const ValueKey('player-search-input-0'));
    expect(initialField, findsOneWidget);
    await tester.enterText(initialField, 'Brandon Lowe');
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.widget<TextField>(initialField).controller?.text,
      'Brandon Lowe',
    );
    expect(find.byKey(const ValueKey('active-board-filters')), findsOneWidget);
    expect(find.text('SEARCH: Brandon Lowe'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear player search'));
    await tester.pump();

    final clearedField = find.byKey(const ValueKey('player-search-input-1'));
    expect(clearedField, findsOneWidget);
    semantics.dispose();
    expect(tester.widget<TextField>(clearedField).controller?.text, isEmpty);
    // Clearing search removes only the search constraint. The board's
    // deliberate trust sort remains visible as an active preference.
    expect(find.byKey(const ValueKey('active-board-filters')), findsOneWidget);
    expect(find.text('SEARCH: Brandon Lowe'), findsNothing);
    expect(find.text('SORT: TRUST'), findsOneWidget);
    expect(tester.getSemantics(clearedField).value, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
