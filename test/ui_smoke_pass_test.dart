import 'package:prop_intelligence/controllers/active_slip_controller.dart';
import 'package:prop_intelligence/main.dart';
import 'package:prop_intelligence/services/prop_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PropChatService.unreadCount.value = 0;
  });

  tearDown(() {
    PropChatService.unreadCount.value = 0;
  });

  testWidgets('chat mentions and direct contacts show gold unread badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    PropChatService.unreadCount.value = 3;
    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      find.byKey(const ValueKey('board-prop-chat-button')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('prop-chat-bubble-launcher')),
        matching: find.byKey(const ValueKey('chat-unread-badge')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-prop-chat-button')).first,
        matching: find.text('3'),
      ),
      findsNothing,
      reason: 'The badge sits above the button without changing its label.',
    );
    expect(find.text('3'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board controls match the prop-site control size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    final siteSelector = find.byKey(const ValueKey('all-prop-sites-menu'));
    final chatButton = find.byKey(const ValueKey('board-prop-chat-button'));
    final filterButton = find.byKey(const ValueKey('board-filter-button'));
    expect(siteSelector, findsOneWidget);
    expect(chatButton, findsOneWidget);
    expect(filterButton, findsOneWidget);
    final siteButton = find.descendant(
      of: siteSelector,
      matching: find.byType(OutlinedButton),
    );
    expect(siteButton, findsOneWidget);
    expect(tester.getSize(chatButton), tester.getSize(siteButton));
    expect(tester.getSize(filterButton), tester.getSize(siteButton));
    expect(
      find.descendant(of: chatButton, matching: find.text('PROP CHAT')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow phone board controls fit without horizontal overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    final siteSelector = find.byKey(const ValueKey('all-prop-sites-menu'));
    final chatButton = find.byKey(const ValueKey('board-prop-chat-button'));
    final filterButton = find.byKey(const ValueKey('board-filter-button'));
    final controlRail = find.byKey(const ValueKey('prop-sites-scroll-list'));
    expect(siteSelector, findsOneWidget);
    expect(chatButton, findsOneWidget);
    expect(filterButton, findsOneWidget);
    expect(controlRail, findsOneWidget);

    final siteWidth = tester.getSize(siteSelector).width;
    final railWidth = tester.getSize(controlRail).width;
    expect(tester.getSize(chatButton).width, closeTo(siteWidth, .01));
    expect(tester.getSize(filterButton).width, closeTo(siteWidth, .01));
    expect((siteWidth * 3) + 12, lessThanOrEqualTo(railWidth + .01));
    expect(tester.takeException(), isNull);
  });
  testWidgets('smoke: scoreboard, analytics, line movement top navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    // Destinations are grouped now, so the bar carries the five groups
    // rather than every page at once.
    for (final group in ['RESEARCH', 'BUILD', 'LIVE', 'HISTORY', 'SPORTS']) {
      expect(find.byKey(ValueKey('nav-group-$group')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('top-navigation-scrollbar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tier-badge-core')), findsWidgets);
    expect(find.byKey(const ValueKey('tier-badge-edge')), findsWidgets);
    expect(find.byKey(const ValueKey('global-sound-toggle')), findsOneWidget);
    expect(find.byIcon(Icons.visibility_rounded), findsWidgets);
    expect(
      find.byKey(const ValueKey('prop-sites-scroll-left')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prop-sites-scroll-right')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prop-sites-scroll-list')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('all-prop-sites-menu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('all-prop-sites-menu')));
    await tester.pumpAndSettle();
    expect(find.text('PICK6'), findsWidgets);
    await tester.tap(find.text('PICK6').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('all-prop-sites-menu')),
        matching: find.text('PICK6'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('global-sound-toggle')));
    await tester.pump();
    expect(find.byIcon(Icons.mouse_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('nav-group-SPORTS')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-entry-gameMarkets')));
    await tester.pumpAndSettle();
    expect(find.text('MONEYLINE'), findsOneWidget);
    expect(find.text('SPREADS'), findsOneWidget);
    expect(find.text('GAME TOTALS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('nav-group-LIVE')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-entry-scoreboard')));
    await tester.pumpAndSettle();
    expect(find.text('ALL GAMES'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('nav-group-RESEARCH')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-entry-analytics')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('nav-group-RESEARCH')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-entry-lineMovement')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('nav-group-RESEARCH')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-entry-injuryImpact')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('injury-impact-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('smoke: active slip startup and add/remove interactions', () async {
    final controller = ActiveSlipController();
    await controller.load();

    expect(controller.legCount, 0);
    expect(controller.isEmpty, true);

    final added = await controller.addLegs([
      {
        'prop_id': 'smoke-prop-1',
        'player': 'Smoke Test Player',
        'sport': 'MLB',
        'market': 'Hits',
        'line': 0.5,
        'side': 'OVER',
        'odds': -110,
      },
    ]);

    expect(added, 1);
    expect(controller.legCount, 1);

    await controller.removeLeg('smoke-prop-1');
    expect(controller.legCount, 0);
    expect(controller.isEmpty, true);
  });

  testWidgets('smoke: every primary workspace destination opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('ELITE ACTIVE'), findsNothing);

    Future<void> openWorkspace(String label, String? expected) async {
      final destination = find.text(label);
      expect(destination, findsOneWidget);
      await tester.ensureVisible(destination);
      await tester.tap(destination);
      await tester.pump(const Duration(milliseconds: 1200));
      if (expected != null) {
        expect(find.text(expected), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byKey(const ValueKey('board-prop-chat-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('PROP CHAT'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('pop-out-prop-chat')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('floating-prop-chat')), findsOneWidget);
    // The board is still underneath. Asserted on the board's own search
    // field now that BOARD is a menu entry rather than a bar label.
    expect(find.byKey(const ValueKey('board-player-search')), findsWidgets);
    final floatingChatSize = tester.getSize(
      find.byKey(const ValueKey('floating-prop-chat')),
    );
    expect(floatingChatSize.height, lessThan(844 * .75));
    final beforeDrag = tester.getTopLeft(
      find.byKey(const ValueKey('floating-prop-chat')),
    );
    await tester.drag(
      find.byKey(const ValueKey('floating-prop-chat-drag-handle')),
      const Offset(90, 55),
    );
    await tester.pump();
    final afterDrag = tester.getTopLeft(
      find.byKey(const ValueKey('floating-prop-chat')),
    );
    expect(afterDrag.dx, greaterThan(beforeDrag.dx));
    expect(afterDrag.dy, greaterThan(beforeDrag.dy));

    await openWorkspace('THE LAB', 'INTELLIGENCE LAB');
    expect(find.byKey(const ValueKey('floating-prop-chat')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-floating-prop-chat')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('floating-prop-chat')), findsNothing);
    expect(
      find.byKey(const ValueKey('restore-prop-chat-bubble')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('close-prop-chat-bubble')),
      findsNothing,
    );
    await openWorkspace('PROP BUILDER', 'PROP BUILDER');
    await openWorkspace('BUILD\nPERFORM', null);
    await openWorkspace('EV SCANNER', 'EV SCANNER');
    await openWorkspace('STRIKEOUT\nPRO GOLD', 'STRIKEOUT PRO GOLD');
    await tester.tap(find.byKey(const ValueKey('strikeout-model-methodology')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('XGBOOST + LIGHTGBM'), findsOneWidget);
    expect(find.text('POISSON / COUNT MODEL'), findsOneWidget);
    expect(find.text('RANDOM FOREST'), findsOneWidget);
    expect(find.text('LSTM SEQUENCE MODEL'), findsOneWidget);
  });

  testWidgets('mobile PROP CHAT bubble opens over the board', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PropIntelligenceApp());
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      tester.takeException(),
      isNull,
      reason: 'initial mobile board must fit',
    );
    expect(
      find.byKey(const ValueKey('prop-chat-bubble-launcher')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('prop-chat-bubble-launcher')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('floating-prop-chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-player-search')), findsWidgets);
    expect(
      find.byKey(const ValueKey('prop-chat-message-field')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mobile-nav-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('floating-prop-chat')), findsNothing);
    expect(tester.takeException(), isNull, reason: 'mobile drawer must fit');
    expect(
      find.byKey(const ValueKey('mobile-sidebar-prop-chat')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('mobile-sidebar-prop-chat')));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('PROP CHAT'), findsWidgets);
    expect(find.byKey(const ValueKey('pop-out-prop-chat')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('restore-prop-chat-bubble')),
      findsOneWidget,
    );
    tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('restore-prop-chat-bubble')),
        )
        .onPressed!
        .call();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('restore-prop-chat-bubble')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prop-chat-bubble-launcher')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('prop-chat-message-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
