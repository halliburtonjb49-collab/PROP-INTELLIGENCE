import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_slip.dart';
import '../models/prop_data.dart';

class ActiveSlipController extends ChangeNotifier {
  static const String _storageKey = 'prop_intelligence_active_slip_v1';

  final List<Map<String, dynamic>> _legs = [];
  bool _isLoaded = false;

  List<Map<String, dynamic>> get legs =>
      List<Map<String, dynamic>>.unmodifiable(_legs);

  bool get isLoaded => _isLoaded;
  bool get isEmpty => _legs.isEmpty;
  int get legCount => _legs.length;

  int _lockedSlipCount = 0;
  final List<SavedSlip> _recentLockedSlips = [];

  /// Count of the user's currently-active (locked, unresolved) saved slips,
  /// kept in sync by SlipHistoryPanel whenever it fetches from the server.
  /// Lives here (rather than a new singleton) since this controller is
  /// already shared between the sidebar and the slip watcher panel.
  int get lockedSlipCount => _lockedSlipCount;
  List<SavedSlip> get recentLockedSlips =>
      List<SavedSlip>.unmodifiable(_recentLockedSlips);

  void setLockedSlipCount(int count) {
    if (_lockedSlipCount == count) return;
    _lockedSlipCount = count;
    notifyListeners();
  }

  void addOptimisticLockedSlip(SavedSlip slip) {
    _recentLockedSlips.removeWhere((existing) => existing.id == slip.id);
    _recentLockedSlips.insert(0, slip);
    _lockedSlipCount += 1;
    notifyListeners();
  }

  void replaceOptimisticLockedSlip(String temporaryId, SavedSlip saved) {
    final index = _recentLockedSlips.indexWhere(
      (existing) => existing.id == temporaryId,
    );
    if (index < 0) {
      _recentLockedSlips.insert(0, saved);
    } else {
      _recentLockedSlips[index] = saved;
    }
    notifyListeners();
  }

  void removeOptimisticLockedSlip(String temporaryId) {
    final before = _recentLockedSlips.length;
    _recentLockedSlips.removeWhere((existing) => existing.id == temporaryId);
    final removed = before - _recentLockedSlips.length;
    if (removed > 0) {
      _lockedSlipCount = _lockedSlipCount > removed
          ? _lockedSlipCount - removed
          : 0;
      notifyListeners();
    }
  }

  void removeLockedSlip(String slipId) {
    final before = _recentLockedSlips.length;
    _recentLockedSlips.removeWhere((slip) => slip.id == slipId);
    if (_recentLockedSlips.length == before) return;
    _lockedSlipCount = _lockedSlipCount > 0 ? _lockedSlipCount - 1 : 0;
    notifyListeners();
  }

  void reconcileActiveLockedSlips(Iterable<SavedSlip> activeSlips) {
    final activeIds = activeSlips.map((slip) => slip.id).toSet();
    final before = _recentLockedSlips.length;
    _recentLockedSlips.removeWhere(
      (slip) => !slip.id.startsWith('pending-') && !activeIds.contains(slip.id),
    );
    if (_recentLockedSlips.length != before) notifyListeners();
  }

  List<SavedSlip> mergeWithRecentLockedSlips(List<SavedSlip> serverSlips) {
    final serverIds = serverSlips.map((slip) => slip.id).toSet();
    return [
      ..._recentLockedSlips.where(
        (slip) =>
            slip.id.startsWith('pending-') && !serverIds.contains(slip.id),
      ),
      ...serverSlips,
    ];
  }

  String _propId(Map<String, dynamic> leg) {
    return leg['prop_id']?.toString() ?? leg['id']?.toString() ?? '';
  }

  String _normalizeSite(String value) {
    final normalized = value.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
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
    if (normalized.contains('DRAFTPICKS')) return 'DRAFTPICKS';
    if (normalized.contains('BETMGM')) return 'BETMGM';
    if (normalized.contains('CAESARS')) return 'CAESARS';
    if (normalized.contains('BET365')) return 'BET365';
    if (normalized.contains('ESPNBET')) return 'ESPNBET';
    return normalized;
  }

  String _siteForLeg(Map<String, dynamic> leg) {
    for (final key in const ['prop_site', 'sportsbook', 'site']) {
      final value = leg[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return _normalizeSite(value);
    }
    return '';
  }

  Future<void> refreshFromProps(Iterable<PropData> props) async {
    final latestById = {for (final prop in props) prop.id: prop};
    var changed = false;
    for (final leg in _legs) {
      final latest = latestById[_propId(leg)];
      if (latest == null) continue;
      final selectedSide = (leg['side'] ?? leg['pick'])
          ?.toString()
          .trim()
          .toUpperCase();
      final latestOdds = selectedSide == 'UNDER'
          ? latest.underOdds
          : latest.overOdds;
      if (leg['current_line'] != latest.line ||
          (latestOdds != null && leg['current_odds'] != latestOdds)) {
        leg['line'] = latest.line;
        leg['current_line'] = latest.line;
        leg['current_odds'] = latestOdds ?? leg['current_odds'];
        leg['over_odds'] = latest.overOdds;
        leg['under_odds'] = latest.underOdds;
        leg['line_moved_at_utc'] = latest.lineMovedAtUtc;
        leg['last_updated_utc'] = latest.lastUpdatedUtc;
        leg['movement_status'] = 'UPDATED';
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _legs.clear();

    final storedValue = preferences.getString(_storageKey);
    if (storedValue != null && storedValue.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedValue);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) {
              _legs.add(Map<String, dynamic>.from(entry));
            }
          }
        }
      } catch (_) {
        await preferences.remove(_storageKey);
      }
    }

    _normalizePositions();
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
