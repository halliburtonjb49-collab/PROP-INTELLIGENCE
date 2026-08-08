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
    expect(find.text('Continue with Apple'), findsNothing);
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

    expect(find.text('CREATE YOUR LOGIN'), findsOneWidget);
    expect(find.text('Create App Password'), findsOneWidget);
    expect(find.text('Confirm App Password'), findsOneWidget);
    expect(find.textContaining('not your Gmail password'), findsOneWidget);
    expect(find.text('CONTINUE TO EMAIL VERIFICATION'), findsOneWidget);
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
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text(r'$24.99 / MONTH'), findsOneWidget);
    expect(find.text(r'$59.99 / MONTH'), findsOneWidget);
    expect(find.text('CHOOSE CORE'), findsOneWidget);
    expect(find.text('CHOOSE PRO'), findsOneWidget);
    expect(find.text('FOUNDING PRO'), findsOneWidget);
    expect(find.text(r'$49.99 / MONTH'), findsOneWidget);
    expect(
      find.text('Read and participate in the main Prop Chat room'),
      findsOneWidget,
    );
    expect(
      find.text('Pro sport rooms, game threads and direct messages'),
      findsOneWidget,
    );
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
    expect(find.text('PROP CHAT & ALERTS'), findsOneWidget);
    expect(find.text('ADVANCED EDGE TOOLS'), findsOneWidget);
    expect(
      find.text(
        'Poisson and Monte Carlo modeling with de-vigged market probabilities',
      ),
      findsOneWidget,
    );
    expect(
      find.text('A movable mobile chat bubble that keeps the board visible'),
      findsOneWidget,
    );
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

  testWidgets('privacy policy is available from the public navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.text('PRIVACY'));
    await tester.pumpAndSettle();

    expect(find.text('PRIVACY POLICY'), findsOneWidget);
    expect(find.text('DATA WE COLLECT'), findsOneWidget);
    expect(find.text('YOUR CHOICES'), findsOneWidget);
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

  testWidgets('mobile menu exposes public information and install guidance', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mobile-info-menu')));
    await tester.pumpAndSettle();

    expect(find.text('FEATURES'), findsOneWidget);
    expect(find.text('PRICING'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('TERMS'), findsOneWidget);
    expect(find.text('PRIVACY'), findsOneWidget);
    expect(find.text('CONTACT'), findsOneWidget);
    expect(find.text('INSTALL APP'), findsOneWidget);

    await tester.tap(find.text('INSTALL APP'));
    await tester.pumpAndSettle();
    expect(
      find.text('FAST, FULL-SCREEN ACCESS ON EVERY DEVICE'),
      findsOneWidget,
    );
    expect(find.text('IPHONE & IPAD'), findsWidgets);
    expect(find.text('ANDROID'), findsWidgets);
    expect(find.text('DESKTOP'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
