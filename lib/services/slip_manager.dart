import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import 'api_service.dart';

class SlipManager {
  // A dynamic notifier tracking our current list of selected prop slips.
  static final ValueNotifier<List<Map<String, dynamic>>> selectedProps =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  // Toggles adding or removing a prop card from the workspace slip.
  static void togglePropSelection(Map<String, dynamic> prop) {
    final currentList = List<Map<String, dynamic>>.from(selectedProps.value);

    final incomingId = _propId(prop);
    if (incomingId.isEmpty) {
      return;
    }

    final existingIndex = currentList.indexWhere(
      (element) => _propId(element) == incomingId,
    );

    if (existingIndex >= 0) {
      currentList.removeAt(existingIndex);
    } else {
      currentList.add(Map<String, dynamic>.from(prop));
    }

    selectedProps.value = currentList;
  }

  static void upsertProp(Map<String, dynamic> prop) {
    final currentList = List<Map<String, dynamic>>.from(selectedProps.value);
    final incomingId = _propId(prop);
    if (incomingId.isEmpty) {
      return;
    }

    final existingIndex = currentList.indexWhere(
      (element) => _propId(element) == incomingId,
    );

    if (existingIndex >= 0) {
      currentList[existingIndex] = {
        ...currentList[existingIndex],
        ...Map<String, dynamic>.from(prop),
      };
    } else {
      currentList.add(Map<String, dynamic>.from(prop));
    }

    selectedProps.value = currentList;
  }

  static void removePropById(String propId) {
    if (propId.trim().isEmpty) {
      return;
    }
    final currentList = List<Map<String, dynamic>>.from(selectedProps.value)
      ..removeWhere((element) => _propId(element) == propId);
    selectedProps.value = currentList;
  }

  static bool containsPropId(String propId) {
    if (propId.trim().isEmpty) {
      return false;
    }
    return selectedProps.value.any((entry) => _propId(entry) == propId);
  }

  static Future<void> refreshSelectedProps(ApiService apiService) async {
    final currentList = List<Map<String, dynamic>>.from(selectedProps.value);
    if (currentList.isEmpty) {
      return;
    }

    final latestProps = await apiService.fetchProps();
    final byId = <String, PropData>{
      for (final prop in latestProps) prop.id: prop,
    };

    final refreshed = currentList
        .map((entry) {
          final id = _propId(entry);
          final latest = byId[id];
          if (latest == null) {
            return entry;
          }

          return {
            ...entry,
            'line': latest.line,
            'market_type': latest.market,
            'player_name': latest.player,
            'edge_percentage': latest.edge,
            'ai_projection': latest.projection,
            'sport': latest.sport,
            'odds_data': [
              {
                'bookmaker': latest.sportsbook,
                'over_odds': (latest.overOdds ?? entry['odds'] ?? -110),
                'under_odds': (latest.underOdds ?? entry['odds'] ?? -110),
                'last_update': latest.lastUpdatedLocalDisplay,
              },
            ],
          };
        })
        .toList(growable: false);

    selectedProps.value = refreshed;
  }

  // Clear all items out of the tracking slip at once.
  static void clearAllSlips() {
    selectedProps.value = [];
  }

  static String _propId(Map<String, dynamic> leg) {
    return leg['id']?.toString() ?? leg['prop_id']?.toString() ?? '';
  }
}
