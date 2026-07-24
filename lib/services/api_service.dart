import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prop_data.dart';
import '../models/game_market.dart';
import '../models/saved_slip.dart';
import '../models/slip_selection.dart';
import 'supabase_service.dart';

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
  static List<PropData> _lastSuccessfulProps = const [];
  static int _lastFacetCount = 0;
  static Map<String, int> _lastCategoryCounts = const {};
  static final ValueNotifier<BackendRefreshStatus> refreshStatusNotifier =
      ValueNotifier<BackendRefreshStatus>(const BackendRefreshStatus.empty());
  int _lastPropsCount = 0;

  static String get baseUrl => _resolvedBaseUrl ?? _configuredBaseUrl;
  int get lastPropsCount => _lastPropsCount;
  int get lastFacetCount => _lastFacetCount;
  Map<String, int> get lastCategoryCounts =>
      Map.unmodifiable(_lastCategoryCounts);

  Future<Map<String, String>> _authenticatedHeaders({
    bool json = false,
    bool forceRefresh = false,
  }) async {
    final client = SupabaseService.client;
    final session = client?.auth.currentSession;
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
        final response = await http
            .post(
              Uri.parse('$candidate/api/intelligence/$path'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));
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
        final response = await http
            .get(Uri.parse('$candidate/api/intelligence/$path'))
            .timeout(const Duration(seconds: 12));
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
        'game_start_time': prop.gameStartTime,
        'player': prop.player,
        'image_path': prop.imagePath,
        'sport': prop.sport,
        'matchup': prop.matchup,
        'sportsbook': prop.sportsbook,
        'market': prop.market,
        'line': prop.line,
        'side': selection.sideLabel,
        'odds': selection.odds,
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
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 35));
        if (response.statusCode == 200) return response;
        lastError = Exception('Unable to load props: ${response.statusCode}');
        if (response.statusCode < 500 && response.statusCode != 429) break;
      } catch (error) {
        lastError = error;
      }
      if (attempt < 3) {
        final backoffMs = attempt == 1 ? 400 : 800;
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
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
              .get(uri)
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
              .get(uri)
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
    int limit = 75,
    int offset = 0,
  }) async {
    Object? lastError;

    for (final candidate in _candidateBaseUrls) {
      try {
        final uri = Uri.parse('$candidate/api/props').replace(
          queryParameters: {
            'side': selectedSide,
            'tier': selectedTier,
            'sportsbook': selectedSportsbook,
            'sport': selectedSport,
            'category': selectedCategory,
            'search': search,
            'minConfidence': minConfidence.toString(),
            'sortBy': sortBy,
            'limit': limit.clamp(1, 500).toString(),
            'offset': offset.toString(),
          },
        );
        final response = await _getPropsPage(uri);
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('The backend returned invalid data.');
        }
        final rawProps = decoded['props'];
        if (rawProps is! List) {
          throw const FormatException(
            'The backend did not return a props list.',
          );
        }
        final totalCount = decoded['count'] is num
            ? (decoded['count'] as num).toInt()
            : rawProps.length;
        _lastFacetCount =
            (decoded['facetCount'] as num?)?.toInt() ?? totalCount;
        final rawCategoryCounts = decoded['categoryCounts'];
        _lastCategoryCounts = rawCategoryCounts is Map
            ? {
                for (final entry in rawCategoryCounts.entries)
                  entry.key.toString().trim().toUpperCase():
                      (entry.value as num?)?.toInt() ?? 0,
              }
            : const {};
        final rawMaps = rawProps
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList(growable: false);
        final props = _dedupePropsById(rawMaps.map(PropData.fromJson).toList());
        _resolvedBaseUrl = candidate;
        _lastPropsCount = totalCount > 0 ? totalCount : props.length;
        _lastSuccessfulProps = props;
        if (offset == 0) {
          await _savePropsCache(
            _propsCacheKey(
              selectedSide,
              selectedTier,
              selectedSportsbook,
              selectedSport,
              selectedCategory,
              search,
              minConfidence,
              sortBy,
            ),
            rawMaps,
            _lastPropsCount,
            _lastFacetCount,
            _lastCategoryCounts,
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

    if (_lastSuccessfulProps.isNotEmpty) {
      refreshStatusNotifier.value = BackendRefreshStatus(
        lastRefreshAt: refreshStatusNotifier.value.lastRefreshAt,
        sourceUrl: refreshStatusNotifier.value.sourceUrl,
        message: 'Showing the last stable prop download while reconnecting',
      );
      _lastPropsCount = _lastSuccessfulProps.length;
      return List<PropData>.unmodifiable(_lastSuccessfulProps);
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw Exception(
      'Unable to reach the live props service. Check your connection and retry.',
    );
  }

  String _propsCacheKey(
    String side,
    String tier,
    String sportsbook,
    String sport,
    String category,
    String search,
    int confidence,
    String sort,
  ) {
    final raw =
        [side, tier, sportsbook, sport, category, search, '$confidence', sort]
            .map(
              (value) => value.trim().toLowerCase().replaceAll(
                RegExp(r'[^a-z0-9]+'),
                '-',
              ),
            )
            .join('_');
    return 'prop-feed-v2-$raw';
  }

  Future<void> _savePropsCache(
    String key,
    List<Map<String, dynamic>> rawProps,
    int total,
    int facetTotal,
    Map<String, int> categoryCounts,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      key,
      jsonEncode({
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'total': total,
        'facetTotal': facetTotal,
        'categoryCounts': categoryCounts,
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
      sortBy,
    );
    final encoded = preferences.getString(key);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded['props'] is! List) {
        return const [];
      }
      _lastPropsCount = (decoded['total'] as num?)?.toInt() ?? 0;
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
      final cached = (decoded['props'] as List)
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(PropData.fromJson)
          .toList(growable: false);
      refreshStatusNotifier.value = BackendRefreshStatus(
        lastRefreshAt: DateTime.tryParse(decoded['savedAt']?.toString() ?? ''),
        sourceUrl: 'device cache',
        message: 'Showing saved props while refreshing',
      );
      return cached;
    } catch (_) {
      return const [];
    }
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
            .get(uri)
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
            .get(uri)
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
  }) async {
    final uri = Uri.parse('$baseUrl/api/slips');
    final legs = _buildSlipLegs(selections);

    final response = await http.post(
      uri,
      headers: await _authenticatedHeaders(json: true),
      body: jsonEncode({'legs': legs, 'stake': stake}),
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to save slip: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid slip response.');
    }

    return decoded;
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
    var response = await http.get(uri, headers: await _authenticatedHeaders());
    if (response.statusCode == 401) {
      response = await http.get(
        uri,
        headers: await _authenticatedHeaders(forceRefresh: true),
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
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Unable to load active ticket: ${response.body}');
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

  Future<void> gradeWnbaSlips() async {
    final uri = Uri.parse('$baseUrl/api/slips/grade-wnba');
    var response = await http
        .post(uri, headers: await _authenticatedHeaders())
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 401) {
      response = await http
          .post(uri, headers: await _authenticatedHeaders(forceRefresh: true))
          .timeout(const Duration(seconds: 60));
    }

    if (response.statusCode != 200) {
      throw Exception('Unable to grade WNBA slips: ${response.body}');
    }
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
          headers: const {'Content-Type': 'application/json'},
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
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
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
        .delete(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to delete build history: ${response.body}');
    }
  }

  Future<void> clearPropBuilderHistory() async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/history');
    final response = await http
        .delete(uri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Unable to clear build history: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> gradePropBuilderHistory() async {
    final uri = Uri.parse('$baseUrl/api/prop-builder/history/grade');
    final response = await http.post(uri).timeout(const Duration(seconds: 60));
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
    final response = await http.get(uri).timeout(const Duration(seconds: 30));
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
    final response = await http.patch(
      uri,
      headers: await _authenticatedHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to update slip: ${response.body}');
    }
  }

  Future<void> deleteSlip(String slipId) async {
    final uri = Uri.parse('$baseUrl/api/slips/$slipId');
    final response = await http.delete(
      uri,
      headers: await _authenticatedHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Unable to unlock slip: ${response.body}');
    }
  }
}
