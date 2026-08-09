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

    expect(find.text('DATA RELIABILITY'), findsOne);
    expect(find.text('NEXT THREE DAYS'), findsOne);
    expect(find.text('PROVIDERS'), findsOne);
    expect(find.text('PRIZEPICKS'), findsOne);
    expect(find.text('UNDERDOG'), findsOne);
    expect(find.text('MISSING'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
