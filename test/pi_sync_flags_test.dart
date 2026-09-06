import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/config/pi_sync_flags.dart';

void main() {
  test('Stage A path is off unless explicitly enabled', () {
    expect(syncManagerPathEnabled(), isFalse);
    expect(syncManagerPathEnabled(override: false), isFalse);
    expect(syncManagerPathEnabled(override: true), isTrue);
    expect(propRevisionFeedEnabled(), isFalse);
    expect(propRevisionFeedEnabled(override: false), isFalse);
    expect(propRevisionFeedEnabled(override: true), isTrue);
  });
}
