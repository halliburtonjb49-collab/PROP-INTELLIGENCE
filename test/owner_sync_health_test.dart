import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/owner_command_center_overview.dart';

void main() {
  testWidgets('owner command center renders collected sync stages on phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OwnerCommandCenterOverview(
              data: {
                'overview': [
                  {
                    'key': 'propsAvailable',
                    'label': 'Props available',
                    'value': 42,
                    'detail': 'Current inventory',
                    'status': 'healthy',
                  },
                ],
                'services': const [],
                'syncHealth': {
                  'publication': {
                    'durationMs': 18,
                    'publishedAt': '2026-09-06T12:00:00Z',
                    'rowCount': 42,
                  },
                  'queue': {'queued': 0, 'workers': 2},
                  'apiDelivery': {
                    'scope': 'this-api-instance',
                    'sampleCount': 5,
                    'cacheHitRatio': .8,
                    'latencyMs': {'p95': 120},
                    'responseBytes': {'p95': 4096},
                  },
                  'publicationToClientApplied': {
                    'sampleCount': 3,
                    'lastMs': 640,
                  },
                  'providerQuota': {'remaining': 900, 'used': 100},
                  'sourceFreshness': [
                    {
                      'sport': 'MLB',
                      'status': 'HEALTHY',
                      'lastCheckAt': '2026-09-06T12:00:00Z',
                    },
                  ],
                },
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('owner-sync-health')), findsOneWidget);
    expect(find.text('PROP SYNC HEALTH'), findsOneWidget);
    expect(find.text('API LATENCY P95'), findsOneWidget);
    expect(find.text('PUBLISH → CLIENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
