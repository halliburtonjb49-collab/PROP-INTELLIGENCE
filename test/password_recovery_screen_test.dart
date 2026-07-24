import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/screens/password_recovery_screen.dart';

void main() {
  testWidgets('password recovery validates short passwords on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: PasswordRecoveryScreen()));
    await tester.enterText(find.byType(TextField).first, 'short');
    await tester.enterText(find.byType(TextField).last, 'short');
    await tester.tap(find.text('SAVE PASSWORD'));
    await tester.pump();

    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('password recovery validates confirmation before submission', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PasswordRecoveryScreen()));
    await tester.enterText(find.byType(TextField).first, 'secure-password');
    await tester.enterText(find.byType(TextField).last, 'different-password');
    await tester.tap(find.text('SAVE PASSWORD'));
    await tester.pump();

    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
