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

  testWidgets('public signup remains locked during private beta', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.text('SIGN UP').first);
    await tester.pump();

    expect(find.text('CREATE YOUR ACCOUNT'), findsNothing);
    expect(find.textContaining('currently in private beta'), findsOneWidget);
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
    expect(find.text('PRIVATE BETA'), findsOneWidget);
    expect(find.text('RESPONSIBLE USE'), findsOneWidget);
    expect(find.text('LEARN MORE'), findsOneWidget);
    expect(find.text('BACK TO LOGIN'), findsOneWidget);
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
