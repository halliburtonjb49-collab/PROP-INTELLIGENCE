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

  test('board controls stay focused on phones and tablets', () {
    expect(useCompactBoardControls(390), isTrue);
    expect(useCompactBoardControls(768), isTrue);
    expect(useCompactBoardControls(899.9), isTrue);
  });

  test('board controls expose provider shortcuts on wide layouts', () {
    expect(useCompactBoardControls(900), isFalse);
    expect(useCompactBoardControls(1440), isFalse);
  });

  test('compact primary controls fit without horizontal overflow', () {
    expect(compactBoardControlWidth(320), closeTo(102.67, .01));
    expect(compactBoardControlWidth(390), 126);
    expect(compactBoardControlWidth(768), 160);
    expect(compactBoardControlWidth(899), 160);
  });

  test('board framing becomes denser on phones and tablets', () {
    expect(boardContentPadding(390).horizontal, 16);
    expect(boardContentPadding(768).horizontal, 20);
    expect(boardContentPadding(1200).horizontal, 28);
  });

  test('board framing and scrollbars adapt to touch layouts', () {
    expect(boardSectionGap(390), 6);
    expect(boardSectionGap(768), 8);
    expect(boardSectionGap(1200), 10);
    expect(usePersistentBoardScrollbar(390), isFalse);
    expect(usePersistentBoardScrollbar(768), isFalse);
    expect(usePersistentBoardScrollbar(1200), isTrue);
    expect(boardScrollbarThickness(390), 4);
    expect(boardScrollbarThickness(768), 5);
    expect(boardScrollbarThickness(1200), 9);
    expect(boardFilterRailHeight(390), 44);
    expect(boardFilterRailHeight(768), 49);
    expect(boardRailArrowWidth(390), 38);
    expect(boardRailArrowWidth(768), 42);
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
