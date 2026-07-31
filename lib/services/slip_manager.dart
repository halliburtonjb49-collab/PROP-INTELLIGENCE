import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../models/saved_slip.dart';
import 'api_service.dart';

class SlipManager {
  // A dynamic notifier tracking our current list of selected prop slips.
  static final ValueNotifier<List<Map<String, dynamic>>> selectedProps =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  static final ValueNotifier<Set<String>> lockedPropIds =
      ValueNotifier<Set<String>>(<String>{});

  static void reserveActiveSlips(Iterable<SavedSlip> slips) {
    lockedPropIds.value = {
      for (final slip in slips)
        if (slip.status.toLowerCase() == 'active')
          for (final leg in slip.legs)
            if (leg.propId.isNotEmpty) leg.propId,
    };
  }

  static bool isLockedInActiveSlip(String propId) =>
      propId.isNotEmpty && lockedPropIds.value.contains(propId);

  // Toggles adding or removing a prop card from the workspace slip.
  static void togglePropSelection(Map<String, dynamic> prop) {
    final currentList = List<Map<String, dynamic>>.from(selectedProps.value);

    final incomingId = _propId(prop);
    if (incomingId.isEmpty) {
      return;
    }
    if (isLockedInActiveSlip(incomingId)) {
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
    if (isLockedInActiveSlip(incomingId)) {
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

    String normalized(Object? value) =>
        value?.toString().trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '',
        ) ??
        '';

    PropData? semanticMatch(Map<String, dynamic> entry) {
      final player = normalized(entry['player_name'] ?? entry['player']);
      final market = normalized(entry['market_type'] ?? entry['market']);
      final eventId = normalized(entry['event_id'] ?? entry['eventId']);
      final oddsData = entry['odds_data'];
      final firstOdds = oddsData is List && oddsData.isNotEmpty
          ? oddsData.first
          : null;
      final site = normalized(
        entry['sportsbook'] ??
            entry['site'] ??
            (firstOdds is Map ? firstOdds['bookmaker'] : null),
      );
      for (final prop in latestProps) {
        if (normalized(prop.player) != player ||
            normalized(prop.market) != market ||
            normalized(prop.sportsbook) != site) {
          continue;
        }
        if (eventId.isEmpty || normalized(prop.eventId) == eventId) {
          return prop;
        }
      }
      return null;
    }

    final refreshed = currentList
        .map((entry) {
          final id = _propId(entry);
          final latest = byId[id] ?? semanticMatch(entry);
          if (latest == null) {
            return entry;
          }

          return {
            ...entry,
            'id': latest.id,
            'prop_id': latest.id,
            'original_line': entry['original_line'] ?? entry['line'],
            'current_line': latest.line,
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
