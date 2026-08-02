import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/saved_slip.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:prop_intelligence/services/evaluation_cohort.dart';
import 'package:prop_intelligence/widgets/evaluation_cohort_dashboard.dart';

SavedSlipLeg _leg({
  required String id,
  required String result,
  double? actual,
  bool? beatClose,
}) => SavedSlipLeg(
  propId: id,
  eventId: 'same-event',
  player: id,
  sport: 'WNBA',
  matchup: 'A @ B',
  sportsbook: 'DraftKings',
  market: 'points',
  line: 20.5,
  entryLine: 20.5,
  side: 'OVER',
  projection: 22,
  confidence: 60,
  projectionSource: 'verified model',
  resultValue: actual,
  resultStatus: result,
  beatClosingLine: beatClose,
);

SavedSlip _slip(List<SavedSlipLeg> legs) => SavedSlip(
  id: 'ticket-1',
  status: 'active',
  stake: 10,
  potentialPayout: 50,
  createdAt: DateTime.utc(2026, 8, 2),
  legs: legs,
);

class _FakeApi extends ApiService {
  _FakeApi(this.slips);
  final List<SavedSlip> slips;
  @override
  Future<List<SavedSlip>> fetchSlips({String? status}) async => slips;
}

void main() {
  test('cohort metrics use leg decisions and flag same-event correlation', () {
    final cohort = EvaluationCohort.fromSlips([
      _slip([
        _leg(id: 'winner', result: 'won', actual: 23, beatClose: true),
        _leg(id: 'loser', result: 'lost', actual: 19, beatClose: false),
        _leg(id: 'pending', result: 'pending'),
      ]),
    ]);

    expect(cohort.legs, 3);
    expect(cohort.pending, 1);
    expect(cohort.accuracy, 50);
    expect(cohort.meanAbsoluteError, 2);
    expect(cohort.averageConfidence, 60);
    expect(cohort.beatCloseRate, 50);
    expect(cohort.correlatedTickets, 1);
  });

  testWidgets('dashboard remains readable at phone width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 800,
            child: EvaluationCohortDashboard(
              apiService: _FakeApi([
                _slip([_leg(id: 'pending', result: 'pending')]),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EVALUATION COHORT'), findsOneWidget);
    expect(find.text('COHORT LEGS'), findsOneWidget);
    expect(find.textContaining('MODEL 22.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
