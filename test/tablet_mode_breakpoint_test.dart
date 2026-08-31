import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/layout/app_shell.dart';
import 'package:prop_intelligence/layout/responsive_breakpoints.dart';
import 'package:prop_intelligence/services/app_sound_service.dart';
import 'package:prop_intelligence/widgets/prop_grid.dart';

void main() {
  group('responsive application modes', () {
    test('phone mode ends immediately before 600 logical pixels', () {
      expect(ResponsiveBreakpoints.isPhone(320), isTrue);
      expect(ResponsiveBreakpoints.isPhone(599.9), isTrue);
      expect(ResponsiveBreakpoints.isPhone(600), isFalse);
      expect(usePhoneShell(599.9), isTrue);
      expect(usePhoneShell(600), isFalse);
    });

    test('tablet mode owns 600 through 999 logical pixels', () {
      expect(ResponsiveBreakpoints.isTablet(599.9), isFalse);
      expect(ResponsiveBreakpoints.isTablet(600), isTrue);
      expect(ResponsiveBreakpoints.isTablet(820), isTrue);
      expect(ResponsiveBreakpoints.isTablet(999.9), isTrue);
      expect(ResponsiveBreakpoints.isTablet(1000), isFalse);
      expect(useTabletShell(820), isTrue);
      expect(useTabletPropTable(820), isTrue);
    });

    test('desktop mode begins at 1000 logical pixels', () {
      expect(ResponsiveBreakpoints.isDesktop(999.9), isFalse);
      expect(ResponsiveBreakpoints.isDesktop(1000), isTrue);
      expect(useTabletShell(1000), isFalse);
      expect(useTabletPropTable(1000), isFalse);
    });
  });

  testWidgets('tablet shell displays branded header and bottom navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          leftSidebar: const Center(child: Text('WORKSPACE NAVIGATION')),
          topNavigation: const Center(child: Text('DESKTOP COMMAND BAR')),
          content: const Center(child: Text('PRIMARY WORKSPACE')),
          accountPanel: const Center(child: Text('ACCOUNT PANEL')),
          activeSlipPanel: const Center(child: Text('ACTIVE SLIP PANEL')),
          activeSlipCount: 2,
          watchedSlipCount: 1,
          soundService: AppSoundService.instance,
          isOwner: false,
          ownerOperationsSelected: false,
          onOpenOwnerOperations: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('tablet-header-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('tablet-header-account')), findsOneWidget);
    expect(find.byKey(const ValueKey('tablet-nav-board')), findsOneWidget);
    expect(find.byKey(const ValueKey('tablet-nav-scoreboard')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-board')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-ticket')), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-header-menu')), findsNothing);
    expect(find.text('PRIMARY WORKSPACE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
