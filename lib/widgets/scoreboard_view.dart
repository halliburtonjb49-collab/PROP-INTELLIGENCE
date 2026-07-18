import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/scoreboard_controller.dart';
import '../models/scoreboard_game.dart';
import '../services/api_service.dart';
import '../services/scoreboard_service.dart';

class LiveScoreboardTickerGridWidget extends StatefulWidget {
  const LiveScoreboardTickerGridWidget({super.key});

  @override
  State<LiveScoreboardTickerGridWidget> createState() =>
      _LiveScoreboardTickerGridWidgetState();
}

class _LiveScoreboardTickerGridWidgetState
    extends State<LiveScoreboardTickerGridWidget> {
  static const _background = Color(0xFF030A10);
  static const _panel = Color(0xFF071520);
  static const _panelRaised = Color(0xFF091A26);
  static const _border = Color(0xFF263A48);
  static const _borderSoft = Color(0xFF172A36);
  static const _gold = Color(0xFFFFC400);
  static const _white = Color(0xFFF7F8FA);
  static const _silver = Color(0xFFA4B1BB);
  static const _muted = Color(0xFF71818D);
  static const _green = Color(0xFF36B9FF);

  late final ScoreboardController _controller;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _watchedGameIds = <String>{};
  String _selectedTab = 'ALL GAMES';
  String _selectedSport = 'ALL SPORTS';
  bool _autoRefresh = true;

  @override
  void initState() {
    super.initState();
    _controller = ScoreboardController(
      service: ScoreboardService(baseUrl: ApiService.baseUrl),
    );
    _controller.addListener(_handleControllerUpdate);
    unawaited(_controller.load());
    _controller.beginLiveRefresh();
  }

  void _handleControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ScoreboardGame> get _sportGames {
    if (_selectedSport == 'ALL SPORTS') return _controller.games;
    return _controller.games
        .where((game) {
          final sport = game.sport.toUpperCase();
          final league = game.league.toUpperCase();
          return sport == _selectedSport || league == _selectedSport;
        })
        .toList(growable: false);
  }

  List<ScoreboardGame> get _visibleGames {
    final games = _sportGames;
    return switch (_selectedTab) {
      'LIVE NOW' => games.where((game) => game.isLive).toList(),
      'UPCOMING' => games.where((game) => game.isUpcoming).toList(),
      'FINAL' => games.where((game) => game.isFinal).toList(),
      _ => games,
    };
  }

  String _formatDate(DateTime value) {
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
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _gameTime(ScoreboardGame game) {
    if ((game.displayTime ?? '').trim().isNotEmpty) return game.displayTime!;
    final value = game.startTime?.toLocal();
    if (value == null) return game.detail.isEmpty ? 'Scheduled' : game.detail;
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _awayLabel(ScoreboardGame game) => game.isUfc
      ? ((game.fighterOne ?? '').isEmpty ? 'Fighter A' : game.fighterOne!)
      : game.awayTeam;

  String _homeLabel(ScoreboardGame game) => game.isUfc
      ? ((game.fighterTwo ?? '').isEmpty ? 'Fighter B' : game.fighterTwo!)
      : game.homeTeam;

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _controller.selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _gold,
            onPrimary: Colors.black,
            surface: _panel,
          ),
        ),
        child: child!,
      ),
    );
    if (selected == null) return;
    await _controller.selectDate(selected);
  }

  void _toggleAutoRefresh(bool enabled) {
    setState(() => _autoRefresh = enabled);
    if (enabled) {
      _controller.beginLiveRefresh();
      unawaited(_controller.load(silent: true));
    } else {
      _controller.stopLiveRefresh();
    }
  }

  void _watchGame(ScoreboardGame game) {
    setState(() {
      if (!_watchedGameIds.add(game.id)) _watchedGameIds.remove(game.id);
    });
    final watched = _watchedGameIds.contains(game.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: watched ? _gold : _panelRaised,
        content: Text(
          watched
              ? 'Game added to Active Watchlist.'
              : 'Game removed from Active Watchlist.',
          style: TextStyle(
            color: watched ? Colors.black : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _background,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final liveCount = _sportGames.where((game) => game.isLive).length;
    final tabs = <String>['ALL GAMES', 'LIVE NOW', 'UPCOMING', 'FINAL'];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCOREBOARD',
                      style: TextStyle(
                        color: _white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Real-time scores, stats & game status',
                      style: TextStyle(color: _silver, fontSize: 10),
                    ),
                  ],
                ),
              ),
              _outlineButton(
                icon: Icons.chevron_left,
                label: '',
                onPressed: () => unawaited(_controller.previousDay()),
                compact: true,
              ),
              const SizedBox(width: 5),
              _outlineButton(
                icon: Icons.calendar_month_outlined,
                label: _formatDate(_controller.selectedDate),
                onPressed: _pickDate,
              ),
              const SizedBox(width: 5),
              _outlineButton(
                icon: Icons.chevron_right,
                label: '',
                onPressed: () => unawaited(_controller.nextDay()),
                compact: true,
              ),
              const SizedBox(width: 7),
              _outlineButton(
                icon: _controller.isRefreshing ? Icons.sync : Icons.refresh,
                label: 'REFRESH',
                onPressed: _controller.isRefreshing
                    ? null
                    : () => unawaited(_controller.load(silent: true)),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              for (final tab in tabs)
                InkWell(
                  onTap: () => setState(() => _selectedTab = tab),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(13, 8, 13, 9),
                    decoration: BoxDecoration(
                      color: _selectedTab == tab
                          ? _gold.withValues(alpha: .09)
                          : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: _selectedTab == tab
                              ? _gold
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      tab == 'LIVE NOW' ? 'LIVE NOW  $liveCount' : tab,
                      style: TextStyle(
                        color: _selectedTab == tab ? _gold : _silver,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              const Text(
                'Auto Refresh',
                style: TextStyle(color: _silver, fontSize: 9),
              ),
              const SizedBox(width: 5),
              Transform.scale(
                scale: .72,
                child: Switch(
                  value: _autoRefresh,
                  activeThumbColor: _gold,
                  activeTrackColor: const Color(0xFF1976D2),
                  onChanged: _toggleAutoRefresh,
                ),
              ),
              const Text(
                '● Live',
                style: TextStyle(
                  color: _green,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _outlineButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool compact = false,
  }) {
    return SizedBox(
      height: 34,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: compact ? const SizedBox.shrink() : Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _white,
          side: const BorderSide(color: _border),
          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
          textStyle: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading && _controller.games.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_controller.errorMessage != null && _controller.games.isEmpty) {
      return _messageState(
        Icons.cloud_off_outlined,
        _controller.errorMessage!,
        action: () => unawaited(_controller.load()),
      );
    }

    final visible = _visibleGames;
    final live = visible.where((game) => game.isLive).toList();
    final upcoming = visible.where((game) => game.isUpcoming).toList();
    final finalGames = visible.where((game) => game.isFinal).toList();

    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: const WidgetStatePropertyAll(_gold),
        trackColor: WidgetStatePropertyAll(_gold.withValues(alpha: .10)),
        trackBorderColor: const WidgetStatePropertyAll(_border),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
      ),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(18, 12, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSportFilters(),
              const SizedBox(height: 16),
              if (visible.isEmpty)
                _messageState(
                  Icons.sports_score,
                  'No games match these filters.',
                )
              else ...[
                if (live.isNotEmpty) _buildLiveSection(live),
                if (upcoming.isNotEmpty) _buildUpcomingSection(upcoming),
                if (finalGames.isNotEmpty) _buildFinalSection(finalGames),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSportFilters() {
    const preferred = [
      'ALL SPORTS',
      'NBA',
      'WNBA',
      'NFL',
      'MLB',
      'NHL',
      'SOCCER',
      'TENNIS',
      'PGA',
      'UFC',
    ];
    int countFor(String sport) => sport == 'ALL SPORTS'
        ? _controller.games.length
        : _controller.games.where((game) {
            return game.sport.toUpperCase() == sport ||
                game.league.toUpperCase() == sport;
          }).length;
    IconData iconFor(String sport) => switch (sport) {
      'NBA' || 'WNBA' => Icons.sports_basketball,
      'NFL' => Icons.sports_football,
      'MLB' => Icons.sports_baseball,
      'NHL' => Icons.sports_hockey,
      'SOCCER' => Icons.sports_soccer,
      'TENNIS' => Icons.sports_tennis,
      'PGA' => Icons.sports_golf,
      'UFC' => Icons.sports_mma,
      _ => Icons.apps_rounded,
    };
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: preferred.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final sport = preferred[index];
          final selected = sport == _selectedSport;
          return OutlinedButton(
            onPressed: () => setState(() => _selectedSport = sport),
            style: OutlinedButton.styleFrom(
              foregroundColor: selected ? _gold : _white,
              backgroundColor: selected ? _gold.withValues(alpha: .09) : _panel,
              side: BorderSide(color: selected ? _gold : _border),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconFor(sport), size: 14),
                const SizedBox(width: 6),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      sport,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${countFor(sport)}',
                      style: const TextStyle(color: _muted, fontSize: 7),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, color: _gold, size: 15),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(
              color: _white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 7),
          Text('$count', style: const TextStyle(color: _muted, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildLiveSection(List<ScoreboardGame> games) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.radio_button_checked, 'LIVE NOW', games.length),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 620
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: games.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                  mainAxisExtent: 160,
                ),
                itemBuilder: (context, index) => _liveCard(games[index]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _liveCard(ScoreboardGame game) {
    final awayScore = game.awayScore ?? 0;
    final homeScore = game.homeScore ?? 0;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _gold.withValues(alpha: .55)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                game.league,
                style: const TextStyle(
                  color: _white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  game.detail,
                  style: const TextStyle(
                    color: _green,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _watchIcon(game),
            ],
          ),
          const SizedBox(height: 8),
          _scoreRow(_awayLabel(game), awayScore, awayScore >= homeScore),
          const SizedBox(height: 7),
          _scoreRow(_homeLabel(game), homeScore, homeScore >= awayScore),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: const LinearProgressIndicator(
              value: .55,
              minHeight: 5,
              color: _green,
              backgroundColor: _border,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreRow(String team, int score, bool leading) {
    return Row(
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: _panelRaised,
            shape: BoxShape.circle,
          ),
          child: Text(
            _initials(team),
            style: const TextStyle(
              color: _gold,
              fontSize: 7,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: leading ? _white : _silver,
              fontSize: 9,
              fontWeight: leading ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          '$score',
          style: TextStyle(
            color: leading ? _gold : _silver,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingSection(List<ScoreboardGame> games) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.calendar_today_outlined,
            'UPCOMING GAMES',
            games.length,
          ),
          Container(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _borderSoft),
            ),
            child: Column(
              children: [
                _upcomingHeader(),
                for (var index = 0; index < games.length; index++)
                  _upcomingRow(games[index], index),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              'TIME',
              style: TextStyle(
                color: _muted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'MATCHUP',
              style: TextStyle(
                color: _muted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'LEAGUE',
              style: TextStyle(
                color: _muted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'STATUS',
              style: TextStyle(
                color: _muted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              'WATCH',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _muted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingRow(ScoreboardGame game, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: index.isOdd ? _panelRaised : _panel,
        border: const Border(top: BorderSide(color: _borderSoft)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              _gameTime(game),
              style: const TextStyle(color: _white, fontSize: 8),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '${_awayLabel(game)}  @  ${_homeLabel(game)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _white,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              game.league,
              style: const TextStyle(color: _silver, fontSize: 8),
            ),
          ),
          Expanded(
            child: Text(
              game.detail.isEmpty ? 'Upcoming' : game.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _gold, fontSize: 8),
            ),
          ),
          SizedBox(
            width: 76,
            height: 27,
            child: OutlinedButton(
              onPressed: () => _watchGame(game),
              style: OutlinedButton.styleFrom(
                foregroundColor: _watchedGameIds.contains(game.id)
                    ? _gold
                    : _white,
                side: BorderSide(
                  color: _watchedGameIds.contains(game.id) ? _gold : _border,
                ),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                _watchedGameIds.contains(game.id) ? 'WATCHING' : 'WATCH',
                style: const TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalSection(List<ScoreboardGame> games) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.verified_outlined, 'FINAL GAMES', games.length),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850
                ? 4
                : constraints.maxWidth >= 560
                ? 3
                : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: games.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                mainAxisExtent: 125,
              ),
              itemBuilder: (context, index) => _finalCard(games[index]),
            );
          },
        ),
      ],
    );
  }

  Widget _finalCard(ScoreboardGame game) {
    final awayScore = game.awayScore ?? 0;
    final homeScore = game.homeScore ?? 0;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _borderSoft),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'FINAL',
                style: TextStyle(
                  color: _muted,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                game.league,
                style: const TextStyle(color: _muted, fontSize: 7),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _finalScoreRow(_awayLabel(game), awayScore, awayScore > homeScore),
          const SizedBox(height: 6),
          _finalScoreRow(_homeLabel(game), homeScore, homeScore > awayScore),
        ],
      ),
    );
  }

  Widget _finalScoreRow(String team, int score, bool winner) {
    return Row(
      children: [
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: winner ? _white : _silver,
              fontSize: 8.5,
              fontWeight: winner ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          '$score',
          style: TextStyle(
            color: winner ? _gold : _silver,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _watchIcon(ScoreboardGame game) {
    final watched = _watchedGameIds.contains(game.id);
    return InkWell(
      onTap: () => _watchGame(game),
      child: Icon(
        watched ? Icons.star : Icons.star_border,
        color: _gold,
        size: 16,
      ),
    );
  }

  Widget _messageState(IconData icon, String message, {VoidCallback? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _gold, size: 34),
              const SizedBox(height: 10),
              Text(
                message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _silver, fontSize: 10),
              ),
              if (action != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: action, child: const Text('RETRY')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return '${words[words.length - 2][0]}${words.last[0]}'.toUpperCase();
    }
    return value.length >= 2
        ? value.substring(0, 2).toUpperCase()
        : value.toUpperCase();
  }
}
