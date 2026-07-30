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
  test('all-sports display places soccer after available US sports', () {
    final ordered = deprioritizeSoccerForAllSports([
      PropData.fromJson(_prop('soccer', 'SOCCER')),
      PropData.fromJson(_prop('nba', 'NBA')),
    ], selectedSport: 'ALL');

    expect(ordered.map((prop) => prop.id), ['nba', 'soccer']);
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
        'prop-feed-v2-all_all_all_all_all__0_source': jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'total': 0,
          'facetTotal': 0,
          'categoryCounts': <String, int>{},
          'props': <Map<String, dynamic>>[],
        }),
        'prop-feed-v2-last-stable': jsonEncode({
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
