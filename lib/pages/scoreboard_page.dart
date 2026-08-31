import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/scoreboard_controller.dart';
import '../models/scoreboard_game.dart';
import '../services/api_service.dart';
import '../services/scoreboard_service.dart';
import '../services/player_image_resolver.dart';
import '../theme/app_colors.dart';
import '../widgets/context_help.dart';
import '../widgets/player_image_widget.dart';

import '../theme/app_colors.dart' as brand_colors;

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
      color: AppColors.background,
      child: Column(
        children: [
          _buildHeader(),
          _buildFilterRow(),
          const Divider(height: 1, color: brand_colors.AppColors.chromeShadow),
          Expanded(child: _buildScoreboardBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    const sportLabel =
        'Games and live scores across all sports for the selected date';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sportLabel,
                  style: TextStyle(
                    color: brand_colors.AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const ContextHelp(
            title: 'Live scoreboard',
            message:
                'Scores and game status refresh automatically while live updates are connected. Use the date controls to review other slates. Prop-site settlement rules can differ from unofficial live statistics.',
          ),
          IconButton(
            onPressed: _previousDay,
            icon: const Icon(Icons.chevron_left, color: Colors.white),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: brand_colors.AppColors.bgPanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: brand_colors.AppColors.goldShadow),
            ),
            child: Text(
              _formatDate(_controller.selectedDate),
              style: const TextStyle(
                color: brand_colors.AppColors.gold,
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
                      color: brand_colors.AppColors.gold,
                    ),
                  )
                : const Icon(Icons.refresh, color: brand_colors.AppColors.gold),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? brand_colors.AppColors.gold
              : brand_colors.AppColors.bgPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? brand_colors.AppColors.gold
                : brand_colors.AppColors.chromeShadow,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? brand_colors.AppColors.bgBase : Colors.white,
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
        child: CircularProgressIndicator(color: brand_colors.AppColors.gold),
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
                color: brand_colors.AppColors.danger,
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
                style: const TextStyle(
                  color: brand_colors.AppColors.textSecondary,
                  fontSize: 9,
                ),
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
            Icon(
              Icons.event_busy_outlined,
              color: brand_colors.AppColors.textSecondary,
              size: 32,
            ),
            SizedBox(height: 10),
            Text(
              'NO GAMES FOUND',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 4),
            Text('Try another date or filter.'),
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
      color: brand_colors.AppColors.gold,
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
                color: brand_colors.AppColors.bgPanel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brand_colors.AppColors.goldShadow),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: brand_colors.AppColors.gold,
                    size: 16,
                  ),
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
                style: const TextStyle(
                  color: brand_colors.AppColors.textSecondary,
                  fontSize: 8,
                ),
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
          color: brand_colors.AppColors.gold,
          size: 18,
        );
      case 'NFL':
        return const Icon(
          Icons.sports_football,
          color: brand_colors.AppColors.gold,
          size: 18,
        );
      case 'MLB':
        return const Icon(
          Icons.sports_baseball,
          color: brand_colors.AppColors.gold,
          size: 18,
        );
      case 'SOCCER':
        return const Icon(
          Icons.sports_soccer,
          color: brand_colors.AppColors.gold,
          size: 18,
        );
      case 'TENNIS':
        return const Icon(
          Icons.sports_tennis,
          color: brand_colors.AppColors.gold,
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
        return const Icon(
          Icons.sports,
          color: brand_colors.AppColors.textSecondary,
          size: 18,
        );
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
            color: isLive
                ? brand_colors.AppColors.gold
                : brand_colors.AppColors.chromeShadow,
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
                        ? brand_colors.AppColors.gold
                        : brand_colors.AppColors.textSecondary,
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
                  style: const TextStyle(
                    color: brand_colors.AppColors.textSecondary,
                    fontSize: 8,
                  ),
                ),
                const Spacer(),
                const Text(
                  'VIEW GAME',
                  style: TextStyle(
                    color: brand_colors.AppColors.gold,
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
            color: isLive
                ? brand_colors.AppColors.gold
                : brand_colors.AppColors.chromeShadow,
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
                      color: brand_colors.AppColors.textSecondary,
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
                      color: brand_colors.AppColors.gold,
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
                  border: Border.all(
                    color: brand_colors.AppColors.chromeShadow,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      fight.winner == null || fight.winner!.isEmpty
                          ? 'RESULT FINAL'
                          : '${fight.winner} WINS',
                      style: const TextStyle(
                        color: brand_colors.AppColors.gold,
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
                        color: brand_colors.AppColors.textSecondary,
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
                    style: TextStyle(
                      color: brand_colors.AppColors.textSecondary,
                      fontSize: 8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _gameTimeLabel(fight),
                    style: const TextStyle(
                      color: brand_colors.AppColors.gold,
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
                  ? brand_colors.AppColors.success
                  : brand_colors.AppColors.gold,
              width: isWinner ? 2 : 1,
            ),
          ),
          child: ClipOval(
            child: imageUrl == null || imageUrl.trim().isEmpty
                ? Container(
                    color: brand_colors.AppColors.bgPanel,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.sports_mma,
                      color: Color(0xFF9A6338),
                    ),
                  )
                : PlayerImageWidget(
                    imageUrl: imageUrl,
                    player: name,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.sports_mma,
                    fallbackIconSize: 25,
                    showShimmer: false,
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
            color: isWinner ? brand_colors.AppColors.success : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (isWinner) ...[
          const SizedBox(height: 3),
          const Icon(
            Icons.emoji_events,
            color: brand_colors.AppColors.gold,
            size: 13,
          ),
        ],
      ],
    );
  }

  Widget _teamLogo({required String? imageUrl, required String team}) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) {
      return _teamInitialLogo(team);
    }
    final resolvedUrl = resolvePlayerImagePath(
      url,
      useApiProxyForRemoteImages: kIsWeb,
    );
    return ClipOval(
      child: kIsWeb
          ? Image.network(
              resolvedUrl,
              width: 34,
              height: 34,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _teamInitialLogo(team),
              errorBuilder: (_, _, _) => _teamInitialLogo(team),
            )
          : CachedNetworkImage(
              imageUrl: resolvedUrl,
              width: 34,
              height: 34,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              memCacheWidth: 136,
              memCacheHeight: 136,
              placeholder: (_, _) => _teamInitialLogo(team),
              errorWidget: (_, _, _) => _teamInitialLogo(team),
            ),
    );
  }

  Widget _teamInitialLogo(String team) {
    final initial = team.trim().isEmpty ? '?' : team.trim()[0].toUpperCase();
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF142430),
        border: Border.all(color: brand_colors.AppColors.chromeShadow),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: brand_colors.AppColors.gold,
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
        color = brand_colors.AppColors.success;
        break;
      case 'FINAL':
        color = brand_colors.AppColors.textSecondary;
        break;
      default:
        color = brand_colors.AppColors.gold;
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
