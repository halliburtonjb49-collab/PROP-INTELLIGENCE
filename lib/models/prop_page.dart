import 'prop_data.dart';

enum PropPageStatus {
  idle,
  checking,
  updating,
  current,
  providerDelayed,
  reconnecting,
  offlineSaved,
}

class PropQuery {
  const PropQuery({
    this.side = 'All',
    this.tier = 'All',
    this.sportsbook = 'All',
    this.sport = 'All',
    this.category = 'All',
    this.search = '',
    this.minConfidence = 0,
    this.sortBy = 'confidence',
    this.verdict = 'All',
    this.limit = 24,
    this.offset = 0,
    this.includeReliability = false,
    this.schemaVersion = 1,
    required this.accessScope,
  });

  final String side;
  final String tier;
  final String sportsbook;
  final String sport;
  final String category;
  final String search;
  final int minConfidence;
  final String sortBy;
  final String verdict;
  final int limit;
  final int offset;
  final bool includeReliability;
  final int schemaVersion;
  final String accessScope;

  String get key => <Object>[
    schemaVersion,
    accessScope,
    side,
    tier,
    sportsbook,
    sport,
    category,
    search,
    minConfidence,
    sortBy,
    verdict,
    limit,
    offset,
    includeReliability,
  ].map((value) => Uri.encodeComponent('$value')).join('|');

  PropQuery copyWith({int? offset, int? limit, String? accessScope}) =>
      PropQuery(
        side: side,
        tier: tier,
        sportsbook: sportsbook,
        sport: sport,
        category: category,
        search: search,
        minConfidence: minConfidence,
        sortBy: sortBy,
        verdict: verdict,
        limit: limit ?? this.limit,
        offset: offset ?? this.offset,
        includeReliability: includeReliability,
        schemaVersion: schemaVersion,
        accessScope: accessScope ?? this.accessScope,
      );
}

class PropPage {
  PropPage({
    required this.query,
    required List<PropData> rows,
    required this.catalogCount,
    required this.totalCount,
    required this.facetCount,
    required Map<String, int> categoryCounts,
    required Map<String, int> totalCategoryCounts,
    required Map<String, int> playableCategoryCounts,
    required Map<String, int> sportCounts,
    required Map<String, int> sportsbookCounts,
    required Map<String, int> verdictCounts,
    required Map<String, Map<String, int>> sportCategoryCounts,
    required Map<String, Map<String, int>> totalSportCategoryCounts,
    required Map<String, Map<String, int>> playableSportCategoryCounts,
    required Map<String, dynamic> providerCoverage,
    required Map<String, dynamic> providerReliability,
    required this.feedSource,
    required this.feedIsRecovery,
    required this.receivedAt,
    this.sourceUpdatedAt,
    this.validator,
    this.contentRevision,
    this.backendVersion,
    this.status = PropPageStatus.current,
    this.isFromCache = false,
  }) : rows = List<PropData>.unmodifiable(rows),
       categoryCounts = Map<String, int>.unmodifiable(categoryCounts),
       totalCategoryCounts = Map<String, int>.unmodifiable(totalCategoryCounts),
       playableCategoryCounts = Map<String, int>.unmodifiable(
         playableCategoryCounts,
       ),
       sportCounts = Map<String, int>.unmodifiable(sportCounts),
       sportsbookCounts = Map<String, int>.unmodifiable(sportsbookCounts),
       verdictCounts = Map<String, int>.unmodifiable(verdictCounts),
       sportCategoryCounts = _freezeNestedCounts(sportCategoryCounts),
       totalSportCategoryCounts = _freezeNestedCounts(totalSportCategoryCounts),
       playableSportCategoryCounts = _freezeNestedCounts(
         playableSportCategoryCounts,
       ),
       providerCoverage = _freezeDynamicMap(providerCoverage),
       providerReliability = _freezeDynamicMap(providerReliability);

  final PropQuery query;
  final List<PropData> rows;
  final int catalogCount;
  final int totalCount;
  final int facetCount;
  final Map<String, int> categoryCounts;
  final Map<String, int> totalCategoryCounts;
  final Map<String, int> playableCategoryCounts;
  final Map<String, int> sportCounts;
  final Map<String, int> sportsbookCounts;
  final Map<String, int> verdictCounts;
  final Map<String, Map<String, int>> sportCategoryCounts;
  final Map<String, Map<String, int>> totalSportCategoryCounts;
  final Map<String, Map<String, int>> playableSportCategoryCounts;
  final Map<String, dynamic> providerCoverage;
  final Map<String, dynamic> providerReliability;
  final String feedSource;
  final bool feedIsRecovery;
  final DateTime receivedAt;
  final DateTime? sourceUpdatedAt;
  final String? validator;
  final String? contentRevision;
  final String? backendVersion;
  final PropPageStatus status;
  final bool isFromCache;

  bool get hasRows => rows.isNotEmpty;

  PropPage copyWith({
    PropPageStatus? status,
    bool? isFromCache,
    List<PropData>? rows,
  }) => PropPage(
    query: query,
    rows: rows ?? this.rows,
    catalogCount: catalogCount,
    totalCount: totalCount,
    facetCount: facetCount,
    categoryCounts: categoryCounts,
    totalCategoryCounts: totalCategoryCounts,
    playableCategoryCounts: playableCategoryCounts,
    sportCounts: sportCounts,
    sportsbookCounts: sportsbookCounts,
    verdictCounts: verdictCounts,
    sportCategoryCounts: sportCategoryCounts,
    totalSportCategoryCounts: totalSportCategoryCounts,
    playableSportCategoryCounts: playableSportCategoryCounts,
    providerCoverage: providerCoverage,
    providerReliability: providerReliability,
    feedSource: feedSource,
    feedIsRecovery: feedIsRecovery,
    receivedAt: receivedAt,
    sourceUpdatedAt: sourceUpdatedAt,
    validator: validator,
    contentRevision: contentRevision,
    backendVersion: backendVersion,
    status: status ?? this.status,
    isFromCache: isFromCache ?? this.isFromCache,
  );

  factory PropPage.empty(PropQuery query) => PropPage(
    query: query,
    rows: const [],
    catalogCount: 0,
    totalCount: 0,
    facetCount: 0,
    categoryCounts: const {},
    totalCategoryCounts: const {},
    playableCategoryCounts: const {},
    sportCounts: const {},
    sportsbookCounts: const {},
    verdictCounts: const {},
    sportCategoryCounts: const {},
    totalSportCategoryCounts: const {},
    playableSportCategoryCounts: const {},
    providerCoverage: const {},
    providerReliability: const {},
    feedSource: '',
    feedIsRecovery: false,
    receivedAt: DateTime.now().toUtc(),
    status: PropPageStatus.idle,
  );
}

Map<String, Map<String, int>> _freezeNestedCounts(
  Map<String, Map<String, int>> source,
) => Map<String, Map<String, int>>.unmodifiable({
  for (final entry in source.entries)
    entry.key: Map<String, int>.unmodifiable(entry.value),
});

Map<String, dynamic> _freezeDynamicMap(Map<String, dynamic> source) =>
    Map<String, dynamic>.unmodifiable({
      for (final entry in source.entries) entry.key: _freeze(entry.value),
    });

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries) '${entry.key}': _freeze(entry.value),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value is Set) return Set<Object?>.unmodifiable(value.map(_freeze));
  return value;
}
