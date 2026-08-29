import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/scoreboard_controller.dart';
import '../models/scoreboard_game.dart';
import '../services/app_sound_service.dart';
import '../services/scoreboard_preferences_service.dart';
import '../services/scoreboard_watchlist_service.dart';
import '../theme/app_colors.dart';

class ScoreboardNavigationRibbon extends StatefulWidget {
  const ScoreboardNavigationRibbon({
    super.key,
    required this.controller,
    required this.expanded,
    required this.selectedSport,
    required this.accentColor,
    required this.soundService,
    required this.onExpandedChanged,
    required this.onSportSelected,
    required this.onOpenScoreboard,
    required this.onOpenGameMarkets,
    this.onOpenOwnerOperations,
  });

  final ScoreboardController controller;
  final bool expanded;
  final String selectedSport;
  final Color accentColor;
  final AppSoundService soundService;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<String> onSportSelected;
  final VoidCallback onOpenScoreboard;
  final VoidCallback onOpenGameMarkets;
  final VoidCallback? onOpenOwnerOperations;

  @override
  State<ScoreboardNavigationRibbon> createState() =>
      _ScoreboardNavigationRibbonState();
}

class _ScoreboardNavigationRibbonState
    extends State<ScoreboardNavigationRibbon> {
  static const _visibleScoreboardSports = <String>{
    'MLB',
    'NFL',
    'NBA',
    'WNBA',
    'NHL',
    'SOCCER',
    'MLS',
    'EPL',
    'NCAAF',
    'NCAAB',
    'CFL',
  };

  static const _sports = <String>[
    'MLB',
    'NFL',
    'NBA',
    'WNBA',
    'NHL',
    'SOCCER',
    'NCAAF',
    'NCAAB',
    'CFL',
  ];
  final _preferences = ScoreboardPreferencesService();
  final _watchlist = ScoreboardWatchlistService.instance;
  Timer? _rotationTimer;
  Timer? _manualPauseTimer;
  int _page = 0;
  String _tab = 'LIVE NOW';
  bool _autoRotate = true;
  bool _hovered = false;
  bool _manualPaused = false;
  Set<String> _favoriteSports = <String>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updated);
    _watchlist.watchedIds.addListener(_updated);
    unawaited(_loadPreferences());
    unawaited(_watchlist.load());
    _startRotation();
  }

  Future<void> _loadPreferences() async {
    final values = await Future.wait<Object>([
      _preferences.autoRotate(),
      _preferences.expanded(),
      _preferences.favoriteSports(),
    ]);
    if (!mounted) return;
    final storedExpanded = values[1] as bool;
    setState(() {
      _autoRotate = values[0] as bool;
      _favoriteSports = values[2] as Set<String>;
    });
    if (storedExpanded != widget.expanded) {
      widget.onExpandedChanged(storedExpanded);
    }
    _startRotation();
  }

  void _updated() {
    if (mounted) setState(() {});
  }

  void _startRotation() {
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_autoRotate || _hovered || _manualPaused) return;
      _movePage(1, manual: false);
    });
  }

  void _movePage(int delta, {bool manual = true}) {
    final pageCount = _pageCount(_orderedGames, _cardsPerPage(context));
    if (pageCount <= 1) return;
    setState(() => _page = (_page + delta) % pageCount);
    if (_page < 0) _page = pageCount - 1;
    if (manual) {
      _manualPauseTimer?.cancel();
      setState(() => _manualPaused = true);
      _manualPauseTimer = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _manualPaused = false);
      });
    }
  }

  List<ScoreboardGame> get _orderedGames {
    final seen = <String>{};
    final games = widget.controller.games.where((game) {
      final sport = game.sport.trim().toUpperCase();
      final league = game.league.trim().toUpperCase();
      if (!_visibleScoreboardSports.contains(sport) &&
          !_visibleScoreboardSports.contains(league)) {
        return false;
      }
      if (game.id.trim().isEmpty ||
          game.awayTeam.trim().isEmpty ||
          game.homeTeam.trim().isEmpty) {
        return false;
      }
      return seen.add(game.id);
    }).toList();
    int rank(ScoreboardGame game) {
      final watched = _watchlist.isWatching(game.id);
      if (game.isLive && watched) return 0;
      if (game.isLive) return 1;
      if (game.isUpcoming && watched) return 2;
      if (_favoriteSports.contains(game.sport.toUpperCase())) return 3;
      if (game.isUpcoming) return 4;
      return 5;
    }

    games.sort((a, b) {
      final status = rank(a).compareTo(rank(b));
      if (status != 0) return status;
      return (a.startTime ?? DateTime(2100)).compareTo(
        b.startTime ?? DateTime(2100),
      );
    });
    return switch (_tab) {
      'LIVE NOW' => [
        ...games.where((g) => g.isLive),
        ...games.where((g) => g.isUpcoming),
      ],
      'MY SPORTS' =>
        games
            .where(
              (g) =>
                  _favoriteSports.contains(g.sport.toUpperCase()) ||
                  _watchlist.isWatching(g.id),
            )
            .toList(),
      'UPCOMING' => games.where((g) => g.isUpcoming).toList(),
      'FINAL' => games.where((g) => g.isFinal).toList(),
      _ => games,
    };
  }

  int _cardsPerPage(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1650) return 6;
    if (width >= 1350) return 5;
    if (width >= 1000) return 4;
    return 3;
  }

  int _pageCount(List<ScoreboardGame> games, int perPage) =>
      math.max(1, (games.length / perPage).ceil());

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _manualPauseTimer?.cancel();
    widget.controller.removeListener(_updated);
    _watchlist.watchedIds.removeListener(_updated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final games = _orderedGames;
    final perPage = _cardsPerPage(context);
    final pages = _pageCount(games, perPage);
    if (_page >= pages) _page = pages - 1;
    final start = math.min(_page * perPage, games.length);
    final visible = games.skip(start).take(perPage).toList();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        color: AppColors.surfacePrimary,
        padding: EdgeInsets.fromLTRB(10, widget.expanded ? 6 : 4, 10, 4),
        child: Column(
          children: [
            _header(games),
            if (widget.expanded) ...[
              const SizedBox(height: 4),
              Expanded(child: _gameRow(visible, pages)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(List<ScoreboardGame> games) {
    final liveCount = widget.controller.games.where((g) => g.isLive).length;
    return Row(
      children: [
        TextButton.icon(
          key: const ValueKey('scoreboard-ribbon-title'),
          onPressed: widget.onOpenScoreboard,
          icon: Icon(Icons.sports_score_rounded, color: widget.accentColor),
          label: const Text('SCOREBOARD'),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.circle, size: 7, color: AppColors.informational),
        const SizedBox(width: 4),
        const Text(
          'REAL-TIME',
          style: TextStyle(
            color: AppColors.informational,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (widget.expanded) ...[
          const SizedBox(width: 8),
          for (final tab in ['LIVE NOW', 'MY SPORTS', 'UPCOMING', 'FINAL'])
            _tabButton(tab, tab == 'LIVE NOW' ? liveCount : null),
        ],
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'Select market sport',
          onSelected: (sport) {
            widget.onSportSelected(sport);
            final next = {..._favoriteSports, sport};
            setState(() => _favoriteSports = next);
            unawaited(_preferences.setFavoriteSports(next));
          },
          itemBuilder: (_) => _sports
              .map((sport) => PopupMenuItem(value: sport, child: Text(sport)))
              .toList(),
          child: _compactAction(Icons.tune_rounded, widget.selectedSport),
        ),
        const SizedBox(width: 5),
        InkWell(
          onTap: widget.onOpenGameMarkets,
          child: _compactAction(Icons.sports_rounded, 'MARKETS'),
        ),
        if (widget.onOpenOwnerOperations != null) ...[
          const SizedBox(width: 5),
          IconButton(
            tooltip: 'Owner Operations',
            onPressed: widget.onOpenOwnerOperations,
            icon: Icon(
              Icons.admin_panel_settings_outlined,
              color: widget.accentColor,
              size: 19,
            ),
          ),
        ],
        if (widget.expanded)
          Row(
            children: [
              const Text('AUTO', style: TextStyle(fontSize: 9)),
              Switch(
                value: _autoRotate,
                onChanged: (value) {
                  setState(() => _autoRotate = value);
                  unawaited(_preferences.setAutoRotate(value));
                },
              ),
            ],
          ),
        AnimatedBuilder(
          animation: widget.soundService,
          builder: (_, child) => IconButton(
            tooltip: widget.soundService.enabled
                ? 'Mute sound'
                : 'Enable sound',
            onPressed: () => unawaited(
              widget.soundService.setEnabled(!widget.soundService.enabled),
            ),
            icon: Icon(
              widget.soundService.enabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              color: widget.accentColor,
            ),
          ),
        ),
        IconButton(
          tooltip: widget.expanded
              ? 'Collapse scoreboard'
              : 'Expand scoreboard',
          onPressed: () {
            final next = !widget.expanded;
            widget.onExpandedChanged(next);
            unawaited(_preferences.setExpanded(next));
          },
          icon: Icon(
            widget.expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
          ),
        ),
      ],
    );
  }

  Widget _tabButton(String tab, int? count) => TextButton(
    onPressed: () => setState(() {
      _tab = tab;
      _page = 0;
    }),
    style: TextButton.styleFrom(
      foregroundColor: _tab == tab ? widget.accentColor : AppColors.coreSilver,
      padding: const EdgeInsets.symmetric(horizontal: 7),
    ),
    child: Text(
      count == null ? tab : '$tab $count',
      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
    ),
  );

  Widget _compactAction(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: widget.accentColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _gameRow(List<ScoreboardGame> games, int pages) {
    if (widget.controller.isLoading && games.isEmpty) {
      return const _ScoreboardLoadingSequence();
    }
    if (games.isEmpty) {
      return Center(
        child: Text(
          widget.controller.errorMessage ??
              'No ${_tab.toLowerCase()} games available.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Row(
      children: [
        IconButton(
          onPressed: () => _movePage(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (details) =>
                _movePage((details.primaryVelocity ?? 0) < 0 ? 1 : -1),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slots = _cardsPerPage(context);
                final cardWidth =
                    (constraints.maxWidth - ((slots - 1) * 6)) / slots;
                return Row(
                  children: [
                    for (var i = 0; i < games.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      SizedBox(
                        width: cardWidth,
                        child: _GameRibbonCard(
                          game: games[i],
                          accentColor: widget.accentColor,
                          watched: _watchlist.isWatching(games[i].id),
                          onOpen: widget.onOpenScoreboard,
                          onSport: () =>
                              widget.onSportSelected(games[i].sport),
                          onWatch: () =>
                              unawaited(_watchlist.toggle(games[i])),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        IconButton(
          onPressed: () => _movePage(1),
          icon: const Icon(Icons.chevron_right),
        ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              '${_page + 1}/$pages',
              style: const TextStyle(fontSize: 8),
            ),
          ),
      ],
    );
  }
}

class _ScoreboardLoadingSequence extends StatefulWidget {
  const _ScoreboardLoadingSequence();

  @override
  State<_ScoreboardLoadingSequence> createState() =>
      _ScoreboardLoadingSequenceState();
}

class _ScoreboardLoadingSequenceState extends State<_ScoreboardLoadingSequence>
    with SingleTickerProviderStateMixin {
  static const _stages = <String>[
    'SYNCING LIVE SCORES',
    'RESOLVING OFFICIAL TEAM LOGOS',
    'ORGANIZING LIVE & UPCOMING GAMES',
  ];

  late final AnimationController _scan;
  Timer? _stageTimer;
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted) setState(() => _stage = (_stage + 1) % _stages.length);
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Prop Intelligence scoreboard loading. ${_stages[_stage]}',
    child: Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B2230), Color(0xFF071722), Color(0xFF040D14)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.62)),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _scan,
            builder: (context, child) => Align(
              alignment: Alignment((_scan.value * 2) - 1, 0),
              child: child,
            ),
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: AppColors.goldHighlight,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfacePrimary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.gold),
                  ),
                  child: Image.asset(
                    'assets/branding/Prop_Intelligence_Master_Logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stackTrace) => const Center(
                      child: Text(
                        'PI',
                        style: TextStyle(
                          color: AppColors.goldHighlight,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PROP INTELLIGENCE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _stages[_stage],
                        key: ValueKey(_stage),
                        style: const TextStyle(
                          color: AppColors.goldHighlight,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _GameRibbonCard extends StatelessWidget {
  const _GameRibbonCard({
    required this.game,
    required this.accentColor,
    required this.watched,
    required this.onOpen,
    required this.onSport,
    required this.onWatch,
  });
  final ScoreboardGame game;
  final Color accentColor;
  final bool watched;
  final VoidCallback onOpen;
  final VoidCallback onSport;
  final VoidCallback onWatch;

  String _abbr(String team, String? logo) {
    final logoMatch = RegExp(
      r'/([a-z]{2,4})\.(?:png|svg)(?:\?|$)',
      caseSensitive: false,
    ).firstMatch(logo ?? '');
    if (logoMatch != null) return logoMatch.group(1)!.toUpperCase();
    final words = team.trim().split(RegExp(r'\s+'));
    if (words.length == 1) {
      return team.substring(0, math.min(3, team.length)).toUpperCase();
    }
    if (words.length == 2 && words.first.length <= 3) {
      return words.first.toUpperCase();
    }
    return words.map((w) => w[0]).take(3).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final awayLeading = (game.awayScore ?? -1) > (game.homeScore ?? -1);
    final homeLeading = (game.homeScore ?? -1) > (game.awayScore ?? -1);
    final footer = [
      game.isUpcoming
          ? (game.displayTime?.trim() ?? game.detail.trim())
          : game.detail.trim(),
      game.broadcast?.trim() ?? '',
    ].where((value) => value.isNotEmpty).join(' • ');
    return Material(
      color: AppColors.surfaceSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: game.isLive
              ? AppColors.destructive.withValues(alpha: 0.48)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: onSport,
                    child: Text(
                      game.league.isEmpty ? game.sport : game.league,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _statusBadge(),
                  const SizedBox(width: 3),
                  InkWell(
                    onTap: onWatch,
                    child: Icon(
                      watched ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 16,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _team(
                game.awayLogo,
                _abbr(game.awayTeam, game.awayLogo),
                game.awayScore,
                awayLeading,
              ),
              const SizedBox(height: 1),
              _team(
                game.homeLogo,
                _abbr(game.homeTeam, game.homeLogo),
                game.homeScore,
                homeLeading,
              ),
              const Spacer(),
              Row(
                children: [
                  if (game.isLive) ...[
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.destructive,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      footer.isEmpty
                          ? (game.displayTime ?? game.status)
                          : footer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge() {
    final label = game.isLive
        ? 'LIVE'
        : game.isFinal
        ? 'FINAL'
        : 'UPCOMING';
    final color = game.isLive
        ? AppColors.destructive
        : game.isFinal
        ? const Color(0xFF50E3A4)
        : accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  Widget _team(String? logo, String name, int? score, bool leading) => Row(
    children: [
      SizedBox(
        width: 28,
        height: 28,
        child: logo != null && logo.isNotEmpty
            ? Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: Image.network(
                  logo,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, error, stackTrace) =>
                      _teamBadge(name),
                ),
              )
            : _teamBadge(name),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          name,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
      Text(
        score?.toString() ?? '',
        style: TextStyle(
          color: leading ? accentColor : AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );

  Widget _teamBadge(String abbreviation) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: accentColor.withValues(alpha: 0.12),
      shape: BoxShape.circle,
      border: Border.all(color: accentColor.withValues(alpha: 0.48)),
    ),
    child: Text(
      abbreviation,
      maxLines: 1,
      style: TextStyle(
        color: accentColor,
        fontSize: abbreviation.length > 3 ? 7 : 8,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}
