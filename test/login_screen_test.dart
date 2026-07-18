import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/screens/login_screen.dart';

void main() {
  testWidgets('login page renders the desktop composition', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('REAL-TIME DATA'), findsOneWidget);
    expect(
      find.textContaining('Advanced analytics. Real-time data'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login page matches the compact desktop composition', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(975, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('REAL-TIME DATA'), findsOneWidget);
    expect(find.text('SHARP ANALYTICS'), findsOneWidget);
    expect(find.text('HIGHER HIT RATE'), findsOneWidget);
    expect(find.text('MULTI-SPORT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public signup opens paid account creation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.text('SIGN UP').first);
    await tester.pump();

    expect(find.text('CREATE YOUR ACCOUNT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('brand button opens the product information panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.byTooltip('About PROP INTELLIGENCE'));
    await tester.pumpAndSettle();

    expect(find.text('WHAT YOU CAN DO'), findsOneWidget);
    expect(find.text('PAID MEMBERSHIP'), findsOneWidget);
    expect(find.text('RESPONSIBLE USE'), findsOneWidget);
    expect(find.text('LEARN MORE'), findsOneWidget);
    expect(find.text('BACK TO LOGIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pricing navigation explains every available tier', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.text('PRICING'));
    await tester.pumpAndSettle();

    expect(find.text('EXPLORE'), findsNothing);
    expect(find.text('FREE'), findsNothing);
    expect(find.text('CORE'), findsOneWidget);
    expect(find.text('PRO / EDGE'), findsOneWidget);
    expect(find.text(r'$29.99 / MONTH'), findsOneWidget);
    expect(find.text(r'$89.99 / MONTH'), findsOneWidget);
    expect(find.text('BEST VALUE'), findsOneWidget);
    expect(find.text('CHOOSE CORE'), findsOneWidget);
    expect(find.text('CHOOSE PRO / EDGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('features navigation reflects the complete research suite', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.text('FEATURES'));
    await tester.pumpAndSettle();

    expect(find.text('DISCOVER & COMPARE'), findsOneWidget);
    expect(find.text('MODEL INTELLIGENCE'), findsOneWidget);
    expect(find.text('BUILD & TRACK'), findsOneWidget);
    expect(find.text('ADVANCED EDGE TOOLS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terms are available from the public navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.text('TERMS'));
    await tester.pumpAndSettle();

    expect(find.text('TERMS & CONDITIONS'), findsOneWidget);
    expect(find.text('SUBSCRIPTIONS & BILLING'), findsOneWidget);
    expect(find.text('RESPONSIBLE PLAY'), findsOneWidget);
    expect(find.text('ACCOUNT RESPONSIBILITIES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login page stacks safely on a mobile viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(find.text('PROP INTELLIGENCE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
