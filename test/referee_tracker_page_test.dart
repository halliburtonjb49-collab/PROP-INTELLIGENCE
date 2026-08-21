import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/pages/referee_tracker_page.dart';

void main() {
  final payload = <String, dynamic>{
    'sport': 'WNBA',
    'officials': [
      {
        'officialId': 'official-1',
        'officialName': 'Jordan Example',
        'sampleSize': 42,
        'rawRate': 48.5,
        'leagueRate': 45.0,
        'tendencyIndex': 1.04,
        'confidence': .68,
        'recentAssignments': [
          {
            'gameDate': '2026-07-24',
            'totalFouls': 39,
            'totalFreeThrowAttempts': 31,
          },
        ],
      },
    ],
    'disclaimer': 'Historical tendencies are informational.',
  };

  testWidgets('renders referee tendency context on desktop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: RefereeTrackerPage(loader: (_) async => payload)),
    );
    await tester.pumpAndSettle();

    expect(find.text('OFFICIATING TRACKER'), findsOneWidget);
    expect(find.text('Jordan Example'), findsOneWidget);
    expect(find.text('+4.0%'), findsOneWidget);
    expect(find.text('42'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remains usable at mobile width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: RefereeTrackerPage(loader: (_) async => payload)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jordan Example'), findsOneWidget);
    expect(find.text('RECENT ASSIGNMENTS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers MLB umpire tracking without an empty NFL control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RefereeTrackerPage(loader: (_) async => payload)),
    );
    await tester.pumpAndSettle();

    expect(find.text('MLB'), findsOneWidget);
    expect(find.text('NFL'), findsNothing);
  });
}
