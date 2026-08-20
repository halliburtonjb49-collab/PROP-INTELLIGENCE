import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/legal/legal_content.dart';
import 'package:prop_intelligence/screens/legal_screen.dart';
import 'package:prop_intelligence/widgets/responsible_play_footer.dart';

void main() {
  testWidgets('the board carries a help line, not just a disclaimer', (
    tester,
  ) async {
    // The app previously carried no problem-gambling resource anywhere, and
    // its disclaimer lived only on a login screen seen once.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ResponsiblePlayFooter())),
    );

    expect(
      find.byKey(const ValueKey('responsible-play-footer')),
      findsOneWidget,
    );
    expect(find.textContaining('1-800-GAMBLER'), findsOneWidget);
    expect(find.textContaining('Not gambling advice'), findsOneWidget);
    expect(find.textContaining('legal age'), findsOneWidget);
  });

  testWidgets('the terms affordance is hidden when it goes nowhere', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ResponsiblePlayFooter())),
    );

    expect(find.byKey(const ValueKey('footer-open-legal')), findsNothing);
  });

  testWidgets('terms and privacy are readable inside the app', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalScreen()));
    await tester.pumpAndSettle();

    expect(find.text('TERMS'), findsOneWidget);
    expect(find.text('PRIVACY'), findsOneWidget);
    expect(find.byKey(const ValueKey('legal-terms')), findsOneWidget);
    // The sections render from the shared source rather than a second copy.
    expect(find.text(termsSections.first.title), findsOneWidget);
  });

  test('the help line is defined once for every surface', () {
    expect(legalHelpLine, '1-800-GAMBLER');
    expect(ResponsiblePlayFooter.helpLine, legalHelpLine);
  });

  test('the legal text has one source rather than two copies', () {
    // Two copies of legal wording drift, and the stale copy is the one that
    // ends up in front of somebody.
    expect(termsSections, isNotEmpty);
    expect(privacySections, isNotEmpty);
    expect(
      termsSections.any((section) => section.title.contains('RESPONSIBLE')),
      isTrue,
    );
  });
}
