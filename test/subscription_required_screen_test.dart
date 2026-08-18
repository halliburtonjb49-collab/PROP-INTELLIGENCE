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

  testWidgets('plan sheet remains scrollable on a short screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(639, 632));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const BrandedPaywallModalSheet(),
              ),
              child: const Text('OPEN PLANS'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN PLANS'));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('RESTORE PURCHASES'),
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );

    expect(
      find.text('FOUNDING PRO - \$49.99 / MONTH').hitTestable(),
      findsOneWidget,
    );
    expect(find.text('RESTORE PURCHASES').hitTestable(), findsOneWidget);
  });
}
