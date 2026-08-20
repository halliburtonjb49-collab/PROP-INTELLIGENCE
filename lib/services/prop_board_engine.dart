import '../models/prop_data.dart';

class PreparedBoardProp {
  const PreparedBoardProp({
    required this.prop,
    required this.normalizedSport,
    required this.normalizedSite,
    required this.searchText,
    required this.scheduledStart,
  });

  final PropData prop;
  final String normalizedSport;
  final String normalizedSite;
  final String searchText;

  /// Parsed once here rather than inside the sort comparator.
  ///
  /// Every sort ordering starts with game time, so the comparator parsed two
  /// date strings per comparison: about 350,000 parses for a full board, on
  /// every rebuild, which is what made favouriting a prop or switching books
  /// stall the screen.
  final DateTime? scheduledStart;
}

String normalizePropSite(String value) {
  final normalized = value
      .trim()
      .toUpperCase()
      .replaceAll(' ', '')
      .replaceAll('_', '')
      .replaceAll('-', '');
  if (normalized.contains('PICK6')) return 'PICK6';
  if (normalized.contains('PRIZEPICKS')) return 'PRIZEPICKS';
  if (normalized.contains('DRAFTKINGS')) return 'DRAFTKINGS';
  if (normalized.contains('DRAFTPICKS')) return 'DRAFT PICKS';
  if (normalized.contains('FANDUEL')) return 'FANDUEL';
  if (normalized.contains('UNDERDOG')) return 'UNDERDOG';
  if (normalized.contains('BETR')) return 'BETR';
  return normalized;
}

String normalizePropSport(String value) {
  final normalized = value
      .trim()
      .toUpperCase()
      .replaceAll(' ', '')
      .replaceAll('_', '')
      .replaceAll('-', '');
  if (normalized.contains('UFC') ||
      normalized.contains('MMA') ||
      normalized.contains('ULTIMATEFIGHTING')) {
    return 'UFC';
  }
  if (normalized.contains('WNBA')) return 'WNBA';
  if (normalized.contains('NCAAB')) return 'NCAAB';
  if (normalized.contains('NBA')) return 'NBA';
  if (normalized.contains('NCAAF')) return 'NCAAF';
  if (normalized.contains('CFL')) return 'CFL';
  if (normalized.contains('NFL') || normalized.contains('FOOTBALL')) {
    return 'NFL';
  }
  if (normalized.contains('MLB') || normalized.contains('BASEBALL')) {
    return 'MLB';
  }
  if (normalized.contains('SOCCER') ||
      normalized.contains('EPL') ||
      normalized.contains('MLS')) {
    return 'SOCCER';
  }
  if (normalized.contains('TENNIS') ||
      normalized.contains('ATP') ||
      normalized.contains('WTA')) {
    return 'TENNIS';
  }
  if (normalized.contains('PGA') || normalized.contains('GOLF')) return 'PGA';
  return normalized;
}

String propSearchableMarket(PropData prop) {
  final candidates = [
    prop.market,
    prop.marketName,
    prop.statType,
    prop.category,
    prop.propType,
    prop.displayMarket,
    prop.marketKey,
  ];
  return candidates.firstWhere(
    (value) =>
        value.trim().isNotEmpty &&
        !const {
          'other',
          'unknown',
          'n/a',
          'na',
        }.contains(value.trim().toLowerCase()),
    orElse: () => '',
  );
}

List<PreparedBoardProp> prepareBoardProps(Iterable<PropData> props) {
  return props
      .map((prop) {
        final market = propSearchableMarket(prop);
        return PreparedBoardProp(
          prop: prop,
          normalizedSport: normalizePropSport(prop.sport),
          normalizedSite: normalizePropSite(
            '${prop.sportsbook} ${prop.sourceProvider}',
          ),
          searchText: '${prop.player} ${prop.matchup} ${prop.sport} $market'
              .toLowerCase(),
          scheduledStart: propScheduledStart(prop),
        );
      })
      .toList(growable: false);
}

int _tierRank(String tier) => switch (tier.trim().toLowerCase()) {
  'premium' => 3,
  'strong' => 2,
  'lean' => 1,
  _ => 0,
};

DateTime? propScheduledStart(PropData prop) {
  final raw = prop.startTimeUtc.isNotEmpty
      ? prop.startTimeUtc
      : prop.gameStartTime;
  return DateTime.tryParse(raw);
}

