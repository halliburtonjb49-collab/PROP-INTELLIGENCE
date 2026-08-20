import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../services/auth_manager.dart';
import '../theme/app_colors.dart' as app_colors;
import 'sidebar_button.dart';

class LeftSidebar extends StatefulWidget {
  final AppPage selectedPage;
  final String selectedSport;
  final int lockedSlipCount;
  final ValueListenable<int> propCountListenable;
  final VoidCallback onRefresh;
  final ValueChanged<AppPage>? onSelectPage;
  final ValueChanged<String>? onSelectSport;

  const LeftSidebar({
    super.key,
    required this.selectedPage,
    required this.selectedSport,
    required this.lockedSlipCount,
    required this.propCountListenable,
    required this.onRefresh,
    this.onSelectPage,
    this.onSelectSport,
  });

  @override
  State<LeftSidebar> createState() => _LeftSidebarState();
}

class _LeftSidebarState extends State<LeftSidebar> {
  final ScrollController _sidebarScrollController = ScrollController();

  static const _researchPages = {
    AppPage.briefing,
    AppPage.board,
    AppPage.searchPlayers,
    AppPage.lineMovement,
    AppPage.injuryImpact,
    AppPage.analytics,
    AppPage.propChat,
    AppPage.scoreboardWatchlist,
    AppPage.intelligenceLab,
    AppPage.refereeTracker,
    AppPage.evScanner,
  };
  static const _buildPages = {
    AppPage.propBuilder,
    AppPage.builderPerformance,
    AppPage.watchlist,
  };
  static const _historyPages = {AppPage.pastSlipHistory, AppPage.trackRecord};

  String _sportEmoji(String sport) {
    switch (sport) {
      case 'MLB':
        return '⚾';
      case 'NBA':
        return '🏀';
      case 'WNBA':
        return '🏀';
      case 'NCAAB':
        return '\u{1F3C0}';
      case 'SOCCER':
        return '⚽';
      default:
        return '•';
    }
  }

