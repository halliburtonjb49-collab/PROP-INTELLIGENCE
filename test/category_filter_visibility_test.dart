import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';

void main() {
  test('category filters contain only positive live categories', () {
    expect(
      visibleCategoryFilters({
        'HITS': 18,
        'SINGLES': 44,
        'PITCHER STRIKEOUTS': 0,
      }),
      ['ALL', 'SINGLES', 'HITS'],
    );
  });

  test('categories from one prop site do not leak into another', () {
    final prizePicks = visibleCategoryFilters({'HITS': 18, 'SINGLES': 44});
    final underdog = visibleCategoryFilters({
      'PITCHER STRIKEOUTS': 17,
      'TOTAL BASES': 9,
    });

    expect(prizePicks, ['ALL', 'SINGLES', 'HITS']);
    expect(prizePicks, isNot(contains('PITCHER STRIKEOUTS')));
    expect(underdog, ['ALL', 'PITCHER STRIKEOUTS', 'TOTAL BASES']);
    expect(underdog, isNot(contains('SINGLES')));
  });

  test('equal counts are ordered consistently by category name', () {
    expect(visibleCategoryFilters({'REBOUNDS': 12, 'ASSISTS': 12}), [
      'ALL',
      'ASSISTS',
      'REBOUNDS',
    ]);
  });

  test('NFL rushing attempts keep their own category', () {
    expect(marketCategoryFor('NFL', 'player_rush_attempts'), 'RUSH ATTEMPTS');
    expect(marketCategoryFor('NFL', 'rushing attempts'), 'RUSH ATTEMPTS');
  });
}
