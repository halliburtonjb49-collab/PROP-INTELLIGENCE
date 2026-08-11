import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prop_data.dart';
import '../models/game_market.dart';
import '../models/saved_slip.dart';
import '../models/slip_selection.dart';
import 'supabase_service.dart';

@visibleForTesting
Map<String, dynamic> savedSlipPayload(Map<String, dynamic> response) {
  final nested = response['slip'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  return response;
}

class _ParsedPropsPayload {
  const _ParsedPropsPayload({
    required this.props,
    required this.count,
    required this.facetCount,
    required this.categoryCounts,
    required this.sportCounts,
    required this.sportsbookCounts,
    required this.providerCoverage,
    required this.providerReliability,
    required this.verdictCounts,
    required this.sportCategoryCounts,
    required this.rawMaps,
  });

  final List<PropData> props;
  final int count;
  final int facetCount;
  final Map<String, int> categoryCounts;
  final Map<String, int> sportCounts;

  /// Props available per prop site, counted before the sportsbook
  /// filter is applied. A site absent here has nothing right now and
  /// should not be offered as a filter that returns an empty screen.
  final Map<String, int> sportsbookCounts;
  final Map<String, dynamic> providerCoverage;
  final Map<String, dynamic> providerReliability;
  final Map<String, int> verdictCounts;
  final Map<String, Map<String, int>> sportCategoryCounts;
  final List<Map<String, dynamic>> rawMaps;
}

_ParsedPropsPayload _parsePropsPayload(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('The backend returned invalid data.');
  }
  final rawProps = decoded['props'];
  if (rawProps is! List) {
    throw const FormatException('The backend did not return a props list.');
  }

  final rawMaps = rawProps
      .whereType<Map>()
      .map((raw) => Map<String, dynamic>.from(raw))
      .toList(growable: false);
  final propsById = <String, PropData>{};
  for (final raw in rawMaps) {
    final prop = PropData.fromJson(raw);
    propsById.putIfAbsent(prop.id, () => prop);
  }
  final totalCount = decoded['count'] is num
      ? (decoded['count'] as num).toInt()
      : rawMaps.length;
  final facetCount = (decoded['facetCount'] as num?)?.toInt() ?? totalCount;
  final rawCategoryCounts = decoded['categoryCounts'];
  final categoryCounts = rawCategoryCounts is Map
      ? {
          for (final entry in rawCategoryCounts.entries)
            entry.key.toString().trim().toUpperCase():
                (entry.value as num?)?.toInt() ?? 0,
        }
      : const <String, int>{};
  final rawSportCounts = decoded['sportCounts'];
  final sportCounts = rawSportCounts is Map
      ? {
          for (final entry in rawSportCounts.entries)
            entry.key.toString().trim().toUpperCase():
                (entry.value as num?)?.toInt() ?? 0,
        }
      : const <String, int>{};
  final rawSportsbookCounts = decoded['sportsbookCounts'];
  final sportsbookCounts = rawSportsbookCounts is Map
      ? {
          for (final entry in rawSportsbookCounts.entries)
            entry.key.toString().trim().toUpperCase():
                (entry.value as num?)?.toInt() ?? 0,
        }
      : const <String, int>{};
  final rawProviderCoverage = decoded['providerCoverage'];
  final providerCoverage = rawProviderCoverage is Map
      ? Map<String, dynamic>.from(rawProviderCoverage)
      : const <String, dynamic>{};
  final rawProviderReliability = decoded['providerReliability'];
  final providerReliability = rawProviderReliability is Map
      ? Map<String, dynamic>.from(rawProviderReliability)
      : const <String, dynamic>{};
  final rawVerdictCounts = decoded['verdictCounts'];
  final verdictCounts = rawVerdictCounts is Map
      ? {
          for (final entry in rawVerdictCounts.entries)
            entry.key.toString().trim().toUpperCase():
                (entry.value as num?)?.toInt() ?? 0,
        }
      : const <String, int>{};
  final rawSportCategoryCounts = decoded['sportCategoryCounts'];
  final sportCategoryCounts = rawSportCategoryCounts is Map
      ? {
          for (final sportEntry in rawSportCategoryCounts.entries)
            sportEntry.key
                .toString()
                .trim()
                .toUpperCase(): sportEntry.value is Map
                ? {
                    for (final categoryEntry
                        in (sportEntry.value as Map).entries)
                      categoryEntry.key.toString().trim().toUpperCase():
                          (categoryEntry.value as num?)?.toInt() ?? 0,
                  }
                : <String, int>{},
        }
      : const <String, Map<String, int>>{};

  return _ParsedPropsPayload(
    props: propsById.values.toList(growable: false),
    count: totalCount,
    facetCount: facetCount,
    categoryCounts: categoryCounts,
    sportCounts: sportCounts,
    sportsbookCounts: sportsbookCounts,
    providerCoverage: providerCoverage,
    providerReliability: providerReliability,
    verdictCounts: verdictCounts,
    sportCategoryCounts: sportCategoryCounts,
    rawMaps: rawMaps,
  );
}

class _IntelligenceRequestException implements Exception {
  const _IntelligenceRequestException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackendRefreshStatus {
  final DateTime? lastRefreshAt;
  final String sourceUrl;
  final String message;

  const BackendRefreshStatus({
    required this.lastRefreshAt,
    required this.sourceUrl,
    required this.message,
  });

  const BackendRefreshStatus.empty()
    : lastRefreshAt = null,
      sourceUrl = '',
      message = 'No refresh yet';
}

class ApiService {
  static const String _lastStablePropsCacheKey = 'prop-feed-v5-last-stable';
  static const Duration _propsCacheMaxAge = Duration(minutes: 30);
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'development',
  );
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static String? _resolvedBaseUrl;
  static Future<String?>? _sessionRefresh;
  static final Map<String, Future<http.Response>> _inFlightPropsPages = {};
  static final Map<String, List<PropData>> _lastSuccessfulPropsByQuery =
      <String, List<PropData>>{};
  static int _lastFacetCount = 0;
  static Map<String, int> _lastCategoryCounts = const {};
  static Map<String, int> _lastSportCounts = const {};
  static Map<String, int> _lastVerdictCounts = const {};
  static Map<String, Map<String, int>> _lastSportCategoryCounts = const {};
  static Map<String, dynamic> _lastProviderCoverage = const {};
  static Map<String, dynamic> _lastProviderReliability = const {};
  static final ValueNotifier<BackendRefreshStatus> refreshStatusNotifier =
      ValueNotifier<BackendRefreshStatus>(const BackendRefreshStatus.empty());
  int _lastPropsCount = 0;

  static String get baseUrl => _resolvedBaseUrl ?? _configuredBaseUrl;
  int get lastPropsCount => _lastPropsCount;
  int get lastFacetCount => _lastFacetCount;
  Map<String, int> get lastCategoryCounts =>
      Map.unmodifiable(_lastCategoryCounts);
  Map<String, int> get lastSportCounts => Map.unmodifiable(_lastSportCounts);
  Map<String, int> get lastVerdictCounts =>
      Map.unmodifiable(_lastVerdictCounts);

  static Map<String, int> _lastSportsbookCounts = const {};

  /// Props available per prop site across the whole board.
  Map<String, int> get lastSportsbookCounts =>
      Map.unmodifiable(_lastSportsbookCounts);
  Map<String, Map<String, int>> get lastSportCategoryCounts =>
      Map<String, Map<String, int>>.unmodifiable({
        for (final entry in _lastSportCategoryCounts.entries)
          entry.key: Map<String, int>.unmodifiable(entry.value),
      });
  Map<String, dynamic> get lastProviderCoverage =>
      Map<String, dynamic>.unmodifiable(_lastProviderCoverage);
  Map<String, dynamic> get lastProviderReliability =>
      Map<String, dynamic>.unmodifiable(_lastProviderReliability);

