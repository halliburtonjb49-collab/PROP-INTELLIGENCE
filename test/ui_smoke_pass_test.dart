import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';

void main() {
  testWidgets('current app shell renders across supported viewport classes', (
    tester,
  ) async {
    for (final size in const [
      Size(320, 700),
      Size(390, 844),
      Size(768, 1024),
      Size(1366, 768),
      Size(1920, 1080),
      Size(2560, 1080),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const PropIntelligenceApp());
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PropIntelligenceApp), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'shell must fit $size');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 2100));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('mobile shell exposes the current primary navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('mobile-nav-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-board')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-games')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-watchlist')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-ticket')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 2100));
  });
}
