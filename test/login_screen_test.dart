import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/screens/login_screen.dart';

Future<void> _pumpLogin(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: CorporateLoginScreen()));
  await tester.pump();
}

void main() {
  for (final viewport in <String, Size>{
    'desktop': const Size(1440, 900),
    'laptop': const Size(1366, 768),
    'short laptop': const Size(1280, 720),
    'mobile': const Size(390, 844),
    'narrow phone': const Size(320, 700),
  }.entries) {
    testWidgets('login has no clipping on ${viewport.key}', (tester) async {
      await _pumpLogin(tester, viewport.value);

      expect(find.text('WELCOME BACK'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-email-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-password-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-submit-action')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop presents the professional product value proposition', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(1440, 900));

    expect(find.textContaining('THE PI PWA'), findsOneWidget);
    expect(find.textContaining('INSTALL DIRECTLY FROM THE WEB'), findsOneWidget);
    expect(find.textContaining('RECEIVE IMPROVEMENTS AUTOMATICALLY'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public signup opens paid account creation', (tester) async {
    await _pumpLogin(tester, const Size(1440, 900));
    await tester.tap(find.text('SIGN UP').first);
    await tester.pump();

    expect(find.text('CREATE YOUR LOGIN'), findsOneWidget);
    expect(find.text('Create App Password'), findsOneWidget);
    expect(find.text('Confirm App Password'), findsOneWidget);
    expect(find.textContaining('not your Gmail password'), findsOneWidget);
    expect(find.text('CONTINUE TO EMAIL VERIFICATION'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile menu exposes public information and install guidance', (
    tester,
  ) async {
    await _pumpLogin(tester, const Size(390, 844));
    await tester.tap(find.byKey(const ValueKey('mobile-info-menu')));
    await tester.pumpAndSettle();

    for (final label in <String>[
      'TERMS',
      'PRIVACY',
      'CONTACT',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.textContaining('INSTALL DIRECTLY FROM THE WEB'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard focus moves from email to password', (tester) async {
    await _pumpLogin(tester, const Size(1366, 768));
    final email = find.byKey(const ValueKey('login-email-field'));
    final password = find.byKey(const ValueKey('login-password-field'));

    await tester.tap(email);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final editable = find.descendant(
      of: password,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login controls expose screen-reader semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpLogin(tester, const Size(1366, 768));

    expect(find.bySemanticsLabel('Enter your email'), findsOneWidget);
    expect(find.bySemanticsLabel('Enter your password'), findsOneWidget);
    expect(find.bySemanticsLabel('LOGIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('login remains usable at 200 percent browser text scaling', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );
    await _pumpLogin(tester, const Size(1280, 720));

    expect(find.byKey(const ValueKey('login-submit-action')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('login-submit-action')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
