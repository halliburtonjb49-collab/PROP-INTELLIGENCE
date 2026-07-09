import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/scoreboard_controller.dart';
import '../models/scoreboard_game.dart';
import '../services/api_service.dart';
import '../services/scoreboard_service.dart';

enum ScoreboardFilter { all, live, upcoming, finalGames }

class ScoreboardPage extends StatefulWidget {
  const ScoreboardPage({super.key, required this.selectedSport});

  final String selectedSport;

  @override
  State<ScoreboardPage> createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  late final ScoreboardController _controller;
  ScoreboardFilter _selectedFilter = ScoreboardFilter.all;

  @override
  void initState() {
    super.initState();
    _controller = ScoreboardController(
      service: ScoreboardService(baseUrl: ApiService.baseUrl),
    );
    _controller.addListener(_handleControllerChange);
    unawaited(_controller.load());
    _controller.beginLiveRefresh();
  }

  void _handleControllerChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF050B11),
      child: Column(
        children: [
          _buildHeader(),
          _buildFilterRow(),
          const Divider(height: 1, color: Color(0xFF293946)),
          Expanded(child: _buildScoreboardBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    const sportLabel = 'Games and live scores across all sports for the selected date';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SCOREBOARD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sportLabel,
                  style: TextStyle(color: Color(0xFF96A4B2), fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _previousDay,
            icon: const Icon(Icons.chevron_left, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFF101D28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF8B6813)),
            ),
            child: Text(
              _formatDate(_controller.selectedDate),
              style: const TextStyle(
                color: Color(0xFFFFC400),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: _nextDay,
            icon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh scores',
            onPressed: _controller.isRefreshing ? null : _refreshScores,
            icon: _controller.isRefreshing
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFFC400),
                    ),
                  )
                : const Icon(Icons.refresh, color: Color(0xFFFFC400)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        children: [
          _scoreFilterButton(filter: ScoreboardFilter.all, label: 'ALL GAMES'),
          const SizedBox(width: 8),
          _scoreFilterButton(filter: ScoreboardFilter.live, label: 'LIVE NOW'),
          const SizedBox(width: 8),
          _scoreFilterButton(
            filter: ScoreboardFilter.upcoming,
            label: 'UPCOMING',
          ),
          const SizedBox(width: 8),
          _scoreFilterButton(
            filter: ScoreboardFilter.finalGames,
            label: 'FINAL',
          ),
        ],
      ),
    );
  }

  Widget _scoreFilterButton({
    required ScoreboardFilter filter,
    required String label,
  }) {
    final selected = _selectedFilter == filter;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (_selectedFilter == filter) {
          return;
        }
        setState(() {
          _selectedFilter = filter;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFC400) : const Color(0xFF101D28),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFFFC400) : const Color(0xFF293946),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF050A0F) : Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildScoreboardBody() {
    if (_controller.isLoading && _controller.games.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFC400)),
      );
    }

    if (_controller.errorMessage != null && _controller.games.isEmpty) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: Color(0xFFFF4D5A),
                size: 34,
              ),
              const SizedBox(height: 12),
              const Text(
                'SCORES COULD NOT LOAD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _controller.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF96A4B2), fontSize: 9),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  _controller.load();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('TRY AGAIN'),
              ),
            ],
          ),
        ),
      );
    }

    final games = _filteredGames;
    final isFallbackData =
        games.isNotEmpty &&
        games.every(
          (game) =>
              game.detail.toUpperCase().contains('PROPS FEED') ||
              game.detail.toUpperCase().contains('FROM PROPS'),
        );
    if (games.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined, color: Color(0xFF96A4B2), size: 32),
            SizedBox(height: 10),
            Text(
              'NO GAMES FOUND',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Try another date or filter.',
            ),
          ],
        ),
      );
    }

    final grouped = <String, List<ScoreboardGame>>{};
    for (final game in games) {
      final league = game.league.isNotEmpty ? game.league : game.sport;
      grouped.putIfAbsent(league, () => []).add(game);
    }

    return RefreshIndicator(
      color: const Color(0xFFFFC400),
      onRefresh: () {
        return _controller.load(silent: true);
      },
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (isFallbackData)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF101D28),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8B6813)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFFC400), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing upcoming matchups from props feed until live scoreboard games are available.',
                      style: TextStyle(
                        color: Color(0xFFDBE6EF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ...grouped.entries.map(
            (entry) => _buildSportSection(entry.key, entry.value),
          ),
        ],
      ),
    );
  }

  List<ScoreboardGame> get _filteredGames {
    final games = _controller.games;
    switch (_selectedFilter) {
      case ScoreboardFilter.live:
        return games.where((game) => game.isLive).toList();
      case ScoreboardFilter.upcoming:
        return games.where((game) => game.isUpcoming).toList();
      case ScoreboardFilter.finalGames:
        return games.where((game) => game.isFinal).toList();
      case ScoreboardFilter.all:
        return games;
    }
  }

  Widget _buildSportSection(String sport, List<ScoreboardGame> games) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _scoreboardSportIcon(sport),
              const SizedBox(width: 8),
              Text(
                sport,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${games.length} GAMES',
                style: const TextStyle(color: Color(0xFF96A4B2), fontSize: 8),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: games.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 165,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              return _buildGameCard(games[index]);
            },
          ),
        ],
      ),
    );
  }

  Widget _scoreboardSportIcon(String sport) {
    switch (sport) {
      case 'NBA':
      case 'WNBA':
        return const Icon(
          Icons.sports_basketball,
          color: Color(0xFFFFC400),
          size: 18,
        );
      case 'NFL':
        return const Icon(
          Icons.sports_football,
          color: Color(0xFFFFC400),
          size: 18,
        );
      case 'MLB':
        return const Icon(
          Icons.sports_baseball,
          color: Color(0xFFFFC400),
          size: 18,
        );
      case 'SOCCER':
        return const Icon(
          Icons.sports_soccer,
          color: Color(0xFFFFC400),
          size: 18,
        );
      case 'TENNIS':
        return const Icon(
          Icons.sports_tennis,
          color: Color(0xFFFFC400),
          size: 18,
        );
      case 'PGA':
        return const Icon(
          Icons.sports_golf,
          color: Color(0xFF9A6338),
          size: 18,
        );
      case 'UFC':
      case 'MMA':
        return const Icon(Icons.sports_mma, color: Color(0xFF9A6338), size: 18);
      default:
        return const Icon(Icons.sports, color: Color(0xFF96A4B2), size: 18);
    }
  }

  Widget _buildGameCard(ScoreboardGame game) {
    if (game.isUfc) {
      return _buildUfcFightCard(game);
    }

    return _buildTeamGameCard(game);
  }

  Widget _buildTeamGameCard(ScoreboardGame game) {
    final isLive = game.isLive;
    final isFinal = game.isFinal;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        _openGameDetails(game);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1721),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLive ? const Color(0xFFFFC400) : const Color(0xFF293946),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _statusBadge(game.status),
                const Spacer(),
                Text(
                  game.detail.isNotEmpty ? game.detail : _gameTimeLabel(game),
                  style: TextStyle(
                    color: isLive
                        ? const Color(0xFFFFC400)
                        : const Color(0xFF96A4B2),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _teamScoreRow(
              team: game.awayTeam,
              score: game.awayScore,
              logo: game.awayLogo,
            ),
            const SizedBox(height: 11),
            _teamScoreRow(
              team: game.homeTeam,
              score: game.homeScore,
              logo: game.homeLogo,
            ),
            const Spacer(),
            Row(
              children: [
                Text(
                  isFinal
                      ? 'GAME COMPLETE'
                      : isLive
                      ? 'LIVE UPDATES'
                      : 'GAME PREVIEW',
                  style: const TextStyle(color: Color(0xFF96A4B2), fontSize: 8),
                ),
                const Spacer(),
                const Text(
                  'VIEW GAME',
                  style: TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUfcFightCard(ScoreboardGame fight) {
    final isFinal = fight.isFinal;
    final isLive = fight.isLive;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        _openGameDetails(fight);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1721),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLive ? const Color(0xFFFFC400) : const Color(0xFF293946),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _statusBadge(fight.status),
                const Spacer(),
                if (fight.weightClass != null && fight.weightClass!.isNotEmpty)
                  Text(
                    fight.weightClass!.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF96A4B2),
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _fighterColumn(
                    name: fight.fighterOne ?? 'Fighter 1',
                    imageUrl: fight.fighterOneImage,
                    winner: fight.winner,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      color: Color(0xFFFFC400),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: _fighterColumn(
                    name: fight.fighterTwo ?? 'Fighter 2',
                    imageUrl: fight.fighterTwoImage,
                    winner: fight.winner,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (isFinal)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF111E28),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF293946)),
                ),
                child: Column(
                  children: [
                    Text(
                      fight.winner == null || fight.winner!.isEmpty
                          ? 'RESULT FINAL'
                          : '${fight.winner} WINS',
                      style: const TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                            fight.method,
                            fight.round == null ? null : 'ROUND ${fight.round}',
                            fight.time,
                          ]
                          .where(
                            (value) =>
                                value != null && value.toString().isNotEmpty,
                          )
                          .join(' • '),
                      style: const TextStyle(
                        color: Color(0xFF96A4B2),
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  const Text(
                    'FIGHT CARD',
                    style: TextStyle(color: Color(0xFF96A4B2), fontSize: 8),
                  ),
                  const Spacer(),
                  Text(
                    _gameTimeLabel(fight),
                    style: const TextStyle(
                      color: Color(0xFFFFC400),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _fighterColumn({
    required String name,
    required String? imageUrl,
    required String? winner,
  }) {
    final isWinner =
        winner != null &&
        winner.trim().toLowerCase() == name.trim().toLowerCase();
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isWinner
                  ? const Color(0xFF59E769)
                  : const Color(0xFFFFC400),
              width: isWinner ? 2 : 1,
            ),
          ),
          child: ClipOval(
            child: imageUrl == null || imageUrl.trim().isEmpty
                ? Container(
                    color: const Color(0xFF111D27),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.sports_mma,
                      color: Color(0xFF9A6338),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    memCacheWidth: 104,
                    memCacheHeight: 104,
                    placeholder: (context, url) {
                      return Container(
                        color: const Color(0xFF111D27),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.sports_mma,
                          color: Color(0xFF9A6338),
                        ),
                      );
                    },
                    errorWidget: (context, url, error) {
                      return Container(
                        color: const Color(0xFF111D27),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.sports_mma,
                          color: Color(0xFF9A6338),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isWinner ? const Color(0xFF59E769) : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (isWinner) ...[
          const SizedBox(height: 3),
          const Icon(Icons.emoji_events, color: Color(0xFFFFC400), size: 13),
        ],
      ],
    );
  }

  Widget _teamLogo({required String? imageUrl, required String team}) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      return _teamInitialLogo(team);
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 28,
        height: 28,
        fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        memCacheWidth: 56,
        memCacheHeight: 56,
        placeholder: (context, url) {
          return _teamInitialLogo(team);
        },
        errorWidget: (context, url, error) {
          return _teamInitialLogo(team);
        },
      ),
    );
  }

  Widget _teamInitialLogo(String team) {
    final initial = team.trim().isEmpty ? '?' : team.trim()[0].toUpperCase();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF142430),
        border: Border.all(color: const Color(0xFF293946)),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFFFFC400),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _teamScoreRow({
    required String team,
    required int? score,
    required String? logo,
  }) {
    return Row(
      children: [
        _teamLogo(imageUrl: logo, team: team),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          score?.toString() ?? '-',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    switch (status) {
      case 'LIVE':
        color = const Color(0xFF59E769);
        break;
      case 'FINAL':
        color = const Color(0xFF96A4B2);
        break;
      default:
        color = const Color(0xFFFFC400);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _previousDay() async {
    await _controller.previousDay();
  }

  Future<void> _nextDay() async {
    await _controller.nextDay();
  }

  Future<void> _refreshScores() async {
    await _controller.load(silent: true);
  }

  String _gameTimeLabel(ScoreboardGame game) {
    final sharedDisplayTime = game.displayTime?.trim() ?? '';
    if (sharedDisplayTime.isNotEmpty) {
      return sharedDisplayTime;
    }
    final start = game.startTime?.toLocal();
    if (start == null) {
      return game.status;
    }
    final hour = start.hour == 0
        ? 12
        : start.hour > 12
        ? start.hour - 12
        : start.hour;
    final minute = start.minute.toString().padLeft(2, '0');
    final period = start.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  void _openGameDetails(ScoreboardGame game) {
    debugPrint('Open ${game.awayTeam} vs ${game.homeTeam}');
  }
}
