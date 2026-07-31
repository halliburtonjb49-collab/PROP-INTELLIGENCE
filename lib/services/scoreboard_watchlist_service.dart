import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scoreboard_game.dart';
import 'scoreboard_service.dart';

enum ScoreboardWatchAlertType { score, finalResult, extendedPlay }

class ScoreboardWatchAlert {
  const ScoreboardWatchAlert({
    required this.game,
    required this.type,
    required this.message,
  });

  final ScoreboardGame game;
  final ScoreboardWatchAlertType type;
  final String message;
}

class ScoreboardWatchlistService {
  ScoreboardWatchlistService._();

  @visibleForTesting
  ScoreboardWatchlistService.forTesting();

  static final instance = ScoreboardWatchlistService._();
  static const _storageKey = 'scoreboard_watched_game_ids';

  final ValueNotifier<Set<String>> watchedIds = ValueNotifier(<String>{});
  final ValueNotifier<List<ScoreboardGame>> watchedGames = ValueNotifier(
    const <ScoreboardGame>[],
  );
  final ValueNotifier<ScoreboardWatchAlert?> latestAlert = ValueNotifier(null);
  final Map<String, ScoreboardGame> _latestById = {};
  ScoreboardService? _service;
  Timer? _timer;
  bool _loaded = false;
  bool _refreshing = false;

  bool isWatching(String gameId) => watchedIds.value.contains(gameId);

  Future<void> load() async {
    if (_loaded) return;
    final preferences = await SharedPreferences.getInstance();
    watchedIds.value = {...?preferences.getStringList(_storageKey)};
    _loaded = true;
    _publishWatchedGames();
  }

  Future<bool> toggle(ScoreboardGame game) async {
    await load();
    final next = {...watchedIds.value};
    final added = next.add(game.id);
    if (!added) next.remove(game.id);
    _latestById[game.id] = game;
    watchedIds.value = next;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_storageKey, next.toList()..sort());
    _publishWatchedGames();
    return added;
  }

  Future<void> start(ScoreboardService service) async {
    _service = service;
    await load();
    await refresh();
    _timer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() async {
    final service = _service;
    if (service == null || _refreshing) return;
    _refreshing = true;
    try {
      processGames(await service.fetchGames(date: DateTime.now()));
    } catch (_) {
      // The scoreboard view and next timer tick remain available as fallbacks.
    } finally {
      _refreshing = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _service = null;
  }

  void processGames(Iterable<ScoreboardGame> games) {
    for (final game in games) {
      final previous = _latestById[game.id];
      _latestById[game.id] = game;
      if (previous == null || !isWatching(game.id)) continue;
      final alert = _alertFor(previous, game);
      if (alert != null) latestAlert.value = alert;
    }
    _publishWatchedGames();
  }

  ScoreboardWatchAlert? _alertFor(
    ScoreboardGame previous,
    ScoreboardGame current,
  ) {
    final priorExtended = _isExtended(previous.detail);
    final nowExtended = _isExtended(current.detail);
    if (!priorExtended && nowExtended) {
      return ScoreboardWatchAlert(
        game: current,
        type: ScoreboardWatchAlertType.extendedPlay,
        message: '${_matchup(current)} has entered ${current.detail}.',
      );
    }
    if (!previous.isFinal && current.isFinal) {
      final away = current.awayScore ?? 0;
      final home = current.homeScore ?? 0;
      final result = away == home
          ? 'finished tied $away-$home'
          : '${away > home ? current.awayTeam : current.homeTeam} won '
                '${away > home ? '$away-$home' : '$home-$away'}';
      return ScoreboardWatchAlert(
        game: current,
        type: ScoreboardWatchAlertType.finalResult,
        message: '${_matchup(current)}: $result.',
      );
    }
    if (previous.awayScore != current.awayScore ||
        previous.homeScore != current.homeScore) {
      return ScoreboardWatchAlert(
        game: current,
        type: ScoreboardWatchAlertType.score,
        message:
            '${_matchup(current)} score changed: '
            '${current.awayScore ?? 0}-${current.homeScore ?? 0}.',
      );
    }
    return null;
  }

  bool _isExtended(String detail) {
    final value = detail.toUpperCase();
    return RegExp(
      r'\bOT\b|OVERTIME|EXTRA INNING|EXTRA TIME|SHOOTOUT',
    ).hasMatch(value);
  }

  String _matchup(ScoreboardGame game) => '${game.awayTeam} @ ${game.homeTeam}';

  void _publishWatchedGames() {
    final games =
        watchedIds.value
            .map((id) => _latestById[id])
            .whereType<ScoreboardGame>()
            .toList()
          ..sort((a, b) {
            if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
            if (a.isUpcoming != b.isUpcoming) return a.isUpcoming ? -1 : 1;
            return (a.startTime ?? DateTime(2100)).compareTo(
              b.startTime ?? DateTime(2100),
            );
          });
    watchedGames.value = List.unmodifiable(games);
  }
}
