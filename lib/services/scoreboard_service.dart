import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/scoreboard_game.dart';

class ScoreboardService {
  ScoreboardService({required this.baseUrl});

  final String baseUrl;

  List<String> get _candidateBaseUrls {
    final configured = _normalizeBaseUrl(baseUrl);
    final candidates = <String>{configured};
    return candidates
        .map(_normalizeBaseUrl)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<http.Response> _getWithFallback(
    String path, {
    Map<String, String>? queryParameters,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    Object? lastError;

    for (final candidate in _candidateBaseUrls) {
      try {
        final uri = Uri.parse(
          '$candidate$path',
        ).replace(queryParameters: queryParameters);
        final response = await http.get(uri).timeout(timeout);
        if (response.statusCode == 404) {
          continue;
        }
        return response;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is Exception) {
      throw lastError;
    }
    throw Exception('Unable to reach local scoreboard backend candidates.');
  }

  Future<List<ScoreboardGame>> fetchGames({required DateTime date}) async {
    final formattedDate =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final response = await _getWithFallback(
      '/api/scoreboard',
      queryParameters: {'date': formattedDate},
      timeout: const Duration(seconds: 12),
    );
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    // Some backend environments do not expose /api/scoreboard yet.
    // Treat 404 as temporarily unavailable so the UI can fail soft.
    if (response.statusCode == 404) {
      return isToday ? _fetchFallbackGamesFromProps() : const [];
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return isToday ? _fetchFallbackGamesFromProps() : const [];
    }

    final decoded = jsonDecode(response.body);
    final dynamic rawGames;
    if (decoded is List) {
      rawGames = decoded;
    } else if (decoded is Map) {
      final detail = decoded['detail']?.toString().toLowerCase();
      if (detail == 'not found') {
        return isToday ? _fetchFallbackGamesFromProps() : const [];
      }
      rawGames = decoded['games'] ?? decoded['events'] ?? decoded['data'] ?? [];
    } else {
      rawGames = [];
    }

    if (rawGames is! List) {
      return const [];
    }

    final parsedGames = rawGames
        .whereType<Map>()
        .map((item) => ScoreboardGame.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    if (parsedGames.isNotEmpty) {
      return parsedGames;
    }

    // Some providers return 200 with an empty list for future slates.
    // In that case, populate upcoming cards from the props feed.
    return isToday ? _fetchFallbackGamesFromProps() : const [];
  }

  Future<List<ScoreboardGame>> _fetchFallbackGamesFromProps() async {
    try {
      final response = await _getWithFallback(
        '/api/props',
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const [];
      }

      final rawProps = decoded['props'];
      if (rawProps is! List) {
        return const [];
      }

      final byGame = <String, ScoreboardGame>{};
      for (final raw in rawProps.whereType<Map>()) {
        final prop = Map<String, dynamic>.from(raw);
        final sport = (prop['sport'] ?? '').toString().toUpperCase();
        final matchup = (prop['matchup'] ?? '').toString();
        if (sport.isEmpty || matchup.isEmpty) {
          continue;
        }

        final gameId = '$sport|$matchup';
        byGame.putIfAbsent(gameId, () {
          final teams = _splitMatchup(matchup);
          final isFight = sport == 'UFC' || sport == 'MMA';

          return ScoreboardGame(
            id: gameId,
            sport: sport,
            league: sport,
            awayTeam: isFight ? '' : teams.$1,
            homeTeam: isFight ? '' : teams.$2,
            status: 'UPCOMING',
            detail: 'Upcoming (props feed)',
            fighterOne: isFight ? teams.$1 : null,
            fighterTwo: isFight ? teams.$2 : null,
          );
        });
      }

      return byGame.values.toList();
    } catch (_) {
      return const [];
    }
  }

  (String, String) _splitMatchup(String matchup) {
    final normalized = matchup.trim();
    if (normalized.contains(' @ ')) {
      final parts = normalized.split(' @ ');
      if (parts.length == 2) {
        return (parts[0].trim(), parts[1].trim());
      }
    }
    if (normalized.contains(' vs ')) {
      final parts = normalized.split(' vs ');
      if (parts.length == 2) {
        return (parts[0].trim(), parts[1].trim());
      }
    }
    if (normalized.contains(' VS ')) {
      final parts = normalized.split(' VS ');
      if (parts.length == 2) {
        return (parts[0].trim(), parts[1].trim());
      }
    }
    return (normalized, '');
  }
}
