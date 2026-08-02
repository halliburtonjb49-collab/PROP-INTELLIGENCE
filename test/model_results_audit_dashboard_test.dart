import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/widgets/model_results_audit_dashboard.dart';

class _FakeApi extends ApiService {
  @override
  Future<Map<String, dynamic>> fetchIntelligence(String path) async => {
    'rollingAudit': {
      'windows': [
        {
          'key': '30d',
          'label': 'LAST 30 DAYS',
          'sampleSize': 100,
          'accuracy': .62,
          'monitor': 1,
          'recalibrate': 1,
          'dimensions': {
            'sport': [
              {
                'value': 'WNBA',
                'sampleSize': 100,
                'accuracy': .62,
                'averageConfidence': .67,
                'status': 'MONITOR',
                'reason': 'Confidence gap',
                'actionable': true,
              },
            ],
            'propType': [],
            'confidenceTier': [],
            'side': [],
          },
        },
      ],
    },
  };
}

void main() {
  testWidgets('model audit remains readable at phone width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 800,
            child: ModelResultsAuditDashboard(apiService: _FakeApi()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AUTOMATED MODEL-RESULTS AUDIT'), findsOneWidget);
    expect(find.text('62.0%'), findsWidgets);
    expect(find.text('WNBA'), findsOneWidget);
    expect(find.text('MONITOR'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
