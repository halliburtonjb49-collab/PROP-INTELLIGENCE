import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';
import 'package:prop_intelligence/pages/owner_operations_page.dart';
import 'package:prop_intelligence/services/api_service.dart';

class _FakeOperationsApi extends ApiService {
  @override
  Future<Map<String, dynamic>> fetchLaunchControlPanel() async => {
    'api': {'status': 'ok', 'version': 'abc123'},
    'redis': {'available': true},
    'workers': {'available': true, 'workers': 2, 'queued': 1, 'failed': 0},
    'providers': {'qualityScore': .94, 'errors': 0, 'remainingQuota': 1000},
    'propFreshness': {'healthy': true, 'ageMinutes': 2, 'total': 450},
    'scoreboardLatency': {'status': 'ok', 'lastMs': 240, 'p95Ms': 300},
    'activeUsers': {'count': 3, 'instrumented': true},
    'failedPayments': {'count': 0},
    'unsettledSlips': {'count': 1},
    'gradingReview': {'questionableCount': 1},
    'pipelines': {'activeFailures': <Map<String, dynamic>>[]},
    'modelPerformance': {
      'sampleSize': 120,
      'accuracy': .61,
      'brierScore': .22,
      'calibrated': true,
      'minimumCalibrationSample': 100,
      'clv': {'sampleSize': 80, 'beatClosingLineRate': .56},
      'qualitySegments': [
        {
          'sampleSize': 40,
          'accuracy': .625,
          'averageConfidence': .61,
          'calibrationGap': -.015,
          'sport': 'WNBA',
          'category': 'POINTS',
          'provider': 'test-provider',
        },
      ],
      'auditSummary': {
        'healthy': 1,
        'monitor': 0,
        'recalibrate': 1,
        'collecting': 0,
      },
      'sideSegments': [
        {
          'sampleSize': 45,
          'accuracy': .62,
          'averageConfidence': .64,
          'calibrationGap': .02,
          'sport': 'WNBA',
          'side': 'OVER',
          'confidenceTier': 'MEDIUM',
          'status': 'HEALTHY',
          'reason': 'Observed results are within the guarded calibration range',
        },
      ],
    },
    'predictionOperations': {
      'databaseConfigured': true,
      'snapshotsToday': 18,
      'pendingPredictions': 5,
    },
    'ownerOnlyInsights': {
      'productObservability': {
        'available': true,
        'reliability': {
          'errorFreeUserRate': .99,
          'errorUsers': 1,
          'slowLoadUsers': 2,
          'checkoutFailures': 0,
        },
        'funnels': {
          'research': [
            {
              'label': 'App opened',
              'uniqueUsers': 100,
              'conversionFromPrevious': null,
            },
            {
              'label': 'Dashboard ready',
              'uniqueUsers': 90,
              'conversionFromPrevious': .9,
            },
          ],
          'subscription': [
            {
              'label': 'Paywall viewed',
              'uniqueUsers': 20,
              'conversionFromPrevious': null,
            },
            {
              'label': 'Checkout started',
              'uniqueUsers': 8,
              'conversionFromPrevious': .4,
            },
          ],
        },
        'errors': {'StateError': 1},
      },
    },
  };

  @override
  Future<Map<String, dynamic>> fetchOwnerGradingReview() async => {
    'items': [
      {
        'slipId': 'slip-1',
        'player': 'Test Player',
        'market': 'Points',
        'side': 'OVER',
        'line': 20.5,
        'sport': 'NBA',
        'reasons': ['grade_not_authoritatively_verified'],
      },
    ],
  };
}

void main() {
  test('owner operations access is role-specific', () {
    expect(canAccessOwnerOperations('owner'), isTrue);
    expect(canAccessOwnerOperations('admin'), isFalse);
    expect(canAccessOwnerOperations('tester'), isFalse);
    expect(canAccessOwnerOperations('user'), isFalse);
  });

  testWidgets('owner operations page shows controls and review queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerOperationsPage(apiService: _FakeOperationsApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OWNER OPERATIONS CENTER'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('owner-operations-refresh')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('PRODUCT OBSERVABILITY'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PRODUCT OBSERVABILITY'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('product-observability-section')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('MODEL ACCOUNTABILITY'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MODEL ACCOUNTABILITY'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('OVER / UNDER AUDIT'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OVER / UNDER AUDIT'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Test Player'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Test Player'), findsOneWidget);
  });

  testWidgets('owner operations page fits a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerOperationsPage(apiService: _FakeOperationsApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OWNER OPERATIONS CENTER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
