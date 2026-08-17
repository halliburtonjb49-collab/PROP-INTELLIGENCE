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

  test('coverage warning selects the issue for the active sport', () {
    final issue = providerCoverageIssueForSport({
      'limited': true,
      'issues': [
        {
          'sport': 'MLB',
          'category': 'BATTER WALKS',
          'selectedCount': 2,
          'benchmarkCount': 36,
        },
        {
          'sport': 'MLB',
          'category': 'HITS + RUNS + RBIS',
          'selectedCount': 9,
          'benchmarkCount': 36,
        },
      ],
    }, 'mlb');

    expect(issue, isNotNull);
    expect(issue!['selectedCount'], 2);
    final categoryIssue = providerCoverageIssueForSport(
      {
        'limited': true,
        'issues': [
          {'sport': 'MLB', 'category': 'BATTER WALKS', 'selectedCount': 2},
          {
            'sport': 'MLB',
            'category': 'HITS + RUNS + RBIS',
            'selectedCount': 9,
          },
        ],
      },
      'mlb',
      'hits + runs + rbis',
    );
    expect(categoryIssue?['selectedCount'], 9);
    expect(
      providerCoverageIssueForSport(
        {
          'limited': true,
          'issues': [
            {'sport': 'MLB', 'category': 'BATTER WALKS'},
          ],
        },
        'MLB',
        'HITS',
      ),
      isNull,
    );
    expect(providerCoverageIssueForSport({'limited': false}, 'MLB'), isNull);
    expect(
      providerCoverageIssueForSport({
        'limited': true,
        'issues': [
          {'sport': 'NFL', 'selectedCount': 9},
        ],
      }, 'MLB'),
      isNull,
    );
  });

  test('NFL rushing attempts keep their own category', () {
    expect(marketCategoryFor('NFL', 'player_rush_attempts'), 'RUSH ATTEMPTS');
    expect(marketCategoryFor('NFL', 'rushing attempts'), 'RUSH ATTEMPTS');
  });

  test('Caitlin Clark player-assist labels stay in ASSISTS', () {
    expect(marketCategoryFor('WNBA', 'Player Assists'), 'ASSISTS');
    expect(marketCategoryFor('WNBA', 'player_assists'), 'ASSISTS');
  });
}
