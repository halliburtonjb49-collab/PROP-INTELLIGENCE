import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../services/auth_manager.dart';
import '../theme/app_colors.dart' as app_colors;
import 'feature_tier_badge.dart';

class TopNavigation extends StatelessWidget {
  final AppPage selectedPage;
  final ValueChanged<AppPage> onTabSelected;
  final Color accentColor;
  final String selectedSport;
  final ValueChanged<String>? onSportSelected;

  const TopNavigation({
    super.key,
    required this.selectedPage,
    required this.onTabSelected,
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
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: SingleChildScrollView(
            child: Text(
              _pageHowTo,
              style: const TextStyle(
                color: app_colors.AppColors.textSecondary,
                height: 1.55,
              ),
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

  List<Widget> _buildVisibleSports() {
    final session = AuthManager.instance.sessionState.value;
    final membershipLabel = session.isOwner
        ? 'OWNER'
        : session.hasEdgeAccess
        ? 'PRO'
        : null;
    return [
      KeyedSubtree(
        key: const ValueKey('nav-group-SPORTS'),
        child: _buildNavItem(
          label: 'ML SPORTS',
          page: AppPage.gameMarkets,
          icon: Icons.sports_rounded,
        ),
      ),
      if (membershipLabel != null)
        Container(
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withValues(alpha: .75)),
          ),
          child: Text(
            membershipLabel,
            style: TextStyle(
              color: accentColor,
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
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
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
                    color: selected ? accentColor : app_colors.AppColors.silver,
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
                    for (final (label, _, _) in appNavigationGroups)
                      if (label == 'SPORTS')
                        ..._buildVisibleSports()
                      else if (label == 'LIVE')
                        KeyedSubtree(
                          key: const ValueKey('top-scoreboard'),
                          child: _buildNavItem(
                            label: 'SCOREBOARD',
                            page: AppPage.scoreboard,
                            icon: Icons.scoreboard_outlined,
                          ),
                        ),
                  ],
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
