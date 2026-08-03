import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/prop_data.dart';

PropData propWith({String injury = 'unknown', String grade = 'D'}) {
  return PropData.fromJson({
    'id': 'test',
    'player': 'Player',
    'sport': 'WNBA',
    'matchup': 'A @ B',
    'sportsbook': 'PrizePicks',
    'market': 'Points',
    'line': 20.5,
    'pick': 'UNDER',
    'edge': 0,
    'imagePath': '',
    'injuryStatus': injury,
    'pickGrade': grade,
  });
}

void main() {
  test('injury display uses only approved client labels', () {
    expect(propWith().injuryDisplayLabel, 'NO INJURY REPORTED');
    expect(propWith(injury: 'healthy').injuryDisplayLabel, 'NOT INJURED');
    expect(propWith(injury: 'questionable').injuryDisplayLabel, 'DAY TO DAY');
    expect(propWith(injury: 'out').injuryDisplayLabel, 'INJURED');
  });

  test('legacy and missing grades collapse to C', () {
    expect(propWith(grade: 'A').pickGrade, 'A');
    expect(propWith(grade: 'B').pickGrade, 'B');
    expect(propWith(grade: 'D').pickGrade, 'C');
    expect(propWith(grade: 'F').pickGrade, 'C');
  });
}
