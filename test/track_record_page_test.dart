import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/pages/track_record_page.dart';
import 'package:prop_intelligence/services/api_service.dart';

class _FakeTrackRecordApi extends ApiService {
  @override
  Future<Map<String, dynamic>> fetchTrackRecord() async => {
    'generatedAt': '2026-08-08T12:30:00+00:00',
    'lastGradedAt': '2026-08-08T12:00:00+00:00',
    'modelVersion': 'v10',
    'published': true,
    'sampleSize': 240,
    'winRate': .575,
    'simulatedRoi': .031,
    'losingPredictionsIncluded': true,
    'historyPolicy': 'APPEND_ONLY_GRADED_RESULTS',
    'currentStreak': {'type': 'LOSING', 'length': 2},
    'confidenceTiers': [
      {
        'tier': 'HIGH',
        'label': 'High confidence',
        'sampleSize': 120,
        'hits': 72,
        'winRate': .6,
        'published': true,
      },
    ],
    'sportBreakdown': [
      {
        'key': 'MLB',
        'label': 'MLB',
        'sampleSize': 160,
        'hits': 92,
        'winRate': .575,
        'published': true,
      },
    ],
    'marketBreakdown': [
      {
        'key': 'Batter Hits',
        'label': 'Batter Hits',
        'sampleSize': 140,
        'hits': 80,
        'winRate': .5714,
        'published': true,
      },
    ],
    'calibrationCurve': [
      {
        'label': '60-69%',
        'sampleSize': 90,
        'predicted': .64,
        'observed': .61,
        'judged': true,
      },
    ],
  };
}

void main() {
  testWidgets('verified ledger shows losses, breakdowns and calibration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackRecordPage(apiService: _FakeTrackRecordApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('append-only-ledger')), findsOneWidget);
    expect(find.textContaining('Losing predictions stay'), findsOneWidget);
    expect(find.text('L2'), findsOneWidget);
    expect(find.text('BY SPORT'), findsOneWidget);
    expect(find.text('BY MARKET'), findsOneWidget);
    expect(find.text('CALIBRATION: PREDICTED VS ACTUAL'), findsOneWidget);
  });
}
