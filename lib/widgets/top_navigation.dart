import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../services/app_sound_service.dart';
import '../services/auth_manager.dart';
import '../theme/app_colors.dart' as app_colors;
import 'feature_tier_badge.dart';

class TopNavigation extends StatelessWidget {
  final AppPage selectedPage;
  final ValueChanged<AppPage> onTabSelected;
  final AppSoundService soundService;
  final Color accentColor;
  final String selectedSport;
  final ValueChanged<String>? onSportSelected;

  const TopNavigation({
    super.key,
    required this.selectedPage,
    required this.onTabSelected,
    required this.soundService,
    required this.accentColor,
    this.selectedSport = 'ALL',
    this.onSportSelected,
  });

  static const _sports = [
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

  String get _pageHowTo => appPageHowTo(selectedPage);

  void _showPageHelp(BuildContext context) {
    unawaited(AppSoundService.instance.play(AppSoundEvent.selection));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: app_colors.AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: app_colors.AppColors.borderGold),
        ),
        title: Row(
          children: [
            const Icon(Icons.school_outlined, color: app_colors.AppColors.gold),
            const SizedBox(width: 10),
            Expanded(child: Text('HOW TO USE $_pageTitle')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            _pageHowTo,
            style: const TextStyle(
              color: app_colors.AppColors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  // Features grouped by what someone came to do, rather than the flat row of
  // eleven destinations this had become by adding one at a time. The order is
  // the order of a session: find something, build a slip from it, watch it,
  // then look back at how it went.
  /// One group of destinations, opened rather than crowded onto the bar.
  ///
  /// The group carries the highlight when the current page is inside it, so
  /// the bar still answers "where am I" without every page being visible at
  /// once -- which is what made the flat row unreadable on a phone.
  Widget _buildNavGroup(
    String label,
    IconData icon,
    List<(String, AppPage)> entries,
  ) {
    final holdsCurrentPage = entries.any((entry) => entry.$2 == selectedPage);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<AppPage>(
        key: ValueKey('nav-group-$label'),
        tooltip: label,
        color: app_colors.AppColors.sidebar,
        position: PopupMenuPosition.under,
        onSelected: onTabSelected,
        itemBuilder: (context) => [
          for (final (entryLabel, page) in entries)
            PopupMenuItem<AppPage>(
              key: ValueKey('nav-entry-${page.name}'),
              value: page,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entryLabel,
                      style: TextStyle(
                        color: page == selectedPage
                            ? accentColor
                            : app_colors.AppColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (requiredTierForPage(page) != null) ...[
                    const SizedBox(width: 8),
                    FeatureTierBadge(
                      tier: requiredTierForPage(page)!,
                      compact: true,
                      hasProUpgrade: true,
                    ),
                  ],
                ],
              ),
            ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(11, 15, 11, 13),
          decoration: BoxDecoration(
            color: holdsCurrentPage
                ? accentColor.withValues(alpha: .07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: holdsCurrentPage ? accentColor : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: holdsCurrentPage
                    ? accentColor
                    : app_colors.AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: holdsCurrentPage
                      ? accentColor
                      : app_colors.AppColors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.expand_more_rounded,
                size: 13,
                color: holdsCurrentPage
                    ? accentColor
                    : app_colors.AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSportsGroup() {
    final holdsCurrentPage =
        selectedPage == AppPage.gameMarkets ||
        (selectedPage == AppPage.board && selectedSport != 'ALL');

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<String>(
        key: const ValueKey('nav-group-SPORTS'),
        tooltip: 'Choose a sport or open game markets',
        color: app_colors.AppColors.sidebar,
        position: PopupMenuPosition.under,
        onSelected: (value) {
          if (value == 'GAME_MARKETS') {
            onTabSelected(AppPage.gameMarkets);
          } else {
            onSportSelected?.call(value);
          }
        },
        itemBuilder: (context) => [
          _sportsMenuItem(
            value: 'GAME_MARKETS',
            label: 'GAME MARKETS',
            icon: Icons.show_chart_rounded,
            selected: selectedPage == AppPage.gameMarkets,
          ),
          const PopupMenuDivider(),
          for (final sport in _sports)
            _sportsMenuItem(
              value: sport,
              label: sport,
              icon: _sportIcon(sport),
              selected: selectedPage == AppPage.board && selectedSport == sport,
            ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(11, 15, 11, 13),
          decoration: BoxDecoration(
            color: holdsCurrentPage
                ? accentColor.withValues(alpha: .07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: holdsCurrentPage ? accentColor : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sports_rounded,
                size: 16,
                color: holdsCurrentPage
                    ? accentColor
                    : app_colors.AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                selectedPage == AppPage.board && selectedSport != 'ALL'
                    ? selectedSport
                    : 'SPORTS',
                style: TextStyle(
                  color: holdsCurrentPage
                      ? accentColor
                      : app_colors.AppColors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.expand_more_rounded,
                size: 13,
                color: holdsCurrentPage
                    ? accentColor
                    : app_colors.AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVisibleSports() {
    return [
      KeyedSubtree(
        key: const ValueKey('nav-group-SPORTS'),
        child: _buildNavItem(
          label: 'SPORTS',
          page: AppPage.gameMarkets,
          icon: Icons.sports_rounded,
          requiredTier: SubscriptionTier.core,
        ),
      ),
      for (final sport in _sports) _buildVisibleSportItem(sport),
    ];
  }

  Widget _buildVisibleSportItem(String sport) {
    final selected = selectedPage == AppPage.board && selectedSport == sport;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: 'Show $sport props',
        child: InkWell(
          key: ValueKey('top-sport-$sport'),
          onTap: () => onSportSelected?.call(sport),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: selected
                  ? accentColor.withValues(alpha: .09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? accentColor : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _sportIcon(sport),
                  size: 15,
                  color: selected
                      ? accentColor
                      : app_colors.AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  sport,
                  style: TextStyle(
                    color: selected ? accentColor : app_colors.AppColors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _sportsMenuItem({
    required String value,
    required String label,
    required IconData icon,
    required bool selected,
  }) {
    return PopupMenuItem<String>(
      key: ValueKey('sports-entry-$value'),
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: selected ? accentColor : app_colors.AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: selected ? accentColor : app_colors.AppColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  IconData _sportIcon(String sport) => switch (sport) {
    'MLB' => Icons.sports_baseball_rounded,
    'NFL' || 'NCAAF' || 'CFL' => Icons.sports_football_rounded,
    'NBA' || 'WNBA' || 'NCAAB' => Icons.sports_basketball_rounded,
    'NHL' => Icons.sports_hockey_rounded,
    'SOCCER' => Icons.sports_soccer_rounded,
    _ => Icons.sports_rounded,
  };

  Widget _buildNavItem({
    required String label,
    required AppPage page,
    required IconData icon,
    SubscriptionTier? requiredTier,
    bool hasProUpgrade = false,
  }) {
    final selected = selectedPage == page;

    return Tooltip(
      message: appPageTooltip(page, fallback: label),
      child: InkWell(
        onTap: () => onTabSelected(page),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(11, 15, 11, 13),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: .07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accentColor : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? accentColor
                    : app_colors.AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 30),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: selected ? accentColor : app_colors.AppColors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (requiredTier != null) ...[
                const SizedBox(width: 7),
                FeatureTierBadge(
                  tier: requiredTier,
                  compact: true,
                  hasProUpgrade: hasProUpgrade,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _pageTitle => appPageTitle(selectedPage);

  String get _pageSubtitle => appPageSubtitle(selectedPage);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showContext = constraints.maxWidth >= 1150;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              if (showContext) ...[
                Container(
                  width: 4,
                  height: 42,
                  decoration: BoxDecoration(
                    color: app_colors.AppColors.gold,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x88FFC400), blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Open instructions for $_pageTitle',
                  child: InkWell(
                    onTap: () => _showPageHelp(context),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 230,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _pageTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: app_colors.AppColors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: app_colors.AppColors.blue.withValues(
                                    alpha: .12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: app_colors.AppColors.blue.withValues(
                                      alpha: .55,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: app_colors.AppColors.blue,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.help_outline_rounded,
                                size: 14,
                                color: app_colors.AppColors.gold,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pageSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 42,
                  color: app_colors.AppColors.border,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _TopNavScroller(
                  children: [
                    for (final (label, icon, entries) in appNavigationGroups)
                      if (label == 'SPORTS')
                        ..._buildVisibleSports()
                      else
                        _buildNavGroup(label, icon, entries),
                    if (AuthManager.instance.sessionState.value.isOwner)
                      _buildNavItem(
                        label: 'OWNER OPS',
                        page: AppPage.ownerOperations,
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: soundService,
                builder: (context, _) => IconButton(
                  key: const ValueKey('global-sound-toggle'),
                  tooltip: soundService.enabled
                      ? 'Sound: Mouse Click — tap for Silent'
                      : 'Sound: Silent — tap for Mouse Click',
                  onPressed: () {
                    unawaited(soundService.setEnabled(!soundService.enabled));
                  },
                  style: IconButton.styleFrom(
                    foregroundColor: soundService.enabled
                        ? accentColor
                        : app_colors.AppColors.textMuted,
                    side: BorderSide(
                      color: soundService.enabled
                          ? accentColor.withValues(alpha: .7)
                          : app_colors.AppColors.border,
                    ),
                    backgroundColor: soundService.enabled
                        ? accentColor.withValues(alpha: .08)
                        : Colors.transparent,
                  ),
                  icon: Icon(
                    soundService.enabled
                        ? Icons.mouse_rounded
                        : Icons.volume_off_rounded,
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopNavScroller extends StatefulWidget {
  const _TopNavScroller({required this.children});

  final List<Widget> children;

  @override
  State<_TopNavScroller> createState() => _TopNavScrollerState();
}

class _TopNavScrollerState extends State<_TopNavScroller> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      key: const ValueKey('top-navigation-scrollbar'),
      controller: _controller,
      thumbVisibility: false,
      trackVisibility: false,
      interactive: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      thickness: 4,
      radius: const Radius.circular(99),
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
      ),
    );
  }
}
