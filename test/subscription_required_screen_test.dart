import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/screens/paywall_screen.dart';

void main() {
  testWidgets('unpaid members can leave the required-plan screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SubscriptionRequiredScreen()),
    );

    expect(find.text('CHOOSE A PLAN TO CONTINUE'), findsOneWidget);
    expect(find.text('CHOOSE CORE - \$24.99 / MONTH'), findsOneWidget);
    expect(find.text('CHOOSE PRO - \$59.99 / MONTH'), findsOneWidget);
    expect(find.text('FOUNDING PRO - \$49.99 / MONTH'), findsOneWidget);
    expect(
      find.text('CORE ANNUAL • \$249.99 / YEAR • 7-DAY FREE TRIAL'),
      findsOneWidget,
    );
    expect(find.text('SIGN OUT'), findsOneWidget);
  });
}
