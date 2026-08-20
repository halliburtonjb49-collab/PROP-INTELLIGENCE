import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/navigation/app_navigation.dart';
import 'package:prop_intelligence/widgets/left_sidebar.dart';

void main() {
  testWidgets('a signed-in member can end the session', (tester) async {
    // signOut() existed, but only the paywall screen offered it: a member
    // with a working subscription had to lose access to be shown the button.
    // That leaves no way off a shared device and no way to recover from
    // being signed in as the wrong account.
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: LeftSidebar(
              selectedPage: AppPage.board,
              selectedSport: 'ALL',
              lockedSlipCount: 0,
              propCountListenable: ValueNotifier<int>(0),
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('sidebar-sign-out')), findsOneWidget);
    expect(find.text('SIGN OUT'), findsOneWidget);
  });
}
