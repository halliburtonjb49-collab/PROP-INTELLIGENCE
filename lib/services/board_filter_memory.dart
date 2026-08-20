import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The board filters a user last chose, remembered between visits.
///
/// Rebuilding the same filters on every return is the tax this removes. The
/// search box is deliberately not part of it: a query is about the moment,
/// and restoring one silently hides most of the board behind a term the user
/// has forgotten typing.
class BoardFilters {
  const BoardFilters({
    this.site = 'ALL',
    this.category = 'ALL',
    this.sortBy = 'trust',
    this.verdict = 'ACTIONABLE',
    this.minConfidence = 0,
  });

  /// Playable, ranked by trust. Where the board opens, and so also where
  /// clearing the filters has to land.
  static const BoardFilters defaults = BoardFilters();

  static const sortOptions = {'trust', 'edge', 'source', 'premium', 'time'};
  static const verdictOptions = {
    'ACTIONABLE',
    'PLAY_NOW',
    'LEAN',
    'SHOP',
    'WAIT',
    'ALL',
  };

  final String site;
  final String category;
  final String sortBy;
  final String verdict;
  final int minConfidence;

  Map<String, dynamic> toJson() => {
    'site': site,
    'category': category,
    'sortBy': sortBy,
    'verdict': verdict,
    'minConfidence': minConfidence,
  };

  /// Rebuild from stored values, replacing anything unrecognised.
  ///
  /// Stored preferences outlive the code that wrote them: a renamed sort or
  /// a retired verdict would otherwise restore a filter the board can no
  /// longer satisfy, and the user would see an empty board with no way to
  /// tell why.
  factory BoardFilters.fromJson(Map<String, dynamic> json) {
    String pick(String key, Set<String> allowed, String fallback) {
      final value = json[key]?.toString().trim().toUpperCase() ?? '';
      final match = allowed.firstWhere(
        (option) => option.toUpperCase() == value,
        orElse: () => fallback,
      );
      return match;
    }

    final confidence = (json['minConfidence'] as num?)?.toInt() ?? 0;
    return BoardFilters(
      site: json['site']?.toString().trim().toUpperCase() ?? 'ALL',
      category: json['category']?.toString().trim().toUpperCase() ?? 'ALL',
      sortBy: pick('sortBy', sortOptions, defaults.sortBy),
      verdict: pick('verdict', verdictOptions, defaults.verdict),
      minConfidence: confidence.clamp(0, 100),
    );
  }

  /// Drop anything this member is not entitled to.
  ///
  /// Restoring a saved filter must not become a way to keep using a feature
  /// after a subscription lapses.
  BoardFilters withinEntitlements({required bool hasProAccess}) {
    if (hasProAccess) return this;
    return BoardFilters(
      site: site,
      category: category,
      sortBy: sortOptions.contains(sortBy) && sortBy != 'premium'
          ? sortBy
          : defaults.sortBy,
      verdict: verdict,
      minConfidence: 0,
    );
  }
}

class BoardFilterMemory {
  const BoardFilterMemory({this.storageKey = 'board_filters_v1'});

  final String storageKey;

  Future<void> save(BoardFilters filters) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(storageKey, jsonEncode(filters.toJson()));
    } catch (_) {
      // Remembering a filter is a convenience. Failing to store one must
      // never interrupt the board.
    }
  }

  Future<BoardFilters> load({required bool hasProAccess}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(storageKey);
      if (stored == null || stored.isEmpty) {
        return BoardFilters.defaults;
      }
      final decoded = jsonDecode(stored);
      if (decoded is! Map) {
        return BoardFilters.defaults;
      }
      return BoardFilters.fromJson(
        Map<String, dynamic>.from(decoded),
      ).withinEntitlements(hasProAccess: hasProAccess);
    } catch (_) {
      return BoardFilters.defaults;
    }
  }

  Future<void> clear() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(storageKey);
    } catch (_) {
      // Same reasoning as save.
    }
  }
}
