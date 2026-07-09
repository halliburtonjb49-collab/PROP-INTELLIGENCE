import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActiveSlipController extends ChangeNotifier {
  static const String _storageKey = 'daily_spin_active_slip_v1';

  final List<Map<String, dynamic>> _legs = [];
  bool _isLoaded = false;

  List<Map<String, dynamic>> get legs =>
      List<Map<String, dynamic>>.unmodifiable(_legs);

  bool get isLoaded => _isLoaded;
  bool get isEmpty => _legs.isEmpty;
  int get legCount => _legs.length;

  String _propId(Map<String, dynamic> leg) {
    return leg['prop_id']?.toString() ?? leg['id']?.toString() ?? '';
  }

  String _normalizeSite(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('PRIZEPICKS')) {
      return 'PRIZEPICKS';
    }
    if (normalized.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    if (normalized.contains('SLEEPER')) {
      return 'SLEEPER';
    }
    if (normalized.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (normalized.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    return normalized;
  }

  String _siteForLeg(Map<String, dynamic> leg) {
    return _normalizeSite(
      leg['prop_site']?.toString() ??
          leg['sportsbook']?.toString() ??
          leg['site']?.toString() ??
          '',
    );
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _legs.clear();
    await preferences.remove(_storageKey);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(_legs));
  }

  void _normalizePositions() {
    for (var index = 0; index < _legs.length; index++) {
      _legs[index]['slip_position'] = index;
    }
  }

  bool containsProp(String propId) {
    if (propId.isEmpty) {
      return false;
    }
    return _legs.any((leg) => _propId(leg) == propId);
  }

  Future<int> addLegs(List<Map<String, dynamic>> incomingLegs) async {
    var addedCount = 0;
    var enforcedSite = _legs.isEmpty ? '' : _siteForLeg(_legs.first);
    var changed = false;

    for (final incoming in incomingLegs) {
      final leg = Map<String, dynamic>.from(incoming);
      final incomingSite = _siteForLeg(leg);
      if (enforcedSite.isNotEmpty && incomingSite != enforcedSite) {
        continue;
      }
      final propId = _propId(leg);
      if (propId.isEmpty || containsProp(propId)) {
        continue;
      }

      if (enforcedSite.isEmpty) {
        enforcedSite = incomingSite;
      }

      leg['prop_id'] = propId;
      leg.putIfAbsent('original_line', () => leg['line']);
      leg.putIfAbsent('original_odds', () => leg['odds']);
      leg.putIfAbsent('current_line', () => leg['line']);
      leg.putIfAbsent('current_odds', () => leg['odds']);
      leg.putIfAbsent('movement_status', () => 'UNCHANGED');
      leg.putIfAbsent('result_status', () => 'pending');
      leg.putIfAbsent('custom_label', () => '');
      leg.putIfAbsent('manual_note', () => '');
      leg['added_to_slip_at'] = DateTime.now().toIso8601String();

      _legs.add(leg);
      addedCount += 1;
      changed = true;
    }

    if (changed) {
      _normalizePositions();
      notifyListeners();
      unawaited(_save());
    }

    return addedCount;
  }

  Future<void> removeLeg(String propId) async {
    var changed = false;
    _legs.removeWhere((leg) => _propId(leg) == propId);
    changed = true;
    _normalizePositions();
    if (changed) {
      notifyListeners();
      unawaited(_save());
    }
  }

  Future<void> clear() async {
    if (_legs.isEmpty) {
      return;
    }
    _legs.clear();
    notifyListeners();
    unawaited(_save());
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final leg = _legs.removeAt(oldIndex);
    _legs.insert(newIndex, leg);
    _normalizePositions();
    notifyListeners();
    unawaited(_save());
  }

  Future<void> updateLeg(Map<String, dynamic> updatedLeg) async {
    final propId = _propId(updatedLeg);
    if (propId.isEmpty) {
      return;
    }

    final index = _legs.indexWhere((leg) => _propId(leg) == propId);
    if (index < 0) {
      return;
    }

    final oldPosition = _legs[index]['slip_position'];
    _legs[index] = Map<String, dynamic>.from(updatedLeg);
    _legs[index]['slip_position'] = oldPosition;

    notifyListeners();
    unawaited(_save());
  }

  Future<void> updateMatchingLegs(
    List<Map<String, dynamic>> updatedLegs,
  ) async {
    var changed = false;

    for (final updated in updatedLegs) {
      final propId = _propId(updated);
      if (propId.isEmpty) {
        continue;
      }

      final index = _legs.indexWhere((leg) => _propId(leg) == propId);
      if (index < 0) {
        continue;
      }

      final existing = _legs[index];
      final position = existing['slip_position'];
      final preservedLabel = existing['custom_label'];
      final preservedNote = existing['manual_note'];

      _legs[index] = Map<String, dynamic>.from(updated);
      _legs[index]['slip_position'] = position;

      if ((_legs[index]['custom_label']?.toString().isEmpty ?? true) &&
          preservedLabel != null) {
        _legs[index]['custom_label'] = preservedLabel;
      }

      if ((_legs[index]['manual_note']?.toString().isEmpty ?? true) &&
          preservedNote != null) {
        _legs[index]['manual_note'] = preservedNote;
      }

      changed = true;
    }

    if (changed) {
      notifyListeners();
      unawaited(_save());
    }
  }
}
