import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/widgets/analytics_admin_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdminApi extends ApiService {
  @override
  Future<Map<String, dynamic>> fetchLaunchControlPanel() async => {
    'api': {'status': 'ok', 'version': 'test'},
    'redis': {'available': true},
    'workers': {'available': true, 'workers': 2, 'queued': 0},
    'providers': {'errors': 0, 'remainingQuota': 100},
    'propFreshness': {'healthy': true, 'total': 12, 'ageMinutes': 2},
    'scoreboardLatency': {'status': 'ok', 'lastMs': 100, 'p95Ms': 150},
    'pipelines': {'activeFailures': <Map<String, dynamic>>[]},
  };

  @override
  Future<Map<String, dynamic>> fetchProductionAcceptance() async => {
    'status': 'healthy',
    'issues': <Map<String, dynamic>>[],
    'propFeed': {'total': 12, 'ageMinutes': 2},
    'providerQuota': {'remaining': 100},
    'billing': {
      'webhookConfigured': true,
      'coreProductsConfigured': true,
      'edgeProductsConfigured': true,
    },
  };

  @override
  Future<Map<String, dynamic>> fetchAdminOperations() async => {
    'pipelineRuns': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> fetchIdentityUnresolvedGrouped({
    String sourceProvider = 'odds-api',
    int limit = 5000,
  }) async => {'count': 0, 'sports': <String, dynamic>{}};
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('data admin renders operational and upload controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DataAdminPage(apiService: _FakeAdminApi())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DATA ADMIN'), findsOneWidget);
    expect(find.text('LAUNCH-DAY CONTROL PANEL'), findsOneWidget);
    expect(find.text('PRODUCTION ACCEPTANCE'), findsOneWidget);
    expect(find.text('Identity Bulk Payload'), findsOneWidget);
    expect(find.text('Availability Bulk Payload'), findsOneWidget);
    expect(find.textContaining('Unresolved players: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
