import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/main.dart';
import 'package:prop_intelligence/models/prop_data.dart';
import 'package:prop_intelligence/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _prop(String id, String sport) => {
  'id': id,
  'player': '$sport Player',
  'sport': sport,
  'sportsbook': 'FANDUEL',
  'market': 'Points',
  'category': 'POINTS',
  'startTimeUtc': '2099-07-20T20:00:00Z',
  'confidence': sport == 'SOCCER' ? 99 : 60,
};

void main() {
  test(
    'active props are ordered by game time and expired props are removed',
    () {
      final early = PropData.fromJson({
        ..._prop('early', 'NFL'),
        'startTimeUtc': '2099-07-20T18:00:00Z',
      });
      final late = PropData.fromJson({
        ..._prop('late', 'PGA'),
        'startTimeUtc': '2099-07-20T22:00:00Z',
      });
      final expired = PropData.fromJson({
        ..._prop('expired', 'UFC'),
        'startTimeUtc': '2020-07-20T18:00:00Z',
      });

      final ordered = activePropsInChronologicalOrder([late, expired, early]);

      expect(ordered.map((prop) => prop.id), ['early', 'late']);
    },
  );

  test('props without a confirmed game time sort after scheduled props', () {
    final pending = PropData.fromJson({
      ..._prop('pending', 'NFL'),
      'startTimeUtc': '',
    });
    final scheduled = PropData.fromJson({
      ..._prop('scheduled', 'NFL'),
      'startTimeUtc': '2099-07-20T18:00:00Z',
    });

    expect(
      activePropsInChronologicalOrder([
        pending,
        scheduled,
      ]).map((prop) => prop.id),
      ['scheduled', 'pending'],
    );
  });

  test('all-sports display places soccer after available US sports', () {
    final ordered = deprioritizeSoccerForAllSports([
      PropData.fromJson(_prop('soccer', 'soccer_usa_mls')),
      PropData.fromJson(_prop('nba', 'NBA')),
    ], selectedSport: 'ALL');

    expect(ordered.map((prop) => prop.id), ['nba', 'soccer']);
  });

  test('all-sports launch does not render a soccer-only device cache', () {
    final soccerOnly = [PropData.fromJson(_prop('soccer', 'soccer_usa_mls'))];
    final mixed = [...soccerOnly, PropData.fromJson(_prop('nba', 'NBA'))];

    expect(
      shouldRenderCachedPropsOnLaunch(soccerOnly, selectedSport: 'ALL'),
      isFalse,
    );
    expect(
      shouldRenderCachedPropsOnLaunch(mixed, selectedSport: 'ALL'),
      isTrue,
    );
    expect(
      shouldRenderCachedPropsOnLaunch(soccerOnly, selectedSport: 'SOCCER'),
      isTrue,
    );
  });

  test('explicit soccer selection preserves soccer ordering', () {
    final props = [
      PropData.fromJson(_prop('soccer-1', 'SOCCER')),
      PropData.fromJson(_prop('soccer-2', 'SOCCER')),
    ];

    expect(
      deprioritizeSoccerForAllSports(props, selectedSport: 'SOCCER'),
      same(props),
    );
  });

  test(
    'broad startup query falls back to the last stable device feed',
    () async {
      SharedPreferences.setMockInitialValues({
        'prop-feed-v3-all_all_all_all_all__0_source': jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'total': 0,
          'facetTotal': 0,
          'categoryCounts': <String, int>{},
          'props': <Map<String, dynamic>>[],
        }),
        'prop-feed-v3-last-stable': jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'total': 1,
          'facetTotal': 1,
          'categoryCounts': {'POINTS': 1},
          'props': [_prop('cached-nba', 'NBA')],
        }),
      });

      final cached = await ApiService().loadCachedProps(
        selectedSide: 'All',
        selectedTier: 'All',
        selectedSportsbook: 'All',
        selectedSport: 'All',
        selectedCategory: 'All',
        sortBy: 'source',
      );

      expect(cached.map((prop) => prop.id), ['cached-nba']);
    },
  );
}
