import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/slip_doctor_service.dart';

Map<String, dynamic> leg({
  required String id,
  required String player,
  String event = 'event-1',
  String market = 'points',
  String side = 'OVER',
  int trust = 82,
  double line = 20,
  double original = 20,
}) => {
  'prop_id': id,
  'player': player,
  'event_id': event,
  'matchup': event,
  'market': market,
  'side': side,
  'pi_trust_score': trust,
  'line': line,
  'current_line': line,
  'original_line': original,
};

void main() {
  test('flags same-player correlation and contradiction', () {
    final report = SlipDoctorService.analyze([
      leg(id: 'a', player: 'Player A', side: 'OVER'),
      leg(id: 'b', player: 'Player A', side: 'UNDER'),
    ]);
    final codes = report.findings.map((finding) => finding.code).toSet();
    expect(codes, containsAll(['same_player', 'contradiction', 'correlation']));
    expect(report.riskLevel, 'HIGH');
  });

  test('flags weak data and adverse line movement', () {
    final report = SlipDoctorService.analyze([
      leg(
        id: 'a',
        player: 'A',
        event: 'one',
        trust: 40,
        line: 22,
        original: 20,
      ),
      leg(id: 'b', player: 'B', event: 'two', trust: 90),
    ]);
    final codes = report.findings.map((finding) => finding.code).toSet();
    expect(codes, contains('weak_data'));
    expect(codes, contains('moved_line'));
    expect(report.weakestPropId, 'a');
  });

  test('healthy diversified high-trust slip is low risk', () {
    final report = SlipDoctorService.analyze([
      leg(id: 'a', player: 'A', event: 'one', trust: 90),
      leg(id: 'b', player: 'B', event: 'two', trust: 84),
    ]);
    expect(report.findings, isEmpty);
    expect(report.riskLevel, 'LOW');
    expect(report.healthy, isTrue);
  });
}
