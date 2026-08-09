import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/auth_manager.dart';
import 'package:prop_intelligence/widgets/sidebar_button.dart';

void main() {
  testWidgets('renders selection, badge, tier and trailing state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SidebarButton(
                label: 'SLIP WATCHER',
                selected: true,
                badge: '3',
                showGoldBar: true,
                trailingIcon: Icons.visibility_rounded,
                trailingIconKey: ValueKey('sidebar-trailing'),
              ),
              SidebarButton(
                label: 'THE LAB',
                requiredTier: SubscriptionTier.edge,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('SLIP WATCHER'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-trailing')), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
  });

  testWidgets('forwards taps', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidebarButton(
            label: 'GAME MARKETS',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('GAME MARKETS'));
    expect(tapped, isTrue);
  });
}
