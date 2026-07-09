import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PropWatchlistService {
  static const String _storageKey = 'daily_spin_prop_watchlist_v1';

  Future<List<Map<String, dynamic>>> loadWatchlist() async {
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
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
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
