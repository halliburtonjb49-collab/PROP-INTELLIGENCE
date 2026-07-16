import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class PropWatchlistService {
  static const String _storageKey = 'prop_intelligence_prop_watchlist_v1';
  final SportsAppAuthService _authService = SportsAppAuthService();

  Future<List<Map<String, dynamic>>> loadWatchlist({
    bool includeCloudSync = false,
  }) async {
    if (includeCloudSync) {
      return syncLocalAndCloudWatchlist();
    }

    final preferences = await SharedPreferences.getInstance();
    final rawValue = preferences.getString(_storageKey);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List<dynamic>) {
        return [];
      }
      final props = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      return props;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> syncLocalAndCloudWatchlist() async {
    final localProps = await loadWatchlist(includeCloudSync: false);

    List<Map<String, dynamic>> cloudRows;
    try {
      cloudRows = await _authService.loadCloudWatchlist();
    } catch (_) {
      cloudRows = const [];
    }

    final merged = <String, Map<String, dynamic>>{};

    for (final row in cloudRows) {
      final playerId = row['player_id']?.toString().trim() ?? '';
      if (playerId.isEmpty) {
        continue;
      }

      merged[playerId] = {
        'prop_id': playerId,
        'player_name': row['player_name']?.toString() ?? '',
        'player': row['player_name']?.toString() ?? '',
        'watchlisted_at':
            row['updated_at']?.toString() ?? row['created_at']?.toString(),
      };
    }

    for (final prop in localProps) {
      final propId = prop['prop_id']?.toString().trim() ?? '';
      if (propId.isEmpty) {
        continue;
      }

      final existing = merged[propId] ?? const {};
      merged[propId] = {...existing, ...Map<String, dynamic>.from(prop)};
    }

    final mergedList = merged.values.toList(growable: false);
    await saveWatchlist(mergedList);

    try {
      await _authService.upsertCloudWatchlist(mergedList);
    } catch (_) {
      // Cloud sync should not block local experience.
    }

    return mergedList;
  }

  Future<void> saveWatchlist(List<Map<String, dynamic>> props) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(props));
  }

  Future<bool> containsProp(String propId) async {
    final props = await loadWatchlist();
    return props.any((prop) => prop['prop_id']?.toString() == propId);
  }

  Future<void> addProp(Map<String, dynamic> prop) async {
    final props = await loadWatchlist();
    final propId = prop['prop_id']?.toString() ?? '';
    if (propId.isEmpty) {
      return;
    }

    final existingIndex = props.indexWhere(
      (item) => item['prop_id']?.toString() == propId,
    );
    final storedProp = Map<String, dynamic>.from(prop);
    storedProp['watchlisted_at'] = DateTime.now().toIso8601String();

    if (existingIndex >= 0) {
      props[existingIndex] = storedProp;
    } else {
      props.insert(0, storedProp);
    }

    await saveWatchlist(props);

    final playerName =
        storedProp['player_name']?.toString() ??
        storedProp['player']?.toString() ??
        '';
    if (playerName.trim().isNotEmpty) {
      try {
        await _authService.savePlayerToCloudWatchlist(propId, playerName);
      } catch (_) {
        // Keep local watchlist functional even when cloud sync is unavailable.
      }
    }
  }

  Future<void> removeProp(String propId) async {
    final props = await loadWatchlist();
    props.removeWhere((prop) => prop['prop_id']?.toString() == propId);
    await saveWatchlist(props);
  }

  Future<void> clearWatchlist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}