  Future<Map<String, String>> _authenticatedHeaders({
    bool json = false,
    bool forceRefresh = false,
  }) async {
    final client = SupabaseService.client;
    var session = client?.auth.currentSession;
    // Immediately after login the dashboard can build one frame before the
    // Supabase client publishes its restored session. Give that handoff a
    // short window instead of failing the first prop request as signed out.
    if (client != null && session == null) {
      for (var attempt = 0; attempt < 12 && session == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        session = client.auth.currentSession;
      }
    }
    var token = session?.accessToken;
    if (client != null &&
        session != null &&
        (forceRefresh || session.isExpired)) {
      final refresh = _sessionRefresh ??= client.auth.refreshSession().then(
        (response) => response.session?.accessToken,
      );
      try {
        token = await refresh;
      } finally {
        if (identical(_sessionRefresh, refresh)) {
          _sessionRefresh = null;
        }
      }
    }
    if (token == null || token.isEmpty) {
      throw StateError('Sign in before accessing private ticket data.');
    }
    return {
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> postIntelligence(
    String path,
    Object payload,
  ) async {
    Object? lastError;
    for (final candidate in _candidateBaseUrls) {
      try {
        var response = await http
            .post(
              Uri.parse('$candidate/api/intelligence/$path'),
              headers: await _authenticatedHeaders(json: true),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 401) {
          response = await http
              .post(
                Uri.parse('$candidate/api/intelligence/$path'),
                headers: await _authenticatedHeaders(
                  json: true,
                  forceRefresh: true,
                ),
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 12));
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _resolvedBaseUrl = candidate;
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        lastError = 'Intelligence API ${response.statusCode}: ${response.body}';
        if (response.statusCode >= 400 && response.statusCode < 500) {
          throw _IntelligenceRequestException(lastError.toString());
        }
      } catch (error) {
        if (error is _IntelligenceRequestException) rethrow;
        lastError = error;
        if (error is FormatException) rethrow;
      }
    }
    throw Exception(lastError ?? 'Intelligence API unavailable');
  }

  Future<Map<String, dynamic>> fetchIntelligence(String path) async {
    Object? lastError;
    for (final candidate in _candidateBaseUrls) {
      try {
        var response = await http
            .get(
              Uri.parse('$candidate/api/intelligence/$path'),
              headers: await _authenticatedHeaders(),
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 401) {
          response = await http
              .get(
                Uri.parse('$candidate/api/intelligence/$path'),
                headers: await _authenticatedHeaders(forceRefresh: true),
              )
              .timeout(const Duration(seconds: 12));
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _resolvedBaseUrl = candidate;
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid intelligence response.');
          }
          return decoded;
        }
        lastError = 'Intelligence API ${response.statusCode}: ${response.body}';
        if (response.statusCode >= 400 && response.statusCode < 500) {
          throw _IntelligenceRequestException(lastError.toString());
        }
      } catch (error) {
        if (error is _IntelligenceRequestException) rethrow;
        lastError = error;
        if (error is FormatException) rethrow;
      }
    }
    throw Exception(lastError ?? 'Intelligence API unavailable');
  }

  /// The model's published record.
  ///
  /// Was briefly unauthenticated so the evidence would reach people deciding
  /// whether to buy. It went back behind the gate the same day: the first
  /// numbers it published reported a beat-the-closing-line rate of 6.7%,
  /// which is not a weak result but a broken measurement, and a record we
  /// cannot stand behind is wrong to publish in either direction.
  Future<Map<String, dynamic>> fetchTrackRecord() async {
    Object? lastError;
    final headers = await _authenticatedHeaders(json: false);
    for (final candidate in _candidateBaseUrls) {
      try {
        final response = await http
            .get(
              Uri.parse('$candidate/api/performance/track-record'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _resolvedBaseUrl = candidate;
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid track record response.');
          }
          return decoded;
        }
        lastError = 'Track record ${response.statusCode}';
      } catch (error) {
        if (error is FormatException) rethrow;
        lastError = error;
      }
    }
    throw Exception(lastError ?? 'Track record unavailable');
  }

  /// Today's board reduced to a briefing.
  ///
  /// Returns an unloaded briefing rather than throwing when it cannot be
  /// reached, because the page must be able to tell "nothing clears the bar"
  /// apart from "we could not ask" -- those read the same and mean opposite
  /// things.
  Future<Map<String, dynamic>> fetchTodaysBriefing() async {
    Object? lastError;
    final headers = await _authenticatedHeaders(json: false);
    for (final candidate in _candidateBaseUrls) {
      try {
        final response = await http
            .get(Uri.parse('$candidate/api/briefing/today'), headers: headers)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _resolvedBaseUrl = candidate;
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid briefing response.');
          }
          return decoded;
        }
        lastError = 'Briefing ${response.statusCode}';
      } catch (error) {
        if (error is FormatException) rethrow;
        lastError = error;
      }
    }
    throw Exception(lastError ?? 'Briefing unavailable');
  }

  Future<GameMarketFeed> fetchGameMarkets({
    required String sport,
    bool refresh = false,
  }) async {
    Object? lastError;
    for (final candidate in _candidateBaseUrls) {
      try {
        final uri = Uri.parse('$candidate/api/game-markets').replace(
          queryParameters: {'sport': sport, if (refresh) 'refresh': 'true'},
        );
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          lastError = Exception(
            'Unable to load game markets: ${response.statusCode}',
          );
          continue;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid game-market response.');
        }
        _resolvedBaseUrl = candidate;
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          'game-market-feed-v1-${sport.trim().toUpperCase()}',
          jsonEncode(decoded),
        );
        return GameMarketFeed.fromJson(decoded);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception(lastError ?? 'Game markets are temporarily unavailable.');
  }

  Future<GameMarketFeed?> loadCachedGameMarkets(String sport) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(
      'game-market-feed-v1-${sport.trim().toUpperCase()}',
    );
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      return GameMarketFeed.fromJson({...decoded, 'cached': true});
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchAdminOperations() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/intelligence/operations'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load pipeline operations: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchProductionAcceptance() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/operations/acceptance'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load production health: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// The rows behind one control-panel tile.
  ///
  /// Detail is an enrichment: a failure here returns an empty result so the
  /// tile that opened it keeps working rather than the panel breaking.
  Future<Map<String, dynamic>> fetchOperationsDetail(
    String metric, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/api/operations/control-panel/detail/$metric?limit=$limit',
      ),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      return {
        'metric': metric,
        'supported': true,
        'reason': 'http_${response.statusCode}',
        'rows': const [],
      };
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchLaunchControlPanel() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/operations/control-panel'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load launch control panel: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchProviderAvailability() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/operations/provider-availability'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load provider availability: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchProviderRecovery() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/operations/provider-recovery'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load provider recovery: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestProviderRecovery({
    String targetSport = 'ALL',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/operations/provider-recovery'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({'targetSport': targetSport}),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to start provider recovery: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchOwnerCommandCenter({
    String window = 'today',
    DateTime? start,
    DateTime? end,
  }) async {
    final query = <String, String>{'window': window};
    if (start != null) query['start'] = start.toUtc().toIso8601String();
    if (end != null) query['end'] = end.toUtc().toIso8601String();
    final uri = Uri.parse(
      '$baseUrl/api/operations/command-center',
    ).replace(queryParameters: query);
    final response = await http.get(
      uri,
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load owner command center: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateOwnerPropControl({
    required Map item,
    required bool quarantined,
    required String reason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/operations/command-center/prop-control'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({
        'targetKey': '${item['id']}',
        'quarantined': quarantined,
        'reason': reason,
        'snapshot': {
          'sport': item['sport'],
          'gameId': item['gameId'],
          'player': item['player'],
          'market': item['market'],
          'provider': item['provider'],
          'line': item['line'],
          'matchup': item['matchup'],
        },
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to update prop control: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateOwnerAlertAcknowledgement({
    required Map alert,
    required bool acknowledged,
    required String reason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/operations/command-center/alert-acknowledgement'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({
        'alertKey': '${alert['id']}',
        'count': alert['count'] ?? 0,
        'acknowledged': acknowledged,
        'reason': reason,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Unable to update alert acknowledgement: ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchOwnerModelAudit({
    String window = '30d',
    DateTime? start,
    DateTime? end,
    int limit = 500,
  }) async {
    final query = <String, String>{'window': window, 'limit': '$limit'};
    if (start != null) query['start'] = start.toUtc().toIso8601String();
    if (end != null) query['end'] = end.toUtc().toIso8601String();
    final uri = Uri.parse(
      '$baseUrl/api/operations/model-audit',
    ).replace(queryParameters: query);
    final response = await http.get(
      uri,
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load owner model audit: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchOwnerGradingReview() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/operations/grading-review'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load owner grading review: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchStrikeoutControls() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/operations/strikeout-controls'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load strikeout controls: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateStrikeoutControls(
    Map<String, dynamic> controls,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/operations/strikeout-controls'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({'controls': controls}),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to update strikeout controls: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitUserFeedback({
    required String category,
    required String message,
    String page = '',
    Map<String, dynamic>? metadata,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/operations/feedback'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({
        'category': category,
        'message': message,
        'page': page,
        'metadata': metadata ?? const {},
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to submit feedback: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchOwnerFeedback({
    int limit = 50,
    String status = '',
  }) async {
    final uri = Uri.parse('$baseUrl/api/operations/feedback').replace(
      queryParameters: {
        'limit': '$limit',
        if (status.trim().isNotEmpty) 'status': status.trim(),
      },
    );
    final response = await http.get(
      uri,
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load owner feedback: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchAlertDeliveries() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/intelligence/alerts/deliveries'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load alert deliveries: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['deliveries'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> saveCompoundAlert(
    Map<String, dynamic> rule,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/intelligence/alerts'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode(rule),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to save alert: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchCompoundAlerts() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/intelligence/alerts'),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load alerts: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['alerts'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> evaluateSavedAlerts(
    Map<String, dynamic> snapshot,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/intelligence/alerts/evaluate-snapshot'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({'snapshot': snapshot}),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to evaluate alerts: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> recordEngagement(List<Map<String, String>> events) async {
    if (events.isEmpty) return;
    final response = await http.post(
      Uri.parse('$baseUrl/api/intelligence/engagement'),
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({'events': events}),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to record engagement: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchPropSentiment(String propId) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/api/intelligence/sentiment/${Uri.encodeComponent(propId)}',
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load sentiment: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static List<String> get _candidateBaseUrls {
    final configured = _normalizeBaseUrl(_configuredBaseUrl);
    final candidates = <String>{
      if (kIsWeb) 'https://api.propsintell.com',
      configured,
    };
    return candidates
        .map(_normalizeBaseUrl)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  List<Map<String, dynamic>> _buildSlipLegs(List<SlipSelection> selections) {
    return selections.map((selection) {
      final prop = selection.prop;
      return {
        'prop_id': prop.id,
        'event_id': prop.eventId,
        'api_sports_game_id': prop.apiSportsGameId,
        'player_id': prop.playerId,
        'custom_label': prop.customLabel,
        'manual_note': prop.manualNote,
        'game_start_time': prop.startTimeUtc.isNotEmpty
            ? prop.startTimeUtc
            : prop.gameStartTime,
        'player': prop.player,
        'image_path': prop.imagePath,
        'sport': prop.sport,
        'matchup': prop.matchup,
        'sportsbook': prop.sportsbook,
        'market': prop.market,
        'line': prop.line,
        'side': selection.sideLabel,
        'odds': selection.odds,
        'projection': prop.projection,
        'hit_probability': prop.winProbability == null
            ? prop.fairProbability
            : prop.winProbability! > 1
            ? prop.winProbability! / 100
            : prop.winProbability,
        'confidence': prop.displayConfidenceRating,
        'recommendation_edge': prop.recommendationEdge,
        'projection_source': prop.projectionSource,
        'projection_model_version': prop.projectionModelVersion,
        'projection_sample_size': prop.projectionSampleSize,
        'projection_volatility': prop.projectionVolatility,
        'projection_calibrated': prop.projectionCalibrated,
        'historical_hit_rate': prop.historicalHitRate,
        'pi_trust_score': prop.piTrustScore,
        'pi_trust_band': prop.piTrustBand,
        'pi_trust_warnings': prop.piTrustWarnings,
        'data_quality_score': prop.dataQualityScore,
        'data_stale': prop.dataStale,
        'injury_status': prop.injuryStatus,
        'lineup_status': prop.lineupStatus,
        'calculation_inputs': {
          'opening_line': prop.openingLine,
          'current_line': prop.currentLine,
          'line_moved_at_utc': prop.lineMovedAtUtc,
          'source_player_id': prop.sourcePlayerId,
          'canonical_player_id': prop.canonicalPlayerId,
          'identity_confidence': prop.playerIdentityConfidence,
          'sourceProvider': prop.sourceProvider,
          'category': prop.category,
          'over_odds': prop.overOdds,
          'under_odds': prop.underOdds,
          'tier': prop.tier,
          'pick_text': prop.pickText,
          'recommendation_explanation': prop.recommendationExplanation,
          'data_quality_score': prop.dataQualityScore,
          'data_quality_reasons': prop.dataQualityReasons,
          'workload_multiplier': prop.fatigueMultiplier,
          'rest_days': prop.restDays,
          'pace_multiplier': prop.paceMultiplier,
          'opponent_defense_multiplier': prop.opponentDefenseMultiplier,
          'usage_multiplier': prop.usageMultiplier,
          'home_away_multiplier': prop.homeAwayMultiplier,
          'opponent_multiplier': prop.matchupMultiplier,
          'matchup_context': prop.matchupContext,
          'officiating_adjustment': prop.officiatingAdjustment,
          'model_probability': prop.modelProbability,
          'market_probability': prop.marketProbability,
          'push_probability': prop.pushProbability,
          'loss_probability': prop.lossProbability,
          'fair_decimal_odds': prop.fairDecimalOdds,
          'probability_method': prop.probabilityMethod,
          'market_blend_weight': prop.probabilityMarketWeight,
          'probability_uncertainty': prop.probabilityUncertainty,
          'calibration_adjustment': prop.probabilityCalibrationAdjustment,
          'calibration_sample_size': prop.probabilityCalibrationSampleSize,
          'expected_value_percentage': prop.evPercentage,
        },
      };
    }).toList();
  }

  List<PropData> _dedupePropsById(List<PropData> props) {
    final deduped = <String, PropData>{};
    var generatedKeyIndex = 0;

    for (final prop in props) {
      final key = prop.id.trim().isNotEmpty
          ? prop.id.trim()
          : '__generated-${generatedKeyIndex++}';
      final existing = deduped[key];
      if (existing == null || prop.edge > existing.edge) {
        deduped[key] = prop;
      }
    }

    return deduped.values.toList(growable: false);
  }

  Future<http.Response> _getPropsPage(Uri uri) async {
    final requestKey = uri.toString();
    final request = _inFlightPropsPages[requestKey] ??= _downloadPropsPage(uri);
    try {
      return await request;
    } finally {
      if (identical(_inFlightPropsPages[requestKey], request)) {
        _inFlightPropsPages.remove(requestKey);
      }
    }
  }

  Future<http.Response> _downloadPropsPage(Uri uri) async {
    Object? lastError;
    final sport = (uri.queryParameters['sport'] ?? '').trim().toUpperCase();
    final category = (uri.queryParameters['category'] ?? '')
        .trim()
        .toUpperCase();
    final isSpecialtySport = const {
      'PGA',
      'TENNIS',
      'UFC',
      'SOCCER',
    }.contains(sport);
    // Specialty feeds can legitimately be empty between events. Avoid making
    // navigation wait through two full network attempts before the board can
    // render its available/empty state.
    // The board owns background recovery and already keeps its last stable
    // page visible. A long second HTTP attempt here only traps first-time
    // mobile visitors behind skeleton cards for up to 25 seconds.
    const maxAttempts = 1;
    final requestTimeout = isSpecialtySport
        ? const Duration(seconds: 4)
        : category.isNotEmpty && category != 'ALL'
        ? const Duration(seconds: 12)
        : const Duration(seconds: 6);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        var response = await http
            .get(uri, headers: await _authenticatedHeaders())
            .timeout(requestTimeout);
        if (response.statusCode == 401) {
          response = await http
              .get(
                uri,
                headers: await _authenticatedHeaders(forceRefresh: true),
              )
              .timeout(requestTimeout);
        }
        if (response.statusCode == 200) return response;
        lastError = Exception('Unable to load props: ${response.statusCode}');
        if (response.statusCode < 500 && response.statusCode != 429) break;
      } catch (error) {
        lastError = error;
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    throw Exception(lastError ?? 'Unable to download the props page.');
  }

  Future<bool> wakeBackend() async {
    for (final candidate in _candidateBaseUrls) {
      final uris = <Uri>[
        Uri.parse('$candidate/api/props/NBA'),
        Uri.parse('$candidate/api/props'),
      ];

      for (final uri in uris) {
        try {
          final response = await http
              .get(uri, headers: await _authenticatedHeaders())
              .timeout(const Duration(seconds: 4));
          if (response.statusCode == 200) {
            _resolvedBaseUrl = candidate;
            refreshStatusNotifier.value = BackendRefreshStatus(
              lastRefreshAt: DateTime.now(),
              sourceUrl: candidate,
              message: 'Backend wake check successful',
            );
            return true;
          }
        } catch (_) {
          // Keep trying other candidate endpoints.
        }
      }
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> fetchRawPropsFeed({
    String sport = 'NBA',
  }) async {
    Object? lastError;

    for (final candidate in _candidateBaseUrls) {
      final uris = <Uri>[
        Uri.parse('$candidate/api/props/$sport'),
        Uri.parse('$candidate/api/props'),
      ];

      for (final uri in uris) {
        try {
          final response = await http
              .get(uri, headers: await _authenticatedHeaders())
              .timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) {
            lastError = Exception(
              'Unable to load props: ${response.statusCode}',
            );
            continue;
          }

          final decoded = jsonDecode(response.body);
          List<dynamic>? rawList;
          if (decoded is List) {
            rawList = decoded;
          } else if (decoded is Map<String, dynamic> &&
              decoded['props'] is List) {
            rawList = decoded['props'] as List<dynamic>;
          }

          if (rawList == null) {
            lastError = const FormatException(
              'The backend did not return a props list.',
            );
            continue;
          }

          _resolvedBaseUrl = candidate;
          refreshStatusNotifier.value = BackendRefreshStatus(
            lastRefreshAt: DateTime.now(),
            sourceUrl: candidate,
            message: 'Props refreshed',
          );
          return rawList
              .whereType<Map>()
              .map((raw) => Map<String, dynamic>.from(raw))
              .toList(growable: false);
        } catch (error) {
          lastError = error;
        }
      }
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw Exception('Unable to load raw props from local backend candidates.');
  }

  Future<bool> checkBackendHealth() async {
    for (final candidate in _candidateBaseUrls) {
      try {
        final healthResponse = await http
            .get(Uri.parse('$candidate/health'))
            .timeout(const Duration(seconds: 4));
        if (healthResponse.statusCode != 200) {
          continue;
        }
        final healthDecoded = jsonDecode(healthResponse.body);
        final isHealthy =
            healthDecoded is Map<String, dynamic> &&
            healthDecoded['status']?.toString().toLowerCase() == 'ok';
        if (!isHealthy) {
          continue;
        }

        final propsResponse = await http
            .get(Uri.parse('$candidate/api/props'))
            .timeout(const Duration(seconds: 8));
        if (propsResponse.statusCode != 200) {
          continue;
        }
        final propsDecoded = jsonDecode(propsResponse.body);
        if (propsDecoded is! Map<String, dynamic>) {
          continue;
        }
        if (propsDecoded['props'] is! List) {
          continue;
        }

        _resolvedBaseUrl = candidate;
        return true;
      } catch (_) {
        // Try the next candidate backend URL.
      }
    }
    return false;
  }

  Future<List<PropData>> fetchProps({
    String selectedSide = 'All',
    String selectedTier = 'All',
    String selectedSportsbook = 'All',
    String selectedSport = 'All',
    String selectedCategory = 'All',
    String search = '',
    int minConfidence = 0,
    String sortBy = 'confidence',
    String verdictFilter = 'All',
    int limit = 75,
    int offset = 0,
  }) async {
    Object? lastError;
    final sportsbookVariants = _sportsbookQueryVariants(selectedSportsbook);
    final targetSportsbookKey = _normalizeSportsbookKey(selectedSportsbook);
    final sportsbookFilterEnabled = targetSportsbookKey != 'ALL';
    final scopedLimit = limit.clamp(1, 500);
    final requestLimit = sportsbookFilterEnabled
        ? math.max(scopedLimit, 350)
        : scopedLimit;
    final requestOffset = sportsbookFilterEnabled ? 0 : offset;
    final cacheKey = _propsCacheKey(
      selectedSide,
      selectedTier,
      selectedSportsbook,
      selectedSport,
      selectedCategory,
      search,
      minConfidence,
      verdictFilter,
      sortBy,
    );

    for (final candidate in _candidateBaseUrls) {
      try {
        _ParsedPropsPayload? parsed;
        for (final sportsbook in sportsbookVariants) {
          final uri = Uri.parse('$candidate/api/props').replace(
            queryParameters: {
              'side': selectedSide,
              'tier': selectedTier,
              'sportsbook': sportsbook,
              'sport': selectedSport,
              'category': selectedCategory,
              'search': search,
              'minConfidence': minConfidence.toString(),
              'sortBy': sortBy,
              'verdict': verdictFilter,
              'includeReliability':
                  (offset == 0 &&
                          selectedCategory.trim().toUpperCase() == 'ALL')
                      .toString(),
              'limit': requestLimit.toString(),
              'offset': requestOffset.toString(),
            },
          );
          final response = await _getPropsPage(uri);
          // Parsing and model construction can be expensive on large feeds.
          final candidateParsed = await compute(
            _parsePropsPayload,
            response.body,
          );
          parsed = candidateParsed;
          if (candidateParsed.props.isNotEmpty) {
            break;
          }
        }
        if (parsed == null) {
          continue;
        }
        var props = parsed.props;
        var totalCount = parsed.count;
        var facetCount = parsed.facetCount;
        var categoryCounts = parsed.categoryCounts;
        var sportCounts = parsed.sportCounts;
        var verdictCounts = parsed.verdictCounts;
        var sportCategoryCounts = parsed.sportCategoryCounts;
        var providerCoverage = parsed.providerCoverage;
        final providerReliability = parsed.providerReliability;

        if (sportsbookFilterEnabled) {
          props = props
              .where(
                (prop) => _matchesSelectedSportsbook(prop, targetSportsbookKey),
              )
              .toList(growable: false);
        }

        if (sportsbookFilterEnabled && props.isEmpty) {
          final fallbackUri = Uri.parse('$candidate/api/props').replace(
            queryParameters: {
              'side': selectedSide,
              'tier': selectedTier,
              'sportsbook': 'All',
              'sport': selectedSport,
              'category': selectedCategory,
              'search': search,
              'minConfidence': minConfidence.toString(),
              'sortBy': sortBy,
              'verdict': verdictFilter,
              'includeReliability':
                  (offset == 0 &&
                          selectedCategory.trim().toUpperCase() == 'ALL')
                      .toString(),
              'limit': requestLimit.toString(),
              'offset': requestOffset.toString(),
            },
          );
          final fallbackResponse = await _getPropsPage(fallbackUri);
          final fallbackParsed = await compute(
            _parsePropsPayload,
            fallbackResponse.body,
          );
          final fallbackProps = fallbackParsed.props
              .where(
                (prop) => _matchesSelectedSportsbook(prop, targetSportsbookKey),
              )
              .toList(growable: false);
          if (fallbackProps.isNotEmpty) {
            props = fallbackProps;
            totalCount = fallbackProps.length;
            facetCount = fallbackProps.length;
            categoryCounts = _categoryCountsFromProps(fallbackProps);
            sportCounts = _sportCountsFromProps(fallbackProps);
            verdictCounts = _verdictCountsFromProps(fallbackProps);
            sportCategoryCounts = _sportCategoryCountsFromProps(fallbackProps);
            providerCoverage = const <String, dynamic>{};
          }
        }

        _lastFacetCount = facetCount;
        _lastCategoryCounts = categoryCounts;
        _lastVerdictCounts = verdictCounts;
        if (providerCoverage.isNotEmpty) {
          _lastProviderCoverage = providerCoverage;
        }
        if (providerReliability.isNotEmpty) {
          _lastProviderReliability = providerReliability;
        }
        if (selectedSport.trim().toUpperCase() == 'ALL' &&
            selectedCategory.trim().toUpperCase() == 'ALL') {
          _lastSportCounts = sportCounts;
          _lastSportsbookCounts = parsed.sportsbookCounts;
          _lastSportCategoryCounts = sportCategoryCounts;
        }
        _resolvedBaseUrl = candidate;
        _lastPropsCount = totalCount > 0 ? totalCount : props.length;
        if (props.isNotEmpty) {
          _lastSuccessfulPropsByQuery[cacheKey] = List<PropData>.unmodifiable(
            props,
          );
        }
        if (offset == 0 && props.isNotEmpty) {
          final isBroadQuery = _isBroadPropsQuery(
            selectedSide: selectedSide,
            selectedTier: selectedTier,
            selectedSportsbook: selectedSportsbook,
            selectedSport: selectedSport,
            selectedCategory: selectedCategory,
            search: search,
            verdictFilter: verdictFilter,
            minConfidence: minConfidence,
          );
          // Rendering must never wait on browser/local device storage. Broad
          // queries use the stable key directly, avoiding two identical JSON
          // encodes and writes on slower phones.
          unawaited(
            _savePropsCache(
              isBroadQuery
                  ? _lastStablePropsCacheKey
                  : _propsCacheKey(
                      selectedSide,
                      selectedTier,
                      selectedSportsbook,
                      selectedSport,
                      selectedCategory,
                      search,
                      minConfidence,
                      verdictFilter,
                      sortBy,
                    ),
              parsed.rawMaps,
              _lastPropsCount,
              _lastFacetCount,
              _lastCategoryCounts,
              sportCounts,
              verdictCounts,
              sportCategoryCounts,
            ).catchError((_) {
              // A storage quota or private-browsing restriction must not turn
              // a successful live response into a failed board load.
            }),
          );
        }
        refreshStatusNotifier.value = BackendRefreshStatus(
          lastRefreshAt: DateTime.now(),
          sourceUrl: candidate,
          message:
              'Downloaded ${props.length} props reliably • build $appVersion',
        );
        return props;
      } catch (error) {
        lastError = error;
      }
    }

    final lastSuccessfulProps = _lastSuccessfulPropsByQuery[cacheKey];
    if (lastSuccessfulProps != null && lastSuccessfulProps.isNotEmpty) {
      refreshStatusNotifier.value = BackendRefreshStatus(
        lastRefreshAt: refreshStatusNotifier.value.lastRefreshAt,
        sourceUrl: refreshStatusNotifier.value.sourceUrl,
        message: 'Showing the last stable prop download while reconnecting',
      );
      _lastPropsCount = lastSuccessfulProps.length;
      return lastSuccessfulProps;
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw Exception(
      'Unable to reach the live props service. Check your connection and retry.',
    );
  }

  List<String> _sportsbookQueryVariants(String selectedSportsbook) {
    final trimmed = selectedSportsbook.trim();
    final normalized = trimmed
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized == 'BETR' || normalized == 'BETRPICKS') {
      return _dedupeSportsbookVariants([
        selectedSportsbook,
        'BETR',
        'BETR PICKS',
        'BETRPICKS',
      ]);
    }
    if (normalized == 'PICK6' ||
        normalized == 'PICK 6' ||
        normalized == 'DRAFTKINGSPICK6') {
      return _dedupeSportsbookVariants([
        selectedSportsbook,
        'PICK6',
        'PICK 6',
        'DRAFTKINGS PICK6',
        'DK PICK6',
      ]);
    }
    return [selectedSportsbook];
  }

  List<String> _dedupeSportsbookVariants(List<String> values) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final value in values) {
      final key = value
          .trim()
          .toUpperCase()
          .replaceAll(' ', '')
          .replaceAll('_', '')
          .replaceAll('-', '');
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      ordered.add(value);
    }
    return ordered;
  }

  String _normalizeSportsbookKey(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized == 'ALL') {
      return 'ALL';
    }
    if (normalized.contains('PICK6') || normalized.contains('PICK 6')) {
      return 'PICK6';
    }
    if (normalized.contains('PRIZEPICKS')) {
      return 'PRIZEPICKS';
    }
    if (normalized.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    if (normalized.contains('DRAFTPICKS')) {
      return 'DRAFTPICKS';
    }
    if (normalized.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (normalized.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    if (normalized.contains('BETR')) {
      return 'BETR';
    }
    return normalized;
  }

  bool _matchesSelectedSportsbook(PropData prop, String targetSportsbookKey) {
    if (targetSportsbookKey.isEmpty || targetSportsbookKey == 'ALL') {
      return true;
    }
    final propSiteKey = _normalizeSportsbookKey(
      '${prop.sportsbook} ${prop.sourceProvider}',
    );
    return propSiteKey == targetSportsbookKey;
  }

  Map<String, int> _categoryCountsFromProps(List<PropData> props) {
    final counts = <String, int>{};
    for (final prop in props) {
      final category = prop.category.trim().isEmpty ? 'OTHER' : prop.category;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _sportCountsFromProps(List<PropData> props) {
    final counts = <String, int>{};
    for (final prop in props) {
      final sport = prop.sport.trim().isEmpty ? 'ALL' : prop.sport;
      counts[sport] = (counts[sport] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> _verdictCountsFromProps(List<PropData> props) {
    final counts = <String, int>{'ALL': props.length, 'ACTIONABLE': 0};
    for (final prop in props) {
      final decision = prop.verdict.decision.trim().toUpperCase();
      if (decision.isNotEmpty) {
        counts[decision] = (counts[decision] ?? 0) + 1;
      }
      if (prop.verdict.actionable) {
        counts['ACTIONABLE'] = (counts['ACTIONABLE'] ?? 0) + 1;
      }
    }
    return counts;
  }

  Map<String, Map<String, int>> _sportCategoryCountsFromProps(
    List<PropData> props,
  ) {
    final counts = <String, Map<String, int>>{};
    for (final prop in props) {
      final sport = prop.sport.trim().isEmpty ? 'ALL' : prop.sport;
      final category = prop.category.trim().isEmpty ? 'OTHER' : prop.category;
      final byCategory = counts.putIfAbsent(sport, () => <String, int>{});
      byCategory[category] = (byCategory[category] ?? 0) + 1;
    }
    return counts;
  }

  /// Loads the complete actionable set of props whose current site line has
  /// moved from its recorded opening line. This bypasses the normal board
  /// cache so Line Movement never displays a stale first-page snapshot.
  Future<List<PropData>> fetchLineMovementProps({String sport = 'All'}) async {
    Object? lastError;
    for (final candidate in _candidateBaseUrls) {
      try {
        const pageSize = 500;
        final propsById = <String, PropData>{};
        var offset = 0;
        while (true) {
          final uri = Uri.parse('$candidate/api/props').replace(
            queryParameters: {
              'sport': sport,
              'onlyMoved': 'true',
              'includeReliability': 'false',
              'sortBy': 'time',
              'limit': '$pageSize',
              'offset': '$offset',
            },
          );
          final response = await _getPropsPage(uri);
          final parsed = await compute(_parsePropsPayload, response.body);
          for (final prop in parsed.props) {
            propsById[prop.id] = prop;
          }
          offset += parsed.props.length;
          if (parsed.props.isEmpty || offset >= parsed.count) break;
        }
        _resolvedBaseUrl = candidate;
        return propsById.values.toList(growable: false);
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError is Exception) throw lastError;
    throw Exception('Unable to load current line movement.');
  }

  String _propsCacheKey(
    String side,
    String tier,
    String sportsbook,
    String sport,
    String category,
    String search,
    int confidence,
    String verdict,
    String sort,
  ) {
    final raw =
        [
              side,
              tier,
              sportsbook,
              sport,
              category,
              search,
              '$confidence',
              verdict,
              sort,
            ]
            .map(
              (value) => value.trim().toLowerCase().replaceAll(
                RegExp(r'[^a-z0-9]+'),
                '-',
              ),
            )
            .join('_');
    return 'prop-feed-v5-$raw';
  }

  bool _isBroadPropsQuery({
    required String selectedSide,
    required String selectedTier,
    required String selectedSportsbook,
    required String selectedSport,
    required String selectedCategory,
    required String search,
    required String verdictFilter,
    required int minConfidence,
  }) {
    bool isAll(String value) => value.trim().toUpperCase() == 'ALL';
    return isAll(selectedSide) &&
        isAll(selectedTier) &&
        isAll(selectedSportsbook) &&
        isAll(selectedSport) &&
        isAll(selectedCategory) &&
        isAll(verdictFilter) &&
        search.trim().isEmpty &&
        minConfidence <= 0;
  }

  Future<void> _savePropsCache(
    String key,
    List<Map<String, dynamic>> rawProps,
    int total,
    int facetTotal,
    Map<String, int> categoryCounts,
    Map<String, int> sportCounts,
    Map<String, int> verdictCounts,
    Map<String, Map<String, int>> sportCategoryCounts,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      key,
      jsonEncode({
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'total': total,
        'facetTotal': facetTotal,
        'categoryCounts': categoryCounts,
        'sportCounts': sportCounts,
        'verdictCounts': verdictCounts,
        'sportCategoryCounts': sportCategoryCounts,
        'props': rawProps,
      }),
    );
  }

  Future<List<PropData>> loadCachedProps({
    String selectedSide = 'All',
    String selectedTier = 'All',
    String selectedSportsbook = 'All',
    String selectedSport = 'All',
    String selectedCategory = 'All',
    String search = '',
    int minConfidence = 0,
    String sortBy = 'confidence',
    String verdictFilter = 'All',
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _propsCacheKey(
      selectedSide,
      selectedTier,
      selectedSportsbook,
      selectedSport,
      selectedCategory,
      search,
      minConfidence,
      verdictFilter,
      sortBy,
    );
    final broadQuery = _isBroadPropsQuery(
      selectedSide: selectedSide,
      selectedTier: selectedTier,
      selectedSportsbook: selectedSportsbook,
      selectedSport: selectedSport,
      selectedCategory: selectedCategory,
      search: search,
      verdictFilter: verdictFilter,
      minConfidence: minConfidence,
    );
    final candidates = <String?>[
      preferences.getString(key),
      if (broadQuery && key != _lastStablePropsCacheKey)
        preferences.getString(_lastStablePropsCacheKey),
    ];
    for (final encoded in candidates) {
      if (encoded == null || encoded.isEmpty) continue;
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic> || decoded['props'] is! List) {
          continue;
        }
        final savedAt = DateTime.tryParse(decoded['savedAt']?.toString() ?? '');
        if (savedAt == null) {
          continue;
        }
        final cacheIsStale =
            DateTime.now().toUtc().difference(savedAt.toUtc()) >
            _propsCacheMaxAge;
        final cached = (decoded['props'] as List)
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .map(PropData.fromJson)
            .toList(growable: false);
        if (cached.isEmpty) continue;
        _lastPropsCount = (decoded['total'] as num?)?.toInt() ?? cached.length;
        _lastFacetCount =
            (decoded['facetTotal'] as num?)?.toInt() ?? _lastPropsCount;
        final rawCategoryCounts = decoded['categoryCounts'];
        _lastCategoryCounts = rawCategoryCounts is Map
            ? {
                for (final entry in rawCategoryCounts.entries)
                  entry.key.toString().trim().toUpperCase():
                      (entry.value as num?)?.toInt() ?? 0,
              }
            : const {};
        final rawSportCounts = decoded['sportCounts'];
        _lastSportCounts = rawSportCounts is Map
            ? {
                for (final entry in rawSportCounts.entries)
                  entry.key.toString().trim().toUpperCase():
                      (entry.value as num?)?.toInt() ?? 0,
              }
            : const {};
        _lastProviderCoverage = const {};
        _lastProviderReliability = const {};
        final rawVerdictCounts = decoded['verdictCounts'];
        _lastVerdictCounts = rawVerdictCounts is Map
            ? {
                for (final entry in rawVerdictCounts.entries)
                  entry.key.toString().trim().toUpperCase():
                      (entry.value as num?)?.toInt() ?? 0,
              }
            : const {};
        final rawSportCategoryCounts = decoded['sportCategoryCounts'];
        _lastSportCategoryCounts = rawSportCategoryCounts is Map
            ? {
                for (final sportEntry in rawSportCategoryCounts.entries)
                  sportEntry.key
                      .toString()
                      .trim()
                      .toUpperCase(): sportEntry.value is Map
                      ? {
                          for (final categoryEntry
                              in (sportEntry.value as Map).entries)
                            categoryEntry.key.toString().trim().toUpperCase():
                                (categoryEntry.value as num?)?.toInt() ?? 0,
                        }
                      : <String, int>{},
              }
            : const {};
        refreshStatusNotifier.value = BackendRefreshStatus(
          lastRefreshAt: DateTime.tryParse(
            decoded['savedAt']?.toString() ?? '',
          ),
          sourceUrl: 'device cache',
          message: cacheIsStale
              ? 'Showing the last saved board while refreshing live props'
              : 'Showing saved props while refreshing',
        );
        return cached;
      } catch (_) {
        // Try the last stable broad-feed snapshot next.
      }
    }
    return const [];
  }

  Future<List<PropData>> fetchPositiveEvProps({
    double minEv = 0.0,
    String? sport,
  }) async {
    Object? lastError;

    final minEvText = minEv.toStringAsFixed(2);
    for (final candidate in _candidateBaseUrls) {
      final query = <String, String>{'min_ev': minEvText};
      final normalizedSport = sport?.trim() ?? '';
      if (normalizedSport.isNotEmpty &&
          normalizedSport.toUpperCase() != 'ALL') {
        query['sport'] = normalizedSport;
      }

      final uri = Uri.parse(
        '$candidate/api/props/ev',
      ).replace(queryParameters: query);

      try {
        final response = await http
            .get(uri, headers: await _authenticatedHeaders())
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          lastError = Exception(
            'Unable to load +EV props: ${response.statusCode}',
          );
          continue;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          lastError = const FormatException(
            'The backend returned invalid +EV data.',
          );
          continue;
        }

        final rawProps = decoded['props'];
        if (rawProps is! List) {
          lastError = const FormatException(
            'The backend did not return a +EV props list.',
          );
          continue;
        }

        _resolvedBaseUrl = candidate;
        final parsedProps = rawProps
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .map(PropData.fromJson)
            .toList(growable: false);
        _lastPropsCount = (decoded['count'] is num)
            ? (decoded['count'] as num).toInt()
            : parsedProps.length;
        return _dedupePropsById(parsedProps);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw Exception('Unable to load +EV props from local backend candidates.');
  }

  Future<List<Map<String, dynamic>>> fetchPropAlerts() async {
    Object? lastError;

    for (final candidate in _candidateBaseUrls) {
      final uri = Uri.parse('$candidate/api/prop-alerts');
      try {
        final response = await http
            .get(uri, headers: await _authenticatedHeaders())
            .timeout(const Duration(seconds: 12));

        if (response.statusCode != 200) {
          lastError = Exception(
            'Unable to load prop alerts: ${response.statusCode}',
          );
          continue;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          lastError = const FormatException(
            'The backend returned invalid alert data.',
          );
          continue;
        }

        final rawAlerts = decoded['alerts'];
        if (rawAlerts is! List) {
          lastError = const FormatException(
            'The backend did not return an alerts list.',
          );
          continue;
        }

        _resolvedBaseUrl = candidate;
        return rawAlerts
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList(growable: false);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw Exception(
      'Unable to load prop alerts from local backend candidates.',
    );
  }

  Future<List<Map<String, dynamic>>> fetchInjuryAlerts({int limit = 50}) async {
    final uri = Uri.parse(
      '$baseUrl/api/injury-alerts',
    ).replace(queryParameters: {'limit': limit.clamp(1, 100).toString()});
    final response = await http
        .get(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Unable to load injury alerts: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['alerts'] is! List) {
      throw const FormatException(
        'The backend returned invalid injury alerts.',
      );
    }
    return (decoded['alerts'] as List)
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchIdentityUnresolvedGrouped({
    String sourceProvider = 'odds-api',
    int limit = 5000,
  }) async {
    final query = Uri(
      queryParameters: {
        'sourceProvider': sourceProvider,
        'limit': limit.toString(),
      },
    ).query;
    final uri = Uri.parse('$baseUrl/api/identity/unresolved-grouped?$query');
    final response = await http
        .get(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to fetch unresolved identities: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid unresolved identity response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> bulkUpsertIdentityMap({
    required Map<String, dynamic> payload,
    String mode = 'merge',
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/identity/map/bulk',
    ).replace(queryParameters: {'mode': mode});
    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Unable to bulk update identity map: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid bulk identity response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> bulkUpsertPlayerAvailability({
    required Map<String, dynamic> payload,
    String mode = 'merge',
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/player-availability/bulk',
    ).replace(queryParameters: {'mode': mode});
    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to bulk update player availability: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid bulk availability response.');
    }
    return decoded;
  }

  Future<void> syncProps() async {
    final uri = Uri.parse('$baseUrl/api/sync');
    final response = await http.post(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      String message = 'Sync failed: ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
      } catch (_) {
        // Keep the normal status-code message.
      }
      throw Exception(message);
    }

    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    } catch (_) {
      // Older backends returned no structured sync status.
    }

    var status = payload?['status']?.toString().toLowerCase() ?? 'complete';
    if (status == 'complete') {
      return;
    }
    if (status == 'failed') {
      throw Exception(payload?['error']?.toString() ?? 'Sync failed.');
    }

    final statusUri = Uri.parse('$baseUrl/api/sync/status');
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final statusResponse = await http
          .get(statusUri)
          .timeout(const Duration(seconds: 10));
      if (statusResponse.statusCode != 200) {
        throw Exception(
          'Unable to check sync status: ${statusResponse.statusCode}',
        );
      }
      final decoded = jsonDecode(statusResponse.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid sync status response.');
      }
      status = decoded['status']?.toString().toLowerCase() ?? 'running';
      if (status == 'complete') {
        return;
      }
      if (status == 'failed') {
        throw Exception(decoded['error']?.toString() ?? 'Sync failed.');
      }
    }
    throw Exception(
      'The live prop sync is still running. Please retry shortly.',
    );
  }

  Future<Map<String, dynamic>> saveSlip({
    required List<SlipSelection> selections,
    double stake = 0,
    String? clientRequestId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/slips');
    final legs = _buildSlipLegs(selections);
    final requestId =
        clientRequestId ??
        'ticket-${DateTime.now().microsecondsSinceEpoch}-${legs.hashCode.abs()}';
    final requestBody = jsonEncode({
      'legs': legs,
      'stake': stake,
      'client_request_id': requestId,
    });

    http.Response? response;
    Object? connectionError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        response = await http
            .post(
              uri,
              headers: await _authenticatedHeaders(
                json: true,
                forceRefresh: attempt > 0,
              ),
              body: requestBody,
            )
            .timeout(const Duration(seconds: 8));
        final retryable =
            response.statusCode == 401 ||
            response.statusCode == 408 ||
            response.statusCode == 425 ||
            response.statusCode == 429 ||
            response.statusCode >= 500;
        if (!retryable || attempt == 2) break;
        connectionError = Exception(
          'Temporary ticket response ${response.statusCode}',
        );
      } catch (error) {
        connectionError = error;
      }
      if (attempt < 2) {
        final retryAfter = int.tryParse(response?.headers['retry-after'] ?? '');
        await Future<void>.delayed(
          retryAfter == null
              ? Duration(milliseconds: 350 * (1 << attempt))
              : Duration(seconds: retryAfter.clamp(1, 3)),
        );
      }
    }

    if (response == null && connectionError != null) {
      throw Exception(
        'The ticket server could not be reached after 3 attempts. '
        'Your picks are still editable; please retry.',
      );
    }
    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      var detail = response?.body ?? '';
      try {
        final errorBody = jsonDecode(detail);
        if (errorBody is Map && errorBody['detail'] != null) {
          detail = errorBody['detail'].toString();
        }
      } catch (_) {
        // Preserve the server response when it is not JSON.
      }
      throw Exception(
        response == null
            ? 'Unable to save slip. Check your connection and try again.'
            : 'Ticket lock failed (${response.statusCode}): $detail',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid slip response.');
    }

    return savedSlipPayload(decoded);
  }

  Future<String> sendTicketSyncDiagnostic(Map<String, Object> payload) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/support/ticket-sync-diagnostic'),
          headers: await _authenticatedHeaders(json: true),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Diagnostic report could not be sent.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid diagnostic response.');
    }
    return decoded['diagnosticId']?.toString() ?? 'SYNC-RECEIVED';
  }

  Future<bool> mirrorPropChatToDiscord(String text) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/realtime/discord/messages'),
            headers: await _authenticatedHeaders(json: true),
            body: jsonEncode({'text': text, 'roomId': 'general'}),
          )
          .timeout(const Duration(seconds: 12));
      return response.statusCode == 200;
    } catch (_) {
      // Discord is an optional mirror; Supabase remains the source of truth.
      return false;
    }
  }

  Future<Map<String, double>> previewSlip({
    required List<SlipSelection> selections,
    required double stake,
  }) async {
    final uri = Uri.parse('$baseUrl/api/slips/preview');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'legs': _buildSlipLegs(selections), 'stake': stake}),
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to preview payout: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid payout-preview response.');
    }

    return {
      'stake': (decoded['stake'] as num?)?.toDouble() ?? 0,
      'potentialPayout': (decoded['potential_payout'] as num?)?.toDouble() ?? 0,
      'potentialProfit': (decoded['potential_profit'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<List<SavedSlip>> fetchSlips({String? status}) async {
    final query = status == null || status == 'all' ? '' : '?status=$status';
    final uri = Uri.parse('$baseUrl/api/slips$query');
    http.Response? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        response = await http
            .get(
              uri,
              headers: await _authenticatedHeaders(forceRefresh: attempt > 0),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 401) break;
      } catch (_) {
        // Retry once immediately; keeping this delay-free also makes a
        // reconnect feel responsive on mobile networks.
      }
    }
    if (response == null) {
      throw Exception(
        'Slips are temporarily unavailable. Check your connection and retry.',
      );
    }

    if (response.statusCode != 200) {
      throw Exception('Unable to load slips: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid slips response.');
    }

    final rawSlips = decoded['slips'];
    if (rawSlips is! List) {
      throw const FormatException('Slips list was not returned.');
    }

    return rawSlips
        .whereType<Map<String, dynamic>>()
        .map(SavedSlip.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> fetchActiveTicket({String? season}) async {
    final query = season == null || season.trim().isEmpty
        ? ''
        : '?season=${season.trim()}';
    final uri = Uri.parse('$baseUrl/api/active-ticket$query');
    http.Response? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      response = await http
          .get(
            uri,
            headers: await _authenticatedHeaders(forceRefresh: attempt > 0),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 401) break;
    }

    if (response == null || response.statusCode != 200) {
      throw Exception(
        response == null
            ? 'Unable to load active ticket. Check your connection and retry.'
            : 'Unable to load active ticket: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid active ticket response.');
    }
    return decoded;
  }

  /// Live current-stat values for every active slip's legs, keyed by slip
  /// id then leg prop id. Powers Slip Watcher's live progress bars across
  /// all locked slips (unlike [fetchActiveTicket], which only covers the
  /// first one).
  Future<Map<String, Map<String, dynamic>>> fetchLiveSlipStats({
    String? season,
  }) async {
    final query = season == null || season.trim().isEmpty
        ? ''
        : '?season=${season.trim()}';
    final uri = Uri.parse('$baseUrl/api/slips/live-stats$query');
    final response = await http
        .get(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Unable to load live slip stats: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid live slip stats response.');
    }
    final rawSlips = decoded['slips'];
    if (rawSlips is! Map) {
      return const {};
    }

    final result = <String, Map<String, dynamic>>{};
    for (final entry in rawSlips.entries) {
      final slipId = entry.key.toString();
      final slipData = entry.value;
      if (slipData is! Map) {
        continue;
      }
      final rawLegs = slipData['legs'];
      if (rawLegs is! List) {
        continue;
      }
      final legsById = <String, dynamic>{};
      for (final leg in rawLegs) {
        if (leg is! Map) {
          continue;
        }
        final propId = leg['prop_id']?.toString() ?? leg['id']?.toString();
        if (propId == null || propId.isEmpty) {
          continue;
        }
        legsById[propId] = Map<String, dynamic>.from(leg);
      }
      result[slipId] = legsById;
    }
    return result;
  }

  Future<void> refreshSlipGames(String sportKey) async {
    final uri = Uri.parse('$baseUrl/api/slips/refresh-games/$sportKey');
    final response = await http
        .post(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Unable to refresh $sportKey games: ${response.body}');
    }
  }

  Future<void> refreshAllSlipGames() async {
    const sportKeys = [
      'baseball_mlb',
      'basketball_nba',
      'basketball_wnba',
      'americanfootball_nfl',
      'icehockey_nhl',
      'soccer_epl',
      'soccer_usa_mls',
      'soccer_france_ligue_one',
      'soccer_germany_bundesliga',
      'soccer_italy_serie_a',
      'soccer_spain_la_liga',
    ];

    for (final sportKey in sportKeys) {
      try {
        await refreshSlipGames(sportKey);
      } catch (_) {
        // Continue refreshing the remaining sports.
      }
    }
  }

  Future<void> refreshSavedSlipGameStatuses() async {
    final uri = Uri.parse('$baseUrl/api/slips/game-status/refresh');
    final response = await http
        .post(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Unable to refresh ticket game status.');
    }
  }

  Future<void> gradeWnbaSlips() async {
    await gradePendingSlips();
  }

  Future<Map<String, dynamic>> gradePendingSlips() async {
    final uri = Uri.parse('$baseUrl/api/slips/grade');
    var response = await http
        .post(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 401) {
      response = await http
          .post(uri, headers: await _authenticatedHeaders(forceRefresh: true))
          .timeout(const Duration(seconds: 60));
    }

    if (response.statusCode != 200) {
      throw Exception('Unable to grade pending slips: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid slip grading response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> reconcileSlips() async {
    final uri = Uri.parse('$baseUrl/api/slips/reconcile');
    var response = await http
        .post(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 60));
    if (response.statusCode == 401) {
      response = await http
          .post(uri, headers: await _authenticatedHeaders(forceRefresh: true))
          .timeout(const Duration(seconds: 60));
    }
    if (response.statusCode != 200) {
      throw Exception('Unable to reconcile slips: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid slip reconciliation response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> buildPropSlip({
    required List<String> sports,
    required List<String> propSites,
    required List<String> markets,
    required String riskMode,
    required bool correlationGuardEnabled,
    required int maximumLegsPerGame,
    required int maximumLegsPerTeam,
    required int maximumLegsPerPlayer,
    required List<Map<String, dynamic>> lockedLegs,
    required List<String> excludedPropIds,
    required int legCount,
    required int minimumEdge,
    required int minimumConfidence,
    required bool sameGameAllowed,
    required String buildMode,
    required String sidePreference,
  }) async {
    final uri = Uri.parse('$baseUrl/api/prop-builder');
    final response = await http
        .post(
          uri,
          headers: await _authenticatedHeaders(json: true),
          body: jsonEncode({
            'sports': sports,
            'prop_sites': propSites,
            'markets': markets,
            'risk_mode': riskMode,
            'correlation_guard_enabled': correlationGuardEnabled,
            'maximum_legs_per_game': maximumLegsPerGame,
            'maximum_legs_per_team': maximumLegsPerTeam,
            'maximum_legs_per_player': maximumLegsPerPlayer,
            'locked_legs': lockedLegs,
            'excluded_prop_ids': excludedPropIds,
            'leg_count': legCount,
            'minimum_edge': minimumEdge,
            'minimum_confidence': minimumConfidence,
            'same_game_allowed': sameGameAllowed,
            'build_mode': buildMode,
            'side_preference': sidePreference,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Unable to build prop slip: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid Prop Builder response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> replacePropLeg({
    required String currentPropId,
    required List<String> sports,
    required List<String> propSites,
    required List<String> markets,
    required String riskMode,
    required bool correlationGuardEnabled,
    required int maximumLegsPerGame,
    required int maximumLegsPerTeam,
    required int maximumLegsPerPlayer,
    required int minimumEdge,
    required int minimumConfidence,
    required String buildMode,
    required String sidePreference,
    required List<String> excludedPropIds,
    required List<String> excludedPlayers,
    required List<String> excludedEventIds,
  }) async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/replace');
    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'current_prop_id': currentPropId,
            'sports': sports,
            'prop_sites': propSites,
            'markets': markets,
            'risk_mode': riskMode,
            'correlation_guard_enabled': correlationGuardEnabled,
            'maximum_legs_per_game': maximumLegsPerGame,
            'maximum_legs_per_team': maximumLegsPerTeam,
            'maximum_legs_per_player': maximumLegsPerPlayer,
            'minimum_edge': minimumEdge,
            'minimum_confidence': minimumConfidence,
            'build_mode': buildMode,
            'side_preference': sidePreference,
            'excluded_prop_ids': excludedPropIds,
            'excluded_players': excludedPlayers,
            'excluded_event_ids': excludedEventIds,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Unable to replace prop: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid replacement response.');
    }
    final replacement = decoded['replacement'];
    if (replacement is! Map<String, dynamic>) {
      throw Exception('Replacement prop was missing.');
    }
    return replacement;
  }

  Future<Map<String, dynamic>> checkPropLineMovement({
    required List<Map<String, dynamic>> legs,
    bool refresh = false,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/prop-builder/check-lines',
    ).replace(queryParameters: {'refresh': refresh.toString()});
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'legs': legs}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Unable to check line movement: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid line movement response.');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> fetchPropBuilderPresets() async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/presets');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to load presets: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('Invalid preset response.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((preset) => Map<String, dynamic>.from(preset))
        .toList();
  }

  Future<Map<String, dynamic>> savePropBuilderPreset({
    required String name,
    required List<String> sports,
    required List<String> propSites,
    required List<String> markets,
    required String riskMode,
    required int legCount,
    required int minimumEdge,
    required int minimumConfidence,
    required bool sameGameAllowed,
    required String buildMode,
    required String sidePreference,
  }) async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/presets');
    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name,
            'sports': sports,
            'prop_sites': propSites,
            'markets': markets,
            'risk_mode': riskMode,
            'leg_count': legCount,
            'minimum_edge': minimumEdge,
            'minimum_confidence': minimumConfidence,
            'same_game_allowed': sameGameAllowed,
            'build_mode': buildMode,
            'side_preference': sidePreference,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to save preset: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid saved preset response.');
    }
    return decoded;
  }

  Future<void> deletePropBuilderPreset(int presetId) async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/presets/$presetId');
    final response = await http
        .delete(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to delete preset: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> fetchPropBuilderHistory({
    int limit = 30,
  }) async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/history?limit=$limit');
    final response = await http
        .get(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to load builder history: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('Invalid builder history response.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> deletePropBuilderHistoryItem(int historyId) async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/history/$historyId');
    final response = await http
        .delete(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to delete build history: ${response.body}');
    }
  }

  Future<void> clearPropBuilderHistory() async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/history');
    final response = await http
        .delete(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to clear build history: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> gradePropBuilderHistory() async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/history/grade');
    final response = await http
        .post(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Unable to grade builder history: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid builder history grade response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> fetchPropBuilderPerformance({
    int recentLimit = 10,
    int? days,
    String? sport,
    String? propSite,
    String? market,
    String? player,
  }) async {
    final query = <String, String>{'recent_limit': '$recentLimit'};
    if (days != null) {
      query['days'] = '$days';
    }
    if (sport != null && sport.isNotEmpty && sport != 'ALL') {
      query['sport'] = sport;
    }
    if (propSite != null && propSite.isNotEmpty && propSite != 'ALL') {
      query['prop_site'] = propSite;
    }
    if (market != null && market.isNotEmpty && market != 'ALL') {
      query['market'] = market;
    }
    if (player != null && player.isNotEmpty && player != 'ALL') {
      query['player'] = player;
    }
    final uri = Uri.parse(
      '$baseUrl/api/prop-builder/performance',
    ).replace(queryParameters: query);
    final response = await http
        .get(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Unable to load builder performance: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid builder performance response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> fetchPropBuilderStrategy() async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/strategy');
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Unable to load builder strategy: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid builder strategy response.');
    }
    return decoded;
  }

  Future<void> updateSlipStatus({
    required String slipId,
    required String status,
  }) async {
    final uri = Uri.parse('$baseUrl/api/slips/$slipId/status?status=$status');
    final response = await http
        .patch(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Unable to update slip: ${response.body}');
    }
  }

  Future<void> deleteSlip(String slipId) async {
    final uri = Uri.parse('$baseUrl/api/slips/$slipId');
    final response = await http
        .delete(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Unable to unlock slip: ${response.body}');
    }
  }
}