List<PropData> filterAndSortBoardProps(
  Iterable<PreparedBoardProp> prepared, {
  required String selectedSport,
  required String selectedSite,
  required String searchQuery,
  required String verdictFilter,
  required String sortBy,
  Set<String> pinnedPropIds = const {},
}) {
  final normalizedSport = normalizePropSport(selectedSport);
  final normalizedSite = normalizePropSite(selectedSite);
  final search = searchQuery.trim().toLowerCase();
  final verdict = verdictFilter.trim().toUpperCase();

  final props = prepared
      .where((item) {
        final sportMatches =
            normalizedSport == 'ALL' || item.normalizedSport == normalizedSport;
        final siteMatches =
            normalizedSite == 'ALL' || item.normalizedSite == normalizedSite;
        final searchMatches =
            search.isEmpty || item.searchText.contains(search);
        final verdictMatches =
            verdict == 'ALL' ||
            (verdict == 'ACTIONABLE'
                ? item.prop.verdict.actionable
                : item.prop.verdict.decision == verdict);
        // A prop can be legitimate live inventory while PI is still waiting
        // for a lineup, projection, or another verification input. Keep it on
        // the research board so category totals and cards describe the same
        // catalog. PropData.isSelectable continues to guard the pick buttons,
        // so incomplete props cannot be added to a slip.
        return sportMatches && siteMatches && searchMatches && verdictMatches;
      })
      .toList(growable: true);

  props.sort((leftPrepared, rightPrepared) {
    final left = leftPrepared.prop;
    final right = rightPrepared.prop;
    final leftStart = leftPrepared.scheduledStart;
    final rightStart = rightPrepared.scheduledStart;
    if (leftStart == null && rightStart != null) return 1;
    if (leftStart != null && rightStart == null) return -1;
    if (leftStart != null && rightStart != null) {
      final start = leftStart.compareTo(rightStart);
      if (start != 0) return start;
    }

    final leftPinned = pinnedPropIds.contains(left.id);
    final rightPinned = pinnedPropIds.contains(right.id);
    if (leftPinned != rightPinned) return leftPinned ? -1 : 1;

    var rank = 0;
    switch (sortBy.trim().toLowerCase()) {
      case 'source':
      case 'time':
        break;
      case 'edge':
        rank = (right.calculatedEdge ?? 0).compareTo(left.calculatedEdge ?? 0);
        break;
      case 'trust':
        rank = right.piTrustScore.compareTo(left.piTrustScore);
        break;
      case 'premium':
        final rankDiff = _tierRank(right.tier) - _tierRank(left.tier);
        rank = rankDiff != 0
            ? rankDiff
            : (right.displayConfidenceRating ?? -1).compareTo(
                left.displayConfidenceRating ?? -1,
              );
        break;
      case 'verdict':
        final verdictDiff = right.verdict.actionRank - left.verdict.actionRank;
        rank = verdictDiff != 0
            ? verdictDiff
            : (right.displayConfidenceRating ?? -1).compareTo(
                left.displayConfidenceRating ?? -1,
              );
        break;
      case 'confidence':
      default:
        rank = (right.displayConfidenceRating ?? -1).compareTo(
          left.displayConfidenceRating ?? -1,
        );
        break;
    }
    if (rank != 0) return rank;
    final player = left.player.compareTo(right.player);
    if (player != 0) return player;
    final market = left.market.compareTo(right.market);
    return market != 0 ? market : left.id.compareTo(right.id);
  });
  return props.map((item) => item.prop).toList(growable: false);
}

List<PropData> deprioritizeSoccerForAllSports(
  List<PropData> props, {
  required String selectedSport,
}) {
  if (selectedSport.trim().toUpperCase() != 'ALL' || props.length < 2) {
    return props;
  }
  final otherSports = <PropData>[];
  final soccer = <PropData>[];
  for (final prop in props) {
    final sport = prop.sport.trim().toUpperCase();
    if (sport == 'SOCCER' || sport.startsWith('SOCCER_')) {
      soccer.add(prop);
    } else {
      otherSports.add(prop);
    }
  }
  if (otherSports.isEmpty || soccer.isEmpty) return props;
  return [...otherSports, ...soccer];
}

List<PropData> pinSelectedPropsFirst(
  List<PropData> props,
  Set<String> pinnedPropIds,
) {
  if (props.isEmpty || pinnedPropIds.isEmpty) return props;
  final pinned = <PropData>[];
  final remaining = <PropData>[];
  for (final prop in props) {
    (pinnedPropIds.contains(prop.id) ? pinned : remaining).add(prop);
  }
  return [...pinned, ...remaining];
}

List<PropData> activePropsInChronologicalOrder(Iterable<PropData> props) {
  // Keep legitimate pregame research inventory visible even when a missing
  // verification input makes the pick buttons unavailable. Started/final
  // events are still removed here; isSelectable remains the slip gate.
  final active = props.where((prop) => !prop.gameHasStarted).toList();
  active.sort((left, right) {
    final leftStart = propScheduledStart(left);
    final rightStart = propScheduledStart(right);
    if (leftStart == null && rightStart == null) {
      final player = left.player.compareTo(right.player);
      return player != 0 ? player : left.market.compareTo(right.market);
    }
    if (leftStart == null) return 1;
    if (rightStart == null) return -1;
    final start = leftStart.compareTo(rightStart);
    if (start != 0) return start;
    final player = left.player.compareTo(right.player);
    return player != 0 ? player : left.market.compareTo(right.market);
  });
  return active;
}

bool shouldRenderCachedPropsOnLaunch(
  List<PropData> props, {
  required String selectedSport,
}) {
  if (props.isEmpty) return false;
  if (selectedSport.trim().toUpperCase() != 'ALL') return true;
  return props.any((prop) {
    final sport = prop.sport.trim().toUpperCase();
    return sport != 'SOCCER' && !sport.startsWith('SOCCER_');
  });
}

bool isNarrowedBoardQuery({
  required String sport,
  required String site,
  required String category,
  required String side,
  required String tier,
  required String search,
  required int minConfidence,
}) {
  bool isAll(String value) => value.trim().toUpperCase() == 'ALL';
  return !isAll(sport) ||
      !isAll(site) ||
      !isAll(category) ||
      !isAll(side) ||
      !isAll(tier) ||
      search.trim().isNotEmpty ||
      minConfidence > 0;
}

bool hasActiveBoardFilters({
  required String sport,
  required String site,
  required String category,
  required String side,
  required String tier,
  required String verdict,
  required String search,
  required int minConfidence,
}) {
  return isNarrowedBoardQuery(
        sport: sport,
        site: site,
        category: category,
        side: side,
        tier: tier,
        search: search,
        minConfidence: minConfidence,
      ) ||
      verdict.trim().toUpperCase() != 'ALL';
}
