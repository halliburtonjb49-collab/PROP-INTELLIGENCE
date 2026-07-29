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
    'providers': {
      'qualityScore': .94,
      'errors': 0,
      'remainingQuota': 1000,
    },
    'propFreshness': {'healthy': true, 'ageMinutes': 2, 'total': 450},
    'scoreboardLatency': {'status': 'ok', 'lastMs': 240, 'p95Ms': 300},
    'activeUsers': {'count': 3, 'instrumented': true},
    'failedPayments': {'count': 0},
    'unsettledSlips': {'count': 1},
    'gradingReview': {'questionableCount': 1},
    'pipelines': {'activeFailures': <Map<String, dynamic>>[]},
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
    expect(find.byKey(const ValueKey('owner-operations-refresh')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Test Player'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Test Player'), findsOneWidget);
  });
}
