import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/provider_availability_dashboard.dart';

const availability = <String, dynamic>{
  'overallStatus': 'ATTENTION',
  'checkedAt': '2026-08-11T18:00:00Z',
  'refreshIntervalMinutes': 10,
  'sports': [
    {
      'sport': 'WNBA',
      'provider': 'Sportradar WNBA',
      'status': 'PARTIAL',
      'authorizationStatus': 'AUTHORIZED',
      'stale': true,
      'gamesChecked': 2,
      'playersConfirmed': 0,
      'startersConfirmed': 0,
      'observationsCreated': 0,
      'missingData': ['Latest availability data is stale.'],
    },
    {
      'sport': 'NFL',
      'provider': 'Sportradar NFL',
      'status': 'NOT_ENTITLED',
      'authorizationStatus': 'NOT_ENTITLED',
      'stale': false,
      'gamesChecked': 0,
      'playersConfirmed': 0,
      'startersConfirmed': 0,
      'observationsCreated': 0,
      'missingData': ['Provider plan does not include this sport.'],
    },
  ],
  'alerts': [
    {
      'sport': 'WNBA',
      'status': 'PARTIAL',
      'message': 'Latest availability data is stale.',
    },
  ],
};

const recovery = <String, dynamic>{
  'state': 'RECOMMENDED',
  'message': 'One safe global recovery can refresh WNBA.',
  'recoveryRecommended': true,
  'canStartRecovery': true,
  'sports': [
    {'sport': 'WNBA', 'canRecover': true},
    {'sport': 'NFL', 'canRecover': false},
  ],
  'queue': {
    'available': true,
    'workers': 1,
    'queued': 0,
    'retryPolicy': {'maxAttempts': 4},
  },
  'sync': {
    'status': 'idle',
    'coverageStatus': 'idle',
    'postProcessingStatus': 'idle',
  },
};

void main() {
  testWidgets(
    'recovery controls fit phone width and block non-entitled sports',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requested = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ProviderAvailabilityDashboard(
                data: availability,
                recovery: recovery,
                onRecover: (sport) async => requested.add(sport),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('owner-provider-recovery')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('provider-recover-all')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('provider-recover-WNBA')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('provider-recover-NFL')), findsNothing);
      expect(tester.takeException(), isNull);

      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('provider-recover-WNBA')),
      );
      button.onPressed!();
      await tester.pump();
      expect(requested, ['WNBA']);
    },
  );
}
