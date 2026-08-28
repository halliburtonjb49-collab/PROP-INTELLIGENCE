import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/board_filter_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const memory = BoardFilterMemory();

  test('filters survive leaving and returning to the board', () async {
    await memory.save(
      const BoardFilters(
        site: 'PRIZEPICKS',
        category: 'POINTS',
        sortBy: 'edge',
        verdict: 'PLAY_NOW',
        minConfidence: 65,
      ),
    );

    final restored = await memory.load(hasProAccess: true);

    expect(restored.site, 'PRIZEPICKS');
    expect(restored.category, 'POINTS');
    expect(restored.sortBy, 'edge');
    expect(restored.verdict, 'PLAY_NOW');
    expect(restored.minConfidence, 65);
  });

  test('nothing stored opens on all props, ranked by trust', () async {
    final restored = await memory.load(hasProAccess: true);

    expect(restored.sortBy, 'trust');
    expect(restored.verdict, 'ALL');
  });

  test('a retired sort falls back rather than emptying the board', () async {
    // Stored preferences outlive the code that wrote them. A filter the
    // board can no longer satisfy shows an empty screen with no way to tell
    // why.
    SharedPreferences.setMockInitialValues({
      'board_filters_v1': '{"sortBy":"by_vibes","verdict":"WHENEVER"}',
    });

    final restored = await memory.load(hasProAccess: true);

    expect(restored.sortBy, 'trust');
    expect(restored.verdict, 'ALL');
  });

  test('corrupt storage is not a broken board', () async {
    SharedPreferences.setMockInitialValues({
      'board_filters_v1': 'not json at all',
    });

    final restored = await memory.load(hasProAccess: true);

    expect(restored.sortBy, BoardFilters.defaults.sortBy);
  });

  test('a lapsed subscription cannot be restored around', () async {
    // Remembering a filter must not become a way to keep a paid feature
    // after paying for it stops.
    await memory.save(const BoardFilters(sortBy: 'premium', minConfidence: 70));

    final restored = await memory.load(hasProAccess: false);

    expect(restored.sortBy, isNot('premium'));
    expect(restored.minConfidence, 0);
  });

  test('a pro member keeps the pro filters', () async {
    await memory.save(const BoardFilters(sortBy: 'premium', minConfidence: 70));

    final restored = await memory.load(hasProAccess: true);

    expect(restored.sortBy, 'premium');
    expect(restored.minConfidence, 70);
  });

  test('an out of range confidence is clamped, not trusted', () async {
    SharedPreferences.setMockInitialValues({
      'board_filters_v1': '{"minConfidence": 4000}',
    });

    final restored = await memory.load(hasProAccess: true);

    expect(restored.minConfidence, 0);
  });

  test('the search box is never remembered', () async {
    // A query is about the moment. Restoring one silently hides most of the
    // board behind a term the user has forgotten typing.
    const filters = BoardFilters(category: 'POINTS');

    expect(filters.toJson().containsKey('search'), isFalse);
  });
}
