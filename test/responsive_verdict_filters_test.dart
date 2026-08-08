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

  test('verdict filters preserve an unloaded count state', () {
    expect(resolveVerdictFilterCount(const {}, 'PLAY_NOW'), isNull);
  });

  test('loaded verdict filters expose missing categories as zero', () {
    const counts = {'ALL': 12, 'PLAY_NOW': 3};
    expect(resolveVerdictFilterCount(counts, 'PLAY_NOW'), 3);
    expect(resolveVerdictFilterCount(counts, 'SHOP'), 0);
    expect(resolveVerdictFilterCount(counts, 'WAIT'), 0);
  });
}
