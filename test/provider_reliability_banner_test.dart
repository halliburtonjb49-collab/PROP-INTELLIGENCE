import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/provider_reliability_banner.dart';

void main() {
  const reliability = <String, dynamic>{
    'status': 'DEGRADED',
    'latestAgeMinutes': 4,
    'eventCount': 18,
    'providerCount': 5,
    'expectedProviderCount': 6,
    'horizonDays': 3,
    'recovery': {'requested': true},
    'days': [
      {
        'date': '2026-08-08',
        'propCount': 120,
        'eventCount': 8,
        'providerCount': 5,
      },
      {
        'date': '2026-08-09',
        'propCount': 80,
        'eventCount': 6,
        'providerCount': 4,
      },
      {
        'date': '2026-08-10',
        'propCount': 40,
        'eventCount': 4,
        'providerCount': 3,
      },
    ],
    'marketHealth': [
      {
        'sport': 'MLB',
        'category': 'HITS',
        'status': 'GREEN',
        'providerCount': 5,
        'expectedProviderCount': 6,
        'coveragePercent': 83,
        'propCount': 42,
      },
      {
        'sport': 'MLB',
        'category': 'TOTAL BASES',
        'status': 'RED',
        'providerCount': 2,
        'expectedProviderCount': 6,
        'coveragePercent': 33,
        'propCount': 12,
      },
      {
        'sport': 'WNBA',
        'category': 'POINTS',
        'status': 'YELLOW',
        'providerCount': 3,
        'expectedProviderCount': 6,
        'coveragePercent': 50,
        'propCount': 18,
      },
    ],
    'providers': [
      {
        'provider': 'PRIZEPICKS',
        'status': 'LIVE',
        'propCount': 40,
        'eventCount': 6,
        'ageMinutes': 4,
      },
      {
        'provider': 'UNDERDOG',
        'status': 'MISSING',
        'propCount': 0,
        'eventCount': 0,
        'ageMinutes': null,
      },
    ],
  };

  testWidgets('compact reliability banner fits a phone width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(8),
            child: ProviderReliabilityBanner(
              reliability: reliability,
              selectedSite: 'PRIZEPICKS',
              coverageIssue: {
                'category': 'HITS + RUNS + RBIS',
                'selectedCount': 4,
                'benchmarkCount': 18,
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('provider-reliability-banner')), findsOne);
    expect(find.byKey(const ValueKey('provider-coverage-warning')), findsOne);
    expect(find.textContaining('UPDATED 4M AGO'), findsOne);
    expect(find.textContaining('4 synced'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('market health map summarizes and filters categories on phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProviderReliabilitySheet(reliability: reliability),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('market-health-summary')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('market-health-summary')), findsOne);
    expect(find.byKey(const ValueKey('market-health-map')), findsOne);
    expect(find.text('LIMITED 1'), findsOne);
    expect(find.textContaining('MLB  |  TOTAL BASES'), findsOne);
    expect(find.textContaining('WNBA  |  POINTS'), findsOne);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'MLB'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'MLB'));
    await tester.pump();

    expect(find.text('TOTAL BASES'), findsOne);
    expect(find.text('HITS'), findsOne);
    expect(find.textContaining('WNBA  |  POINTS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('details sheet presents provider and three-day status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProviderReliabilitySheet(reliability: reliability),
        ),
      ),
    );

    expect(find.text('THREE-DAY SLATE CENTER'), findsOne);
    expect(find.text('TODAY + NEXT THREE DAYS'), findsOne);
    await tester.scrollUntilVisible(
      find.text('PROVIDERS'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('PROVIDERS'), findsOne);
    expect(find.text('PRIZEPICKS'), findsOne);
    expect(find.text('UNDERDOG'), findsOne);
    expect(find.text('MISSING'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recovery feed announces itself even with no telemetry', (
    tester,
  ) async {
    // The moment the catalog falls back to the durable snapshot is exactly
    // when reliability telemetry is most likely to be missing too, and the
    // banner used to render nothing at all in that case.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProviderReliabilityBanner(
            reliability: <String, dynamic>{},
            selectedSite: 'ALL',
            feedIsRecovery: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('feed-recovery-warning')), findsOneWidget);
    expect(find.textContaining('RECOVERY FEED'), findsOneWidget);
    expect(find.textContaining('CONFIRM AT THE SPORTSBOOK'), findsOneWidget);
  });

  testWidgets('a healthy feed shows no recovery warning', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProviderReliabilityBanner(
            reliability: <String, dynamic>{'status': 'HEALTHY'},
            selectedSite: 'ALL',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('feed-recovery-warning')), findsNothing);
  });
}
