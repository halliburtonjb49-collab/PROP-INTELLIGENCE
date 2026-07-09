import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/prop_data.dart';
import '../models/saved_slip.dart';
import '../models/slip_selection.dart';

class ApiService {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8010',
  );
  static String? _resolvedBaseUrl;
  int _lastPropsCount = 0;

  static String get baseUrl => _resolvedBaseUrl ?? _configuredBaseUrl;
  int get lastPropsCount => _lastPropsCount;

  static List<String> get _candidateBaseUrls {
    final configured = _normalizeBaseUrl(_configuredBaseUrl);
    final candidates = <String>{
      configured,
      configured.replaceFirst('127.0.0.1', 'localhost'),
      configured.replaceFirst('localhost', '127.0.0.1'),
      'http://127.0.0.1:8011',
      'http://localhost:8011',
      'http://127.0.0.1:8010',
      'http://localhost:8010',
      'http://127.0.0.1:8000',
      'http://localhost:8000',
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
        'player': prop.player,
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
    int minConfidence = 0,
    String sortBy = 'confidence',
  }) async {
    Object? lastError;

    for (final candidate in _candidateBaseUrls) {
      final uri = Uri.parse(
        '$candidate/api/props',
      ).replace(
        queryParameters: {
          'side': selectedSide,
          'tier': selectedTier,
          'minConfidence': minConfidence.toString(),
          'sortBy': sortBy,
        },
      );
      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          lastError = Exception('Unable to load props: ${response.statusCode}');
          continue;
        }

        final decoded = jsonDecode(response.body);

        if (decoded is! Map<String, dynamic>) {
          lastError = const FormatException(
            'The backend returned invalid data.',
          );
          continue;
        }

        final rawProps = decoded['props'];

        if (rawProps is! List) {
          lastError = const FormatException(
            'The backend did not return a props list.',
          );
          continue;
        }

        _resolvedBaseUrl = candidate;
        final parsedProps = rawProps
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .map(PropData.fromJson)
            .toList();
        _lastPropsCount =
          (decoded['count'] is num)
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
    throw Exception(
      'Unable to load props from local backend candidates. Start the real backend in ../python_backend on port 8010 or 8000.',
    );
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
    throw Exception('Unable to load prop alerts from local backend candidates.');
  }

  Future<Map<String, dynamic>> fetchIdentityUnresolvedGrouped({
    String sourceProvider = 'odds-api',
    int limit = 5000,
  }) async {
    final query = Uri(queryParameters: {
      'sourceProvider': sourceProvider,
      'limit': limit.toString(),
    }).query;
    final uri = Uri.parse('$baseUrl/api/identity/unresolved-grouped?$query');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Unable to fetch unresolved identities: ${response.body}');
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
      throw Exception('Unable to bulk update player availability: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid bulk availability response.');
    }
    return decoded;
  }

  Future<void> syncProps() async {
    final uri = Uri.parse('$baseUrl/api/sync');
    final response = await http.post(uri).timeout(const Duration(seconds: 90));

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
  }

  Future<Map<String, dynamic>> saveSlip({
    required List<SlipSelection> selections,
    double stake = 0,
  }) async {
    final uri = Uri.parse('$baseUrl/api/slips');
    final legs = _buildSlipLegs(selections);

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
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
    final response = await http.get(uri);

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
    final query =
        season == null || season.trim().isEmpty ? '' : '?season=${season.trim()}';
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

  Future<void> refreshSlipGames(String sportKey) async {
    final uri = Uri.parse('$baseUrl/api/slips/refresh-games/$sportKey');
    final response = await http.post(uri).timeout(const Duration(seconds: 30));

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
    final response = await http.post(uri).timeout(const Duration(seconds: 60));

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
    final response = await http.patch(uri);

    if (response.statusCode != 200) {
      throw Exception('Unable to update slip: ${response.body}');
    }
  }
}
