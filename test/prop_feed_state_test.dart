import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/api_service.dart';

void main() {
  test('a durable snapshot is reported as a recovery feed', () {
    final state = propFeedStateFromPayload(const {
      'feed': {'source': 'durable-snapshot', 'recovery': true},
    });

    expect(state.source, 'durable-snapshot');
    expect(state.isRecovery, isTrue);
  });

  test('an ordinary shared cache read is not a recovery', () {
    // Multi-instance operation is normal. Warning on it would train users
    // to dismiss the banner that matters.
    final state = propFeedStateFromPayload(const {
      'feed': {'source': 'shared-cache', 'recovery': false},
    });

    expect(state.source, 'shared-cache');
    expect(state.isRecovery, isFalse);
  });

  test('a payload without the field never reads as a recovery', () {
    // During a rollout the app can talk to a backend that predates the
    // field. Unknown must not render a stale-data warning over fresh lines.
    final state = propFeedStateFromPayload(const {'props': []});

    expect(state.source, isEmpty);
    expect(state.isRecovery, isFalse);
  });

  test('a malformed feed value is tolerated', () {
    final state = propFeedStateFromPayload(const {'feed': 'unavailable'});

    expect(state.isRecovery, isFalse);
  });
}
