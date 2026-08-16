import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/saved_slip.dart';

void main() {
  test('saved slip leg retains its entry-time model evidence', () {
    final leg = SavedSlipLeg.fromJson({
      'prop_id': 'prop-1',
      'player': 'Test Player',
      'sport': 'WNBA',
      'matchup': 'A @ B',
      'sportsbook': 'DraftKings',
      'market': 'points',
      'line': 16.5,
      'side': 'UNDER',
      'projection': 14.99,
      'confidence': 61,
      'pi_trust_score': 84,
      'pi_trust_band': 'STRONG',
      'projection_source': 'market ensemble',
      'projection_model_version': '2026.8',
      'projection_calibrated': true,
    });

    expect(leg.projection, 14.99);
    expect(leg.confidence, 61);
    expect(leg.piTrustScore, 84);
    expect(leg.piTrustBand, 'STRONG');
    expect(leg.projectionSource, 'market ensemble');
    expect(leg.projectionModelVersion, '2026.8');
    expect(leg.projectionCalibrated, isTrue);
  });
}