  // Branded gold icons for sports with custom artwork; sports without an
  // entry here fall back to _sportEmoji.
  String? _sportImagePath(String sport) {
    switch (sport) {
      case 'NFL':
        return 'assets/branding/sport_icons/nfl.png';
      case 'NCAAF':
        return 'assets/branding/sport_icons/ncaaf.png';
      case 'NCAAB':
        return 'assets/branding/sport_icons/ncaab.png';
      case 'CFL':
        return 'assets/branding/sport_icons/cfl.png';
      case 'NHL':
        return 'assets/branding/sport_icons/nhl.png';
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: app_colors.AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SidebarHeader(
              onRefresh: widget.onRefresh,
              onOpenAlerts: () => widget.onSelectPage?.call(AppPage.propAlerts),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Scrollbar(
              controller: _sidebarScrollController,
              thumbVisibility: true,
              interactive: true,
              child: ListView(
                controller: _sidebarScrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                children: [
                  _CollapsibleSidebarSection(
                    key: ValueKey(
                      'research-${_researchPages.contains(widget.selectedPage)}',
                    ),
                    title: 'RESEARCH',
                    initiallyExpanded: _researchPages.contains(
                      widget.selectedPage,
                    ),
                    children: [
                      SidebarButton(
                        label: "TODAY'S BRIEFING",
                        leadingIcons: const [Icons.wb_sunny_outlined],
                        selected: widget.selectedPage == AppPage.briefing,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.briefing),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'MARKET BOARD',
                        leadingIcons: const [Icons.dashboard_outlined],
                        selected: widget.selectedPage == AppPage.board,
                        showGoldBar: true,
                        onTap: () => widget.onSelectPage?.call(AppPage.board),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'SEARCH PLAYERS',
                        leadingIcons: const [Icons.person_search_outlined],
                        selected: widget.selectedPage == AppPage.searchPlayers,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.searchPlayers),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'LINE MOVEMENT',
                        leadingIcons: const [Icons.show_chart_rounded],
                        selected: widget.selectedPage == AppPage.lineMovement,
                        requiredTier: SubscriptionTier.core,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.lineMovement),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'INJURY IMPACT',
                        leadingIcons: const [Icons.health_and_safety_outlined],
                        selected: widget.selectedPage == AppPage.injuryImpact,
                        requiredTier: SubscriptionTier.edge,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.injuryImpact),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'ANALYTICS',
                        leadingIcons: const [Icons.analytics_outlined],
                        selected: widget.selectedPage == AppPage.analytics,
                        requiredTier: SubscriptionTier.core,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.analytics),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        key: const ValueKey('mobile-sidebar-prop-chat'),
                        label: 'PROP CHAT',
                        leadingIcons: const [Icons.forum_outlined],
                        selected: widget.selectedPage == AppPage.propChat,
                        requiredTier: SubscriptionTier.core,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.propChat),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'SCORE WATCH',
                        leadingIcons: const [
                          Icons.notifications_active_rounded,
                        ],
                        leadingIconColors: const [app_colors.AppColors.gold],
                        trailingIcon: Icons.visibility_rounded,
                        trailingIconKey: const ValueKey(
                          'score-watch-trailing-icon',
                        ),
                        selected:
                            widget.selectedPage == AppPage.scoreboardWatchlist,
                        requiredTier: SubscriptionTier.edge,
                        showGoldBar: true,
                        onTap: () => widget.onSelectPage?.call(
                          AppPage.scoreboardWatchlist,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'THE LAB',
                        leadingIcons: const [Icons.science_outlined],
                        leadingIconColors: const [app_colors.AppColors.gold],
                        selected:
                            widget.selectedPage == AppPage.intelligenceLab,
                        requiredTier: SubscriptionTier.edge,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.intelligenceLab),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'REFEREE\nTRACKER',
                        leadingIcons: const [Icons.sports_outlined],
                        leadingIconColors: const [app_colors.AppColors.gold],
                        selected: widget.selectedPage == AppPage.refereeTracker,
                        requiredTier: SubscriptionTier.edge,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.refereeTracker),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'EV SCANNER',
                        selected: widget.selectedPage == AppPage.evScanner,
                        requiredTier: SubscriptionTier.edge,
                        showGoldBar: true,
                        leadingIcons: const [Icons.auto_graph],
                        leadingIconColors: const [app_colors.AppColors.blue],
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.evScanner),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _CollapsibleSidebarSection(
                    key: ValueKey(
                      'build-${_buildPages.contains(widget.selectedPage)}',
                    ),
                    title: 'BUILD',
                    initiallyExpanded: _buildPages.contains(
                      widget.selectedPage,
                    ),
                    children: [
                      SidebarButton(
                        label: 'PROP BUILDER',
                        leadingIcons: const [Icons.category_outlined],
                        selected: widget.selectedPage == AppPage.propBuilder,
                        requiredTier: SubscriptionTier.core,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.propBuilder),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'BUILD\nPERFORM',
                        leadingIcons: const [Icons.grid_view_rounded],
                        selected:
                            widget.selectedPage == AppPage.builderPerformance,
                        requiredTier: SubscriptionTier.edge,
                        showGoldBar: true,
                        onTap: () => widget.onSelectPage?.call(
                          AppPage.builderPerformance,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'SLIP WATCHER',
                        badge: '${widget.lockedSlipCount}',
                        leadingIcons: const [Icons.receipt_long_rounded],
                        leadingIconColors: const [app_colors.AppColors.gold],
                        selected: widget.selectedPage == AppPage.watchlist,
                        requiredTier: SubscriptionTier.core,
                        hasProUpgrade: true,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.watchlist),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _CollapsibleSidebarSection(
                    key: ValueKey(
                      'history-${_historyPages.contains(widget.selectedPage)}',
                    ),
                    title: 'HISTORY',
                    initiallyExpanded: _historyPages.contains(
                      widget.selectedPage,
                    ),
                    children: [
                      SidebarButton(
                        label: 'PAST SLIP\nHISTORY',
                        leadingIcons: const [Icons.history_rounded],
                        leadingIconColors: const [app_colors.AppColors.gold],
                        selected:
                            widget.selectedPage == AppPage.pastSlipHistory,
                        requiredTier: SubscriptionTier.core,
                        hasProUpgrade: true,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.pastSlipHistory),
                      ),
                      const SizedBox(height: 6),
                      SidebarButton(
                        label: 'TRACK RECORD',
                        leadingIcons: const [Icons.fact_check_outlined],
                        leadingIconColors: const [app_colors.AppColors.gold],
                        selected: widget.selectedPage == AppPage.trackRecord,
                        requiredTier: SubscriptionTier.core,
                        showGoldBar: true,
                        onTap: () =>
                            widget.onSelectPage?.call(AppPage.trackRecord),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _SidebarSectionLabel('SPECIALTY'),
                  const SizedBox(height: 7),
                  SidebarButton(
                    label: 'STRIKEOUT\nPRO GOLD',
                    selected: widget.selectedPage == AppPage.strikeoutProGold,
                    requiredTier: SubscriptionTier.edge,
                    leadingIcons: const [Icons.sports_baseball_rounded],
                    leadingIconColors: const [app_colors.AppColors.gold],
                    onTap: () =>
                        widget.onSelectPage?.call(AppPage.strikeoutProGold),
                  ),
                  if (AuthManager.instance.sessionState.value.isOwner) ...[
                    const SizedBox(height: 18),
                    const _SidebarSectionLabel('OWNER'),
                    const SizedBox(height: 7),
                    SidebarButton(
                      key: const ValueKey('owner-operations-sidebar-button'),
                      label: 'OPERATIONS\nCENTER',
                      selected: widget.selectedPage == AppPage.ownerOperations,
                      showGoldBar: true,
                      leadingIcons: const [Icons.admin_panel_settings_outlined],
                      leadingIconColors: const [app_colors.AppColors.gold],
                      onTap: () =>
                          widget.onSelectPage?.call(AppPage.ownerOperations),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: ValueListenableBuilder<int>(
              valueListenable: widget.propCountListenable,
              builder: (context, count, _) => Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: app_colors.AppColors.sidebar,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: app_colors.AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURRENT VIEW',
                      style: TextStyle(
                        color: app_colors.AppColors.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: app_colors.AppColors.blue,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const _SidebarLegalLink(),
          const _SidebarSignOut(),
        ],
      ),
    );
  }
}

/// One way into the terms, in navigation rather than on every screen.
///
/// A banner repeated on every page is clutter that gets removed by whoever
/// needs the space next. This sits with the other account controls, where
/// somebody looks when they want it.
class _SidebarLegalLink extends StatelessWidget {
  const _SidebarLegalLink();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: TextButton.icon(
        key: const ValueKey('sidebar-legal-link'),
        onPressed: () => Navigator.of(context).pushNamed('/legal'),
        icon: const Icon(Icons.gavel_rounded, size: 14),
        label: const Text(
          'TERMS & PRIVACY',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
        ),
        style: TextButton.styleFrom(
          foregroundColor: app_colors.AppColors.silver,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        ),
      ),
    );
  }
}

/// Ends the session, from anywhere in the app.
///
/// signOut() existed but only the paywall screen called it, so a member with
/// a working subscription had no way to leave: they would have had to lose
/// access to be offered the button. That matters on a shared device, and it
/// is the only way to recover from being signed in as the wrong account.
class _SidebarSignOut extends StatelessWidget {
  const _SidebarSignOut();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: TextButton.icon(
        key: const ValueKey('sidebar-sign-out'),
        onPressed: () async {
          final navigator = Navigator.of(context);
          // Close the drawer first on the widths where this is one, so the
          // sign-out does not leave an orphaned overlay behind it.
          if (navigator.canPop()) {
            navigator.pop();
          }
          await AuthManager.instance.signOut();
        },
        icon: const Icon(Icons.logout_rounded, size: 16),
        label: const Text(
          'SIGN OUT',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        ),
        style: TextButton.styleFrom(
          foregroundColor: app_colors.AppColors.silver,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.onRefresh, required this.onOpenAlerts});

  final VoidCallback onRefresh;
  final VoidCallback onOpenAlerts;

  Widget _action({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF091722),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: app_colors.AppColors.border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: app_colors.AppColors.gold, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: app_colors.AppColors.sidebar,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: app_colors.AppColors.borderGold),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/branding/Final_Master_Logo_Modern_PI.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE RESEARCH',
                    style: TextStyle(
                      color: app_colors.AppColors.goldHighlight,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'WORKSPACE',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            const Icon(Icons.circle, color: app_colors.AppColors.blue, size: 7),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'SYSTEM ONLINE',
                style: TextStyle(
                  color: app_colors.AppColors.blue,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            _action(
              tooltip: 'Refresh props',
              icon: Icons.refresh_rounded,
              onTap: onRefresh,
            ),
            const SizedBox(width: 6),
            _action(
              tooltip: 'View prop alerts',
              icon: Icons.notifications_none_rounded,
              onTap: onOpenAlerts,
            ),
          ],
        ),
      ],
    );
  }
}

class _CollapsibleSidebarSection extends StatelessWidget {
  const _CollapsibleSidebarSection({
    super.key,
    required this.title,
    required this.initiallyExpanded,
    required this.children,
  });

  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: ValueKey('sidebar-section-$title'),
          initiallyExpanded: initiallyExpanded,
          maintainState: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 9),
          childrenPadding: const EdgeInsets.only(top: 5),
          minTileHeight: 42,
          iconColor: app_colors.AppColors.gold,
          collapsedIconColor: app_colors.AppColors.textMuted,
          title: _SidebarSectionLabel(title),
          children: children,
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  final String label;

  const _SidebarSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Text(
        label,
        style: const TextStyle(
          color: app_colors.AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.35,
        ),
      ),
    );
  }
}
