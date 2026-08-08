import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';

void main() {
  test('verdict filters wrap at mobile widths', () {
    expect(shouldWrapVerdictFilters(390), isTrue);
    expect(shouldWrapVerdictFilters(599), isTrue);
  });

  test('verdict filters retain horizontal desktop layout', () {
    expect(shouldWrapVerdictFilters(600), isFalse);
    expect(shouldWrapVerdictFilters(1200), isFalse);
  });
}
