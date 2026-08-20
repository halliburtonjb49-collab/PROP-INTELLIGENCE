import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/legal/legal_content.dart';
import 'package:prop_intelligence/screens/legal_screen.dart';

void main() {
  testWidgets('terms and privacy are readable inside the app', (tester) async {
    // They were reachable only through a login-screen dialog a signed-in
    // member cannot get back to. Terms a user cannot re-read are terms they
    // cannot check.
    await tester.pumpWidget(const MaterialApp(home: LegalScreen()));
    await tester.pumpAndSettle();

    expect(find.text('TERMS'), findsOneWidget);
    expect(find.text('PRIVACY'), findsOneWidget);
    expect(find.byKey(const ValueKey('legal-terms')), findsOneWidget);
    expect(find.text(termsSections.first.title), findsOneWidget);
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
