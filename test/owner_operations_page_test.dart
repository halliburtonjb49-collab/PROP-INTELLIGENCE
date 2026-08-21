import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/pages/owner_operations_page.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/widgets/owner_user_account_controls.dart';

class _FakeOperationsApi extends ApiService {
  int recoveryRequests = 0;

  @override
  Future<List<PropData>> fetchProps({
    String selectedSide = 'All',
    String selectedTier = 'All',
    String selectedSportsbook = 'All',
    String selectedSport = 'All',
    String selectedCategory = 'All',
    String search = '',
    int minConfidence = 0,
    String sortBy = 'confidence',
    String verdictFilter = 'All',
    int limit = 75,
    int offset = 0,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchBillingCertification() async => {
    'status': 'WARN',
    'releaseReady': false,
    'passCount': 6,
    'warningCount': 1,
    'failureCount': 0,
    'generatedAtUtc': '2026-08-09T20:00:00Z',
    'checks': [
      {
        'key': 'checkout_terms',
        'label': 'Stripe / RevenueCat checkout terms',
        'status': 'WARN',
        'detail': 'External checkout prices and trials require verification.',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchLaunchControlPanel() async => {
    'api': {'status': 'ok', 'version': 'abc123'},
    'redis': {'available': true},
    'workers': {'available': true, 'workers': 2, 'queued': 1, 'failed': 0},
    'providers': {'qualityScore': .94, 'errors': 0, 'remainingQuota': 1000},
    'propFreshness': {'healthy': true, 'ageMinutes': 2, 'total': 450},
    'syncCertification': {
      'status': 'PENDING',
      'automaticRetries': true,
      'generatedAtUtc': '2026-08-10T02:30:00Z',
      'checks': [
        {
          'key': 'coverage',
          'label': 'Broad sport coverage',
          'status': 'PENDING',
          'detail': '4 of 13 configured sports fetched.',
        },
      ],
    },
    'dataCertification': {
      'status': 'WARN',
      'score': 92,
      'passCount': 5,
      'warningCount': 1,
      'failureCount': 0,
      'generatedAtUtc': '2026-08-09T20:00:00Z',
      'checks': [
        {
          'key': 'catalog',
          'label': 'Live catalog',
          'status': 'PASS',
          'value': 450,
          'detail': '450 current prop rows are available.',
        },
        {
          'key': 'slate',
          'label': 'Four-date slate',
          'status': 'WARN',
          'value': '3/4',
          'detail': 'Props are available on 3 of 4 monitored dates.',
        },
      ],
    },
    'billingCertification': {
      'status': 'WARN',
      'releaseReady': false,
      'passCount': 6,
      'warningCount': 1,
      'failureCount': 0,
      'generatedAtUtc': '2026-08-09T20:00:00Z',
      'checks': [
        {
          'key': 'checkout_terms',
          'label': 'Stripe / RevenueCat checkout terms',
          'status': 'WARN',
          'detail': 'External checkout prices and trials require verification.',
        },
      ],
    },
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
  Future<Map<String, dynamic>> fetchOwnerCommandCenter({
    String window = 'today',
    DateTime? start,
    DateTime? end,
  }) async => {
    'generatedAt': '2026-08-11T14:01:00Z',
    'window': {'key': window, 'label': 'Today'},
    'overview': [
      {
        'key': 'activeUsers',
        'label': 'Active users',
        'value': 3,
        'detail': 'Last 15 minutes',
        'status': 'healthy',
      },
      {
        'key': 'propsAvailable',
        'label': 'Props available',
        'value': 450,
        'detail': 'Current cache inventory',
        'status': 'healthy',
      },
    ],
    'services': [
      {
        'service': 'API',
        'status': 'HEALTHY',
        'lastUpdate': '2026-08-11T14:01:00Z',
        'latencyMs': 120,
        'records': 'online',
      },
    ],
    'alerts': <Map<String, dynamic>>[],
    'inventory': {
      'total': 1,
      'returned': 1,
      'truncated': false,
      'healthy': 0,
      'flagged': 1,
      'facets': {
        'sports': ['WNBA'],
        'providers': ['PrizePicks'],
        'markets': ['Points'],
        'statuses': ['scheduled'],
        'quality': ['stale_line'],
      },
      'alerts': [
        {'key': 'stale_line', 'count': 1, 'severity': 'GOLD'},
      ],
      'providers': [
        {
          'provider': 'PrizePicks',
          'status': 'PARTIAL',
          'props': 1,
          'sports': ['WNBA'],
          'stale': 1,
          'suspicious': 0,
          'missingProjection': 0,
          'lastUpdate': '2026-08-11T12:00:00Z',
        },
      ],
      'items': [
        {
          'id': 'game-1|Test Player|Points|PrizePicks',
          'gameId': 'game-1',
          'sport': 'WNBA',
          'matchup': 'Away vs Home',
          'player': 'Test Player',
          'market': 'Points',
          'provider': 'PrizePicks',
          'line': 20.5,
          'openingLine': 19.5,
          'lineMovement': 1.0,
          'prediction': 'OVER',
          'confidence': .72,
          'gameStatus': 'scheduled',
          'lastUpdate': '2026-08-11T12:00:00Z',
          'warnings': ['stale_line'],
          'qualityStatus': 'WARNING',
        },
      ],
    },
  };
  @override
  Future<Map<String, dynamic>> fetchOwnerModelAudit({
    String window = '30d',
    DateTime? start,
    DateTime? end,
    int limit = 500,
  }) async => {
    'available': true,
    'generatedAt': '2026-08-11T14:01:00Z',
    'window': {'key': window, 'label': 'Today'},
    'truncated': false,
    'returned': 1,
    'summary': {
      'graded': 1,
      'decisions': 1,
      'hits': 1,
      'losses': 0,
      'pushes': 0,
      'accuracy': 1.0,
      'brierScore': .0784,
      'simulatedRoi': .91,
      'oddsSampleSize': 1,
    },
    'calibration': [
      {
        'tier': '70-79%',
        'sampleSize': 1,
        'hits': 1,
        'accuracy': 1.0,
        'averageConfidence': .72,
        'calibrationGap': -.28,
      },
    ],
    'sidePerformance': [
      {
        'side': 'OVER',
        'sampleSize': 1,
        'hits': 1,
        'pushes': 0,
        'accuracy': 1.0,
      },
    ],
    'dimensions': {
      'sports': ['WNBA'],
      'markets': ['Points'],
      'sides': ['OVER'],
      'modelVersions': ['wnba-v2'],
    },
    'predictions': [
      {
        'id': 'prediction-1',
        'propId': 'prop-1',
        'player': 'Audit Player',
        'sport': 'WNBA',
        'market': 'Points',
        'side': 'OVER',
        'line': 20.5,
        'projection': 23.1,
        'actualValue': 24,
        'hitProbability': .72,
        'hit': true,
        'modelVersion': 'wnba-v2',
        'createdAt': '2026-08-11T12:00:00Z',
        'eventTime': '2026-08-11T13:00:00Z',
        'gradedAt': '2026-08-11T14:00:00Z',
        'provider': 'PrizePicks',
        'entryOdds': -110,
        'closingLine': 21.5,
        'lineClvPoints': 1.0,
        'explanation': {
          'summary': 'Projection cleared the line with a confirmed role.',
          'modelVersion': 'wnba-v2',
          'sourceVersions': {'projection': 'wnba-v2'},
          'warnings': ['Closing line source was delayed.'],
          'sections': [
            {
              'key': 'projection',
              'label': 'Projection vs line',
              'value': '23.10 vs 20.50',
              'detail': 'Model difference +2.60.',
              'status': 'AVAILABLE',
            },
            {
              'key': 'availability',
              'label': 'Injury and lineup',
              'value': 'Injury: healthy | Lineup: confirmed starter',
              'detail': 'Starter confirmed before tip.',
              'status': 'AVAILABLE',
            },
          ],
        },
        'confidenceTier': '70-79%',
        'push': false,
        'correct': true,
        'profitUnits': .9091,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> fetchProviderAvailability() async => {
    'overallStatus': 'ATTENTION',
    'generatedAt': '2026-08-11T14:00:00Z',
    'checkedAt': '2026-08-11T14:01:00Z',
    'refreshIntervalMinutes': 10,
    'sports': [
      {
        'sport': 'WNBA',
        'provider': 'Sportradar WNBA',
        'status': 'PARTIAL',
        'authorizationStatus': 'AUTHORIZED',
        'stale': true,
        'gamesChecked': 2,
        'playersConfirmed': 20,
        'startersConfirmed': 10,
        'observationsCreated': 18,
        'lastSuccessfulSync': '2026-08-11T14:00:00Z',
        'nextRefreshAt': '2026-08-11T14:10:00Z',
        'missingData': ['Latest availability data is stale.'],
      },
      {
        'sport': 'NFL',
        'provider': 'Sportradar NFL',
        'status': 'NOT_ENTITLED',
        'authorizationStatus': 'NOT_ENTITLED',
        'gamesChecked': 0,
        'playersConfirmed': 0,
        'startersConfirmed': 0,
        'observationsCreated': 0,
        'lastSuccessfulSync': null,
        'nextRefreshAt': '2026-08-11T14:10:00Z',
        'missingData': ['Provider plan does not include this sport.'],
      },
    ],
    'alerts': [
      {
        'sport': 'NFL',
        'status': 'NOT_ENTITLED',
        'message': 'Provider plan does not include this sport.',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> fetchProviderRecovery() async => {
    'state': 'RECOMMENDED',
    'message': 'One safe global recovery can refresh WNBA.',
    'recoveryRecommended': true,
    'canStartRecovery': true,
    'actionableSports': ['WNBA'],
    'sports': [
      {
        'sport': 'WNBA',
        'status': 'PARTIAL',
        'authorizationStatus': 'AUTHORIZED',
        'stale': true,
        'needsRecovery': true,
        'canRecover': true,
        'reason': 'Latest availability data is stale.',
      },
      {
        'sport': 'NFL',
        'status': 'NOT_ENTITLED',
        'authorizationStatus': 'NOT_ENTITLED',
        'stale': false,
        'needsRecovery': false,
        'canRecover': false,
        'reason': 'Provider plan does not include this sport.',
      },
    ],
    'queue': {
      'available': true,
      'workers': 1,
      'queued': 0,
      'started': 0,
      'retryPolicy': {'maxAttempts': 4},
    },
    'sync': {
      'status': 'idle',
      'coverageStatus': 'idle',
      'sportsGameOddsStatus': 'idle',
      'postProcessingStatus': 'idle',
    },
  };

  @override
  Future<Map<String, dynamic>> requestProviderRecovery({
    String targetSport = 'ALL',
  }) async {
    recoveryRequests += 1;
    return {
      ...(await fetchProviderRecovery()),
      'state': 'QUEUED',
      'canStartRecovery': false,
      'message': 'Provider recovery is queued on the background worker.',
      'request': {
        'accepted': true,
        'status': 'QUEUED',
        'reason': 'Provider recovery queued with automatic retries.',
      },
    };
  }

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

class _PartialFailureOperationsApi extends _FakeOperationsApi {
  @override
  Future<Map<String, dynamic>> fetchProviderRecovery() async {
    throw Exception('temporary provider recovery failure');
  }
}

class _PrimaryFailureOperationsApi extends _FakeOperationsApi {
  @override
  Future<Map<String, dynamic>> fetchLaunchControlPanel() async {
    throw Exception('launch control timed out');
  }
}

void main() {
  test('owner operations access is role-specific', () {
    expect(canAccessOwnerOperations('owner'), isTrue);
    expect(canAccessOwnerOperations('admin'), isFalse);
    expect(canAccessOwnerOperations('tester'), isFalse);
    expect(canAccessOwnerOperations('user'), isFalse);
  });

  testWidgets('certifications survive a secondary panel failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerOperationsPage(apiService: _PartialFailureOperationsApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('production-data-certification')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('WARN | SCORE 92/100'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('billing-release-certification')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('billing-release-certification')),
      findsOneWidget,
    );
  });

  testWidgets('billing certification survives a control panel failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerOperationsPage(apiService: _PrimaryFailureOperationsApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('billing-release-certification')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('billing-release-certification')),
      findsOneWidget,
    );
    expect(find.textContaining('6 passed'), findsOneWidget);
  });

  testWidgets('owner operations page shows controls and review queue', (
    tester,
  ) async {
    final api = _FakeOperationsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OwnerOperationsPage(apiService: api)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OWNER COMMAND CENTER'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('owner-command-center-overview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-user-account-controls')),
      findsOneWidget,
    );
    expect(find.text('MANAGE USER ACCOUNTS'), findsOneWidget);
    expect(find.byKey(const ValueKey('owner-window-today')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('owner-operations-refresh')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('owner-prop-inventory')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('owner-prop-inventory')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('owner-inventory-search')),
      findsOneWidget,
    );
    expect(find.text('PROVIDER DRILLDOWNS'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('owner-inventory-search')),
      'missing player',
    );
    await tester.pump();
    expect(find.text('No props match these owner filters.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('owner-inventory-search')),
      '',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('PROVIDER AVAILABILITY'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('provider-availability-dashboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-provider-recovery')),
      findsOneWidget,
    );
    final recoveryButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('provider-recover-all')),
    );
    recoveryButton.onPressed!();
    await tester.pumpAndSettle();
    expect(api.recoveryRequests, 1);
    expect(
      find.text('Provider recovery queued with automatic retries.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('PRODUCTION DATA CERTIFICATION'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('sync-certification')), findsOneWidget);
    expect(find.text('PENDING | SYNC CERTIFICATION'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('production-data-certification')),
      findsOneWidget,
    );
    expect(find.text('WARN | SCORE 92/100'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('billing-release-certification')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('billing-release-certification')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('product-observability-section')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('product-observability-section')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('owner-model-audit')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('owner-model-audit')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('owner-model-audit-search')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('owner-model-audit-search')),
      'missing prediction',
    );
    await tester.pump();
    expect(
      find.text('No verified predictions match these audit filters.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('owner-model-audit-search')),
      '',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('OVER / UNDER AUDIT'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OVER / UNDER AUDIT'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('owner-prediction-prediction-1')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('owner-prediction-prediction-1')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('owner-why-pi-prediction-1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('owner-why-pi-prediction-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('owner-why-pi-dialog')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('owner-why-pi-dialog')),
        matching: find.text('WHY DID PI CHOOSE THIS?'),
      ),
      findsOneWidget,
    );
    expect(find.text('23.10 vs 20.50'), findsOneWidget);
    expect(find.text('DATA WARNINGS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('owner-why-pi-close')));
    await tester.pumpAndSettle();
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

    final api = _FakeOperationsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OwnerOperationsPage(apiService: api)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OWNER COMMAND CENTER'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('owner-command-center-overview')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('owner-window-today')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('owner-operations-refresh')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('PROVIDER AVAILABILITY'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey('provider-availability-dashboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-provider-recovery')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner can open account-role controls on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: const [OwnerUserAccountControls()]),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('owner-manage-user-roles')));
    await tester.pumpAndSettle();

    expect(find.text('O  MANAGE USER ROLE'), findsOneWidget);
    expect(find.byKey(const ValueKey('owner-role-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('owner-role-select')), findsOneWidget);
    expect(find.byKey(const ValueKey('owner-assign-role')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
