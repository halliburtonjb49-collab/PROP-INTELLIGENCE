import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_sound_service.dart';
import '../services/auth_manager.dart';
import '../theme/app_colors.dart';

import '../theme/app_colors.dart' as brand_colors;

const piGold = Color(0xFFD4AF37);
const piSilver = Color(0xFFC0C7D1);
const piPanelNavy = Color(0xFF07111D);

/// Width below which the workspace uses the mobile/tablet application shell.
const double appShellMobileBreakpoint = 1000;

Color rightPanelAccentForTier(String? tier) {
  final normalized = (tier ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'PRO':
    case 'PRO_FOUNDER':
    case 'PRO FOUNDER':
    case 'FOUNDING_PRO':
    case 'FOUNDING PRO':
    case 'OWNER':
      return piGold;
    case 'CORE':
    default:
      return piSilver;
  }
}

enum _RightPanelSection { account, activeSlip }

double mobileShellInset(double width) => width < 600 ? 5 : 6;
double mobileShellGap(double width) => width < 600 ? 5 : 6;
double mobileTopBarHeight(double width) => width < 360
    ? 56
    : width < 600
    ? 58
    : 60;
double mobileBottomBarHeight(double width) => width < 360
    ? 60
    : width < 600
    ? 64
    : 66;

@visibleForTesting
bool usePhoneShell(double width) => width < 600;

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.leftSidebar,
    required this.topNavigation,
    required this.content,
    required this.accountPanel,
    required this.activeSlipPanel,
    this.activeSlipCount = 0,
    this.currentViewCountListenable,
    this.watchedSlipCount = 0,
    this.mobileSelectedIndex = 0,
    this.mobileRouteKey,
    this.onMobileWatchSlip,
    this.onMobileDismissOverlay,
    this.onMobileNavigateIndex,
    this.accentColor = AppColors.gold,
    this.membershipLabel = 'CORE',
    this.topNavigationHeight = 84,
    required this.soundService,
    required this.isOwner,
    required this.ownerOperationsSelected,
    required this.onOpenOwnerOperations,
  });

  final Widget leftSidebar;
  final Widget topNavigation;
  final Widget content;
  final Widget accountPanel;
  final Widget activeSlipPanel;
  final int activeSlipCount;
  final ValueListenable<int>? currentViewCountListenable;
  final int watchedSlipCount;
  final int mobileSelectedIndex;
  final Object? mobileRouteKey;
  final VoidCallback? onMobileWatchSlip;
  final VoidCallback? onMobileDismissOverlay;
  final ValueChanged<int>? onMobileNavigateIndex;
  final Color accentColor;
  final String membershipLabel;
  final double topNavigationHeight;
  final AppSoundService soundService;
  final bool isOwner;
  final bool ownerOperationsSelected;
  final VoidCallback onOpenOwnerOperations;

  static const double leftWidth = 244;
  static const double rightWidth = 332;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _isRightPanelOpen = false;
  _RightPanelSection _activeRightPanelSection = _RightPanelSection.activeSlip;

  static const double desktopRightRailWidth = 58;
  static const double desktopRightPanelWidth = 340;

  ({double left, double right, double gap, double padding}) _metrics(
    double width,
  ) {
    if (width < 1180) {
      return (left: 178, right: 224, gap: 7, padding: 7);
    }
    if (width < 1450) {
      return (left: 204, right: 270, gap: 9, padding: 9);
    }
    return (
      left: AppShell.leftWidth,
      right: AppShell.rightWidth,
      gap: 12,
      padding: 12,
    );
  }

  Widget _surface({
    required Widget child,
    required BorderRadius borderRadius,
    bool highlighted = false,
  }) {
    return Material(
      color: const Color(0xE607111B),
      elevation: 12,
      shadowColor: const Color(0x99000000),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: highlighted ? widget.accentColor : AppColors.border,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < appShellMobileBreakpoint) {
          return _MobileAppShell(
            leftSidebar: widget.leftSidebar,
            topNavigation: widget.topNavigation,
            content: widget.content,
            accountPanel: widget.accountPanel,
            activeSlipPanel: widget.activeSlipPanel,
            activeSlipCount: widget.activeSlipCount,
            watchedSlipCount: widget.watchedSlipCount,
            selectedIndex: widget.mobileSelectedIndex,
            routeKey: widget.mobileRouteKey,
            onWatchSlip: widget.onMobileWatchSlip,
            onDismissOverlay: widget.onMobileDismissOverlay,
            onNavigateIndex: widget.onMobileNavigateIndex,
            accentColor: widget.accentColor,
            topNavigationHeight: widget.topNavigationHeight,
          );
        }
        final metrics = _metrics(constraints.maxWidth);
        final radius = BorderRadius.circular(18);
        final resolvedTopHeight = widget.topNavigationHeight
            .clamp(84.0, constraints.maxHeight * 0.30)
            .toDouble();
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              const Positioned.fill(child: _FrontPageWorkspaceBackground()),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(metrics.padding),
                  child: Row(
                    children: [
                      SizedBox(
                        width: metrics.left,
                        child: _surface(
                          borderRadius: radius,
                          child: widget.leftSidebar,
                        ),
                      ),
                      SizedBox(width: metrics.gap),
                      Expanded(
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              height: resolvedTopHeight,
                              child: _surface(
                                borderRadius: radius,
                                highlighted: true,
                                child: widget.topNavigation,
                              ),
                            ),
                            SizedBox(height: metrics.gap),
                            Expanded(
                              child: _surface(
                                borderRadius: radius,
                                child: widget.content,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: metrics.gap),
                      _DesktopRightPanel(
                        isOpen: _isRightPanelOpen,
                        activePanelSection: _activeRightPanelSection,
                        activeSlipCount: widget.activeSlipCount,
                        currentViewCountListenable:
                            widget.currentViewCountListenable,
                        accentColor: widget.accentColor,
                        membershipLabel: widget.membershipLabel,
                        soundService: widget.soundService,
                        isOwner: widget.isOwner,
                        ownerOperationsSelected: widget.ownerOperationsSelected,
                        onOpenOwnerOperations: widget.onOpenOwnerOperations,
                        accountPanel: widget.accountPanel,
                        activeSlipPanel: widget.activeSlipPanel,
                        onOpenAccount: () => setState(() {
                          _isRightPanelOpen = true;
                          _activeRightPanelSection = _RightPanelSection.account;
                        }),
                        onOpenActiveSlip: () => setState(() {
                          _isRightPanelOpen = true;
                          _activeRightPanelSection =
                              _RightPanelSection.activeSlip;
                        }),
                        onClose: () => setState(() {
                          _isRightPanelOpen = false;
                        }),
                      ),
                    ],
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

/// The slim rail that brings the account column back.
class _DesktopRightPanel extends StatelessWidget {
  const _DesktopRightPanel({
    required this.isOpen,
    required this.activePanelSection,
    required this.activeSlipCount,
    required this.currentViewCountListenable,
    required this.accentColor,
    required this.membershipLabel,
    required this.accountPanel,
    required this.activeSlipPanel,
    required this.onOpenAccount,
    required this.onOpenActiveSlip,
    required this.onClose,
    required this.soundService,
    required this.isOwner,
    required this.ownerOperationsSelected,
    required this.onOpenOwnerOperations,
  });

  final bool isOpen;
  final _RightPanelSection activePanelSection;
  final int activeSlipCount;
  final ValueListenable<int>? currentViewCountListenable;
  final Color accentColor;
  final String membershipLabel;
  final Widget accountPanel;
  final Widget activeSlipPanel;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenActiveSlip;
  final VoidCallback onClose;
  final AppSoundService soundService;
  final bool isOwner;
  final bool ownerOperationsSelected;
  final VoidCallback onOpenOwnerOperations;

  @override
  Widget build(BuildContext context) {
    final panelWidth = isOpen
        ? _AppShellState.desktopRightPanelWidth
        : _AppShellState.desktopRightRailWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 236),
      curve: Curves.easeOutCubic,
      width: panelWidth,
      decoration: BoxDecoration(
        color: piPanelNavy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(color: accentColor.withValues(alpha: 0.12), blurRadius: 14),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: isOpen
            ? _DesktopRightPanelContent(
                activeSlipCount: activeSlipCount,
                accentColor: accentColor,
                accountPanel: accountPanel,
                activeSlipPanel: activeSlipPanel,
                initialSection: activePanelSection,
                onClose: onClose,
              )
            : _RightPanelRail(
                accentColor: accentColor,
                membershipLabel: membershipLabel,
                activeSlipCount: activeSlipCount,
                currentViewCountListenable: currentViewCountListenable,
                onOpenAccount: onOpenAccount,
                onOpenActiveSlip: onOpenActiveSlip,
                soundService: soundService,
                isOwner: isOwner,
                ownerOperationsSelected: ownerOperationsSelected,
                onOpenOwnerOperations: onOpenOwnerOperations,
              ),
      ),
    );
  }
}

class _DesktopRightPanelContent extends StatefulWidget {
  const _DesktopRightPanelContent({
    required this.activeSlipCount,
    required this.accentColor,
    required this.accountPanel,
    required this.activeSlipPanel,
    required this.initialSection,
    this.onClose,
    this.mobileCloseInsideContent = false,
  });

  final int activeSlipCount;
  final Color accentColor;
  final Widget accountPanel;
  final Widget activeSlipPanel;
  final _RightPanelSection initialSection;
  final VoidCallback? onClose;
  final bool mobileCloseInsideContent;

  @override
  State<_DesktopRightPanelContent> createState() =>
      _DesktopRightPanelContentState();
}

class _DesktopRightPanelContentState extends State<_DesktopRightPanelContent> {
  late _RightPanelSection _activeSection = widget.initialSection;

  @override
  void didUpdateWidget(covariant _DesktopRightPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _activeSection = widget.initialSection;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!widget.mobileCloseInsideContent)
          Container(
            height: 54,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: accentWithOpacity(widget.accentColor),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _PanelTab(
                    label: 'ACCOUNT',
                    selected: _activeSection == _RightPanelSection.account,
                    accentColor: widget.accentColor,
                    onTap: () {
                      setState(
                        () => _activeSection = _RightPanelSection.account,
                      );
                    },
                    labelKey: const ValueKey('account-tab'),
                  ),
                ),
                Expanded(
                  child: _PanelTab(
                    label: 'ACTIVE SLIP',
                    selected: _activeSection == _RightPanelSection.activeSlip,
                    accentColor: widget.accentColor,
                    onTap: () {
                      setState(
                        () => _activeSection = _RightPanelSection.activeSlip,
                      );
                    },
                    labelKey: const ValueKey('active-slip-tab'),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Close panel',
                  child: IconButton(
                    key: const ValueKey('right-panel-close'),
                    tooltip: 'Close panel',
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close_rounded, color: widget.accentColor),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 170),
                  child: _activeSection == _RightPanelSection.account
                      ? Container(
                          key: const ValueKey('account-tab-content'),
                          color: piPanelNavy,
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                          child: widget.accountPanel,
                        )
                      : Container(
                          key: const ValueKey('active-slip-tab-content'),
                          color: piPanelNavy,
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                          child: widget.activeSlipPanel,
                        ),
                ),
              ),
              if (widget.mobileCloseInsideContent)
                Positioned(
                  top: 17,
                  right: 52,
                  child: Semantics(
                    button: true,
                    label: 'Close active slip',
                    child: IconButton(
                      key: const ValueKey('mobile-active-slip-close'),
                      tooltip: 'Close active slip',
                      onPressed: widget.onClose,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(34, 34),
                        backgroundColor: Colors.transparent,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: widget.accentColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
    required this.labelKey,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;
  final Key labelKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label tab',
      child: InkWell(
        onTap: onTap,
        key: labelKey,
        child: Container(
          height: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accentColor : AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .35,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _RightPanelRail extends StatelessWidget {
  const _RightPanelRail({
    required this.accentColor,
    required this.membershipLabel,
    required this.activeSlipCount,
    required this.currentViewCountListenable,
    required this.onOpenAccount,
    required this.onOpenActiveSlip,
    required this.soundService,
    required this.isOwner,
    required this.ownerOperationsSelected,
    required this.onOpenOwnerOperations,
  });

  final Color accentColor;
  final String membershipLabel;
  final int activeSlipCount;
  final ValueListenable<int>? currentViewCountListenable;
  final VoidCallback onOpenAccount;
  final VoidCallback onOpenActiveSlip;
  final AppSoundService soundService;
  final bool isOwner;
  final bool ownerOperationsSelected;
  final VoidCallback onOpenOwnerOperations;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: piPanelNavy,
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 7),
      child: Column(
        children: [
          _RailButton(
            key: const ValueKey('right-panel-account-button'),
            label: 'Open account',
            tooltip: 'Open account',
            icon: Icons.person_outline_rounded,
            visibleLabel: 'ACCOUNT',
            accentColor: accentColor,
            buttonHeight: 62,
            onTap: onOpenAccount,
            openActionSize: 44,
            openAction: _OpenPanelActionButton(
              key: const ValueKey('right-panel-account-open'),
              tooltip: 'Open account',
              accentColor: accentColor,
              onPressed: onOpenAccount,
            ),
            trailing: const SizedBox.shrink(),
          ),
          const SizedBox(height: 7),
          _RailButton(
            key: const ValueKey('right-panel-active-slip-button'),
            label:
                'Open active slip, $activeSlipCount selected props in active slip',
            tooltip: 'Open active slip',
            icon: Icons.receipt_long_outlined,
            visibleLabel: 'SLIP',
            accentColor: accentColor,
            buttonHeight: 74,
            onTap: onOpenActiveSlip,
            openActionSize: 46,
            openAction: _OpenPanelActionButton(
              key: const ValueKey('right-panel-active-slip-open'),
              tooltip: 'Open active slip',
              accentColor: accentColor,
              onPressed: onOpenActiveSlip,
            ),
            trailing: ActiveSlipBadge(
              key: const ValueKey('active-slip-badge'),
              count: activeSlipCount,
              accentColor: accentColor,
            ),
          ),
          if (currentViewCountListenable != null) ...[
            const SizedBox(height: 7),
            ValueListenableBuilder<int>(
              valueListenable: currentViewCountListenable!,
              builder: (context, count, _) => _CurrentViewRail(count: count),
            ),
          ],
          if (isOwner) ...[
            const SizedBox(height: 7),
            _RailButton(
              key: const ValueKey('right-panel-owner-operations-button'),
              label: 'Open Owner Operations',
              tooltip: 'Open Owner Operations',
              icon: Icons.admin_panel_settings_outlined,
              visibleLabel: 'OWNER OPS',
              accentColor: accentColor,
              buttonHeight: 68,
              onTap: onOpenOwnerOperations,
              openActionSize: 0,
              openAction: const SizedBox.shrink(),
              trailing: ownerOperationsSelected
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 12,
                      color: accentColor,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
          const SizedBox(height: 7),
          AnimatedBuilder(
            animation: soundService,
            builder: (context, _) => _RailButton(
              key: const ValueKey('right-panel-sound-button'),
              label: soundService.enabled ? 'Disable sound' : 'Enable sound',
              tooltip: soundService.enabled ? 'Sound on' : 'Sound muted',
              icon: soundService.enabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              visibleLabel: soundService.enabled ? 'SOUND' : 'MUTED',
              accentColor: accentColor,
              buttonHeight: 64,
              onTap: () => soundService.setEnabled(!soundService.enabled),
              openActionSize: 0,
              openAction: const SizedBox.shrink(),
              trailing: const SizedBox.shrink(),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: '$membershipLabel membership',
            child: Semantics(
              label: '$membershipLabel membership',
              child: Container(
                key: const ValueKey('right-panel-membership-badge'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withValues(alpha: .55)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 18,
                      color: accentColor,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'MEMBERSHIP',
                      maxLines: 1,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 5.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      membershipLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.visibleLabel,
    required this.accentColor,
    required this.buttonHeight,
    required this.onTap,
    required this.openActionSize,
    required this.openAction,
    required this.trailing,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final String visibleLabel;
  final Color accentColor;
  final double buttonHeight;
  final VoidCallback onTap;
  final double openActionSize;
  final Widget openAction;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final hasBadge = visibleLabel == 'SLIP';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        height: buttonHeight,
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.fromLTRB(6, 8, 7, 8),
            minimumSize: const Size(44, 44),
            side: BorderSide(color: accentColor.withValues(alpha: .45)),
            foregroundColor: accentColor,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          onPressed: onTap,
          child: Column(
            children: [
              if (hasBadge)
                SizedBox(
                  height: 22,
                  child: Align(alignment: Alignment.topRight, child: trailing),
                ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 32,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          visibleLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentViewRail extends StatelessWidget {
  const _CurrentViewRail({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Current view, $count live props',
    child: Container(
      key: const ValueKey('right-panel-current-view'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      decoration: BoxDecoration(
        color: piGold.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: piGold.withValues(alpha: .65)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.query_stats_rounded, color: piGold, size: 17),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count',
              maxLines: 1,
              style: const TextStyle(
                color: piGold,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'LIVE',
            style: TextStyle(
              color: piGold,
              fontSize: 6.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .35,
            ),
          ),
        ],
      ),
    ),
  );
}

class _OpenPanelActionButton extends StatelessWidget {
  const _OpenPanelActionButton({
    super.key,
    required this.tooltip,
    required this.accentColor,
    required this.onPressed,
  });

  final String tooltip;
  final Color accentColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          focusColor: accentColor.withValues(alpha: 0.24),
          hoverColor: accentColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withValues(alpha: .55)),
            ),
            child: Center(
              child: Icon(
                Icons.chevron_right_rounded,
                color: accentColor,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ActiveSlipBadge extends StatefulWidget {
  const ActiveSlipBadge({
    super.key,
    required this.count,
    required this.accentColor,
  });

  final int count;
  final Color accentColor;

  @override
  State<ActiveSlipBadge> createState() => _ActiveSlipBadgeState();
}

class _ActiveSlipBadgeState extends State<ActiveSlipBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.18,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_pulseController);
  }

  @override
  void didUpdateWidget(covariant ActiveSlipBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count && widget.count > 0) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 0) {
      return const SizedBox.shrink(key: ValueKey('active-slip-badge-empty'));
    }
    final muted = widget.count == 0;
    final badgeColor = muted
        ? widget.accentColor.withValues(alpha: 0.42)
        : widget.accentColor;
    return Semantics(
      label: '${widget.count} selected props in active slip',
      liveRegion: true,
      child: ScaleTransition(
        key: const ValueKey('active-slip-badge-scale'),
        scale: muted ? const AlwaysStoppedAnimation(1.0) : _scaleAnimation,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: badgeColor,
            shape: BoxShape.circle,
            boxShadow: muted
                ? null
                : [
                    BoxShadow(
                      color: badgeColor.withValues(alpha: 0.28),
                      blurRadius: 9,
                    ),
                  ],
          ),
          child: Text(
            '${widget.count}',
            style: TextStyle(
              color: muted ? const Color(0xFF07111D) : AppColors.bgBase,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

Color accentWithOpacity(Color accent) => accent.withValues(alpha: 0.24);

class _MobileAppShell extends StatefulWidget {
  const _MobileAppShell({
    required this.leftSidebar,
    required this.topNavigation,
    required this.content,
    required this.accountPanel,
    required this.activeSlipPanel,
    required this.activeSlipCount,
    required this.watchedSlipCount,
    required this.selectedIndex,
    required this.routeKey,
    required this.onWatchSlip,
    required this.onDismissOverlay,
    required this.onNavigateIndex,
    required this.accentColor,
    required this.topNavigationHeight,
  });

  final Widget leftSidebar;
  final Widget topNavigation;
  final Widget content;
  final Widget accountPanel;
  final Widget activeSlipPanel;
  final int activeSlipCount;
  final int watchedSlipCount;
  final int selectedIndex;
  final Object? routeKey;
  final VoidCallback? onWatchSlip;
  final VoidCallback? onDismissOverlay;
  final ValueChanged<int>? onNavigateIndex;
  final Color accentColor;
  final double topNavigationHeight;

  @override
  State<_MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends State<_MobileAppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  _RightPanelSection _mobileRightPanelSection = _RightPanelSection.activeSlip;
  DateTime? _lastHorizontalScrollSignal;
  double _dragNetX = 0;
  double _dragAbsX = 0;
  double _dragAbsY = 0;

  bool get _supportsSwipeRoute {
    // Swiping is intended only for top-level destinations represented in the
    // mobile bottom navigation.
    return widget.selectedIndex >= 0 && widget.selectedIndex <= 2;
  }

  void _handleSwipeStart(DragStartDetails details) {
    _dragNetX = 0;
    _dragAbsX = 0;
    _dragAbsY = 0;
  }

  void _handleSwipeUpdate(DragUpdateDetails details) {
    _dragNetX += details.delta.dx;
    _dragAbsX += details.delta.dx.abs();
    _dragAbsY += details.delta.dy.abs();
  }

  void _handleSwipeEnd(DragEndDetails details) {
    if (!_supportsSwipeRoute) return;
    if ((_scaffoldKey.currentState?.isDrawerOpen ?? false) ||
        (_scaffoldKey.currentState?.isEndDrawerOpen ?? false)) {
      return;
    }

    final now = DateTime.now();
    if (_lastHorizontalScrollSignal != null &&
        now.difference(_lastHorizontalScrollSignal!) <
            const Duration(milliseconds: 240)) {
      return;
    }

    // Require a deliberate horizontal gesture so regular vertical board
    // scrolling does not unexpectedly navigate pages.
    final velocity = details.primaryVelocity ?? 0;
    final strongVelocity = velocity.abs() >= 760;
    final strongDistance = _dragAbsX >= 84;
    final mostlyHorizontal = _dragAbsX >= (_dragAbsY * 1.35);
    if (!mostlyHorizontal || (!strongVelocity && !strongDistance)) {
      return;
    }

    var targetIndex = widget.selectedIndex;
    if (velocity < -1 || (velocity == 0 && _dragNetX < -1)) {
      targetIndex += 1;
    } else if (velocity > 1 || (velocity == 0 && _dragNetX > 1)) {
      targetIndex -= 1;
    }
    targetIndex = targetIndex.clamp(0, 2);
    if (targetIndex == widget.selectedIndex) {
      return;
    }
    widget.onNavigateIndex?.call(targetIndex);
  }

  @override
  void didUpdateWidget(covariant _MobileAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the primary navigation open after a destination change. Mobile now
    // mirrors the web workspace: the complete sidebar remains available until
    // the member deliberately collapses it. The secondary slip drawer still
    // closes after its destination changes.
    if (oldWidget.routeKey != widget.routeKey ||
        oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scaffold = _scaffoldKey.currentState;
        if (scaffold?.isEndDrawerOpen ?? false) scaffold?.closeEndDrawer();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isPhone = usePhoneShell(screenWidth);
    // For flip/fold phones (280-320px), use 85% of screen width
    // For regular phones, use 260-340px range
    final drawerWidth = screenWidth < 360
        ? (screenWidth * 0.85).clamp(240.0, 300.0)
        : screenWidth.clamp(260.0, 340.0);
    final shellInset = mobileShellInset(screenWidth);
    final shellGap = mobileShellGap(screenWidth);
    final resolvedTopHeight = isPhone
        ? mobileTopBarHeight(screenWidth)
        : widget.topNavigationHeight
              .clamp(76.0, MediaQuery.sizeOf(context).height * 0.30)
              .toDouble();
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: SizedBox(
        width: drawerWidth,
        child: Drawer(
          backgroundColor: Colors.transparent,
          child: SafeArea(child: widget.leftSidebar),
        ),
      ),
      endDrawer: SizedBox(
        width: drawerWidth,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              top: resolvedTopHeight + shellGap + shellInset,
              bottom:
                  mobileBottomBarHeight(screenWidth) + shellGap + shellInset,
            ),
            child: Drawer(
              backgroundColor: Colors.transparent,
              child: _DesktopRightPanelContent(
                activeSlipCount: widget.activeSlipCount,
                accentColor: widget.accentColor,
                accountPanel: widget.accountPanel,
                activeSlipPanel: widget.activeSlipPanel,
                initialSection: _mobileRightPanelSection,
                mobileCloseInsideContent: true,
                onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _FrontPageWorkspaceBackground()),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(shellInset),
              child: Column(
                children: [
                  Container(
                    height: resolvedTopHeight,
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth < 360 ? 4 : 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE607111B),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: widget.accentColor),
                    ),
                    child: isPhone
                        ? _PhoneAppHeader(
                            accentColor: widget.accentColor,
                            onMenu: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                            onAccount: () {
                              setState(() {
                                _mobileRightPanelSection =
                                    _RightPanelSection.account;
                              });
                              _scaffoldKey.currentState?.openEndDrawer();
                            },
                          )
                        : Row(
                            children: [Expanded(child: widget.topNavigation)],
                          ),
                  ),
                  SizedBox(height: shellGap),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.axis == Axis.horizontal) {
                          _lastHorizontalScrollSignal = DateTime.now();
                        }
                        return false;
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: _handleSwipeStart,
                        onHorizontalDragUpdate: _handleSwipeUpdate,
                        onHorizontalDragEnd: _handleSwipeEnd,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xE607111B),
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: widget.content,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: shellGap),
                  _MobileBottomNavigation(
                    selectedIndex: widget.selectedIndex,
                    activeSlipCount: widget.activeSlipCount,
                    watchedSlipCount: widget.watchedSlipCount,
                    onWatchSlip: () {
                      widget.onDismissOverlay?.call();
                      widget.onWatchSlip?.call();
                    },
                    onNavigateIndex: (index) {
                      widget.onDismissOverlay?.call();
                      widget.onNavigateIndex?.call(index);
                    },
                    onTicket: () {
                      widget.onDismissOverlay?.call();
                      setState(() {
                        _mobileRightPanelSection =
                            _RightPanelSection.activeSlip;
                      });
                      _scaffoldKey.currentState?.openEndDrawer();
                    },
                    onMenu: () {
                      widget.onDismissOverlay?.call();
                      _scaffoldKey.currentState?.openDrawer();
                    },
                    accentColor: widget.accentColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneAppHeader extends StatelessWidget {
  const _PhoneAppHeader({
    required this.accentColor,
    required this.onMenu,
    required this.onAccount,
  });

  final Color accentColor;
  final VoidCallback onMenu;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('phone-header-menu'),
          tooltip: 'Open menu',
          onPressed: onMenu,
          icon: const Icon(Icons.menu_rounded),
          color: piSilver,
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 36,
          height: 36,
          child: Image.asset(
            'assets/branding/Final_Master_Logo_Modern_PI.png',
            fit: BoxFit.contain,
            semanticLabel: 'Prop Intelligence',
            errorBuilder: (_, _, _) =>
                const Icon(Icons.insights_rounded, color: piGold, size: 28),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'PROP INTELLIGENCE',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.15,
            ),
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: onAccount,
              icon: const Icon(Icons.notifications_none_rounded),
              color: piSilver,
              visualDensity: VisualDensity.compact,
            ),
            Positioned(
              right: 8,
              top: 7,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        ValueListenableBuilder<AuthSessionState>(
          valueListenable: AuthManager.instance.sessionState,
          builder: (context, session, _) {
            final avatarUrl = session.avatarUrl?.trim() ?? '';
            return IconButton(
              key: const ValueKey('phone-header-account'),
              tooltip: 'Open account',
              onPressed: onAccount,
              visualDensity: VisualDensity.compact,
              icon: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor, width: 1.2),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl.isEmpty
                    ? Icon(
                        Icons.account_circle_outlined,
                        color: accentColor,
                        size: 28,
                      )
                    : Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.account_circle_outlined,
                          color: accentColor,
                          size: 28,
                        ),
                      ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MobileBottomNavigation extends StatelessWidget {
  const _MobileBottomNavigation({
    required this.selectedIndex,
    required this.activeSlipCount,
    required this.watchedSlipCount,
    required this.onWatchSlip,
    required this.onNavigateIndex,
    required this.onTicket,
    required this.onMenu,
    required this.accentColor,
  });

  final int selectedIndex;
  final int activeSlipCount;
  final int watchedSlipCount;
  final VoidCallback? onWatchSlip;
  final ValueChanged<int> onNavigateIndex;
  final VoidCallback onTicket;
  final VoidCallback onMenu;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 360;
    return Container(
      height: mobileBottomBarHeight(screenWidth),
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 3 : 5,
        vertical: isNarrow ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xF207111B),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accentColor),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18)],
      ),
      child: Row(
        children: [
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-menu'),
              icon: Icons.grid_view_rounded,
              label: 'MENU',
              selected: selectedIndex == 3,
              onTap: onMenu,
              accentColor: accentColor,
            ),
          ),
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-board'),
              icon: Icons.view_agenda_outlined,
              label: 'PROPS',
              selected: selectedIndex == 0,
              onTap: () => onNavigateIndex(0),
              accentColor: accentColor,
            ),
          ),
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-games'),
              icon: Icons.sports_score_outlined,
              label: isNarrow ? 'GAMES' : 'LIVE GAMES',
              selected: selectedIndex == 1,
              onTap: () => onNavigateIndex(1),
              accentColor: accentColor,
            ),
          ),
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-watchlist'),
              icon: Icons.visibility_outlined,
              label: 'WATCH',
              selected: selectedIndex == 2,
              badge: watchedSlipCount,
              onTap: onWatchSlip,
              accentColor: accentColor,
            ),
          ),
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-ticket'),
              icon: Icons.receipt_long_rounded,
              label: 'SLIP',
              selected: false,
              badge: activeSlipCount,
              onTap: onTicket,
              accentColor: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int badge;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accentColor : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: .11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? accentColor : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 21),
                  if (badge > 0)
                    Positioned(
                      right: -12,
                      top: -8,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.gold,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            color: brand_colors.AppColors.bgBase,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandCenterBackground extends StatelessWidget {
  const _CommandCenterBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _CommandCenterBackgroundPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _FrontPageWorkspaceBackground extends StatelessWidget {
  const _FrontPageWorkspaceBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _CommandCenterBackground(),
        Center(
          child: Opacity(
            opacity: .11,
            child: FractionallySizedBox(
              widthFactor: .62,
              heightFactor: .78,
              child: Image.asset(
                'assets/branding/prop_intelligence_logo_transparent.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const Positioned(
          left: 22,
          top: 92,
          child: _WorkspaceSportIcon(Icons.sports_basketball_rounded, 92),
        ),
        const Positioned(
          right: 28,
          bottom: 74,
          child: _WorkspaceSportIcon(Icons.sports_baseball_rounded, 82),
        ),
      ],
    );
  }
}

class _WorkspaceSportIcon extends StatelessWidget {
  const _WorkspaceSportIcon(this.icon, this.size);

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: size, color: AppColors.gold.withValues(alpha: .12));
}

class _CommandCenterBackgroundPainter extends CustomPainter {
  const _CommandCenterBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0B2638), Color(0xFF04101A), Color(0xFF020609)],
        stops: [0, .58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final grid = Paint()
      ..color = AppColors.gold.withValues(alpha: .055)
      ..strokeWidth = .7;
    const spacing = 56.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final blueGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [AppColors.blue.withValues(alpha: .13), Colors.transparent],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .48, size.height * .2),
              radius: size.shortestSide * .65,
            ),
          );
    canvas.drawRect(Offset.zero & size, blueGlow);

    final accent = Paint()
      ..color = AppColors.gold.withValues(alpha: .16)
      ..strokeWidth = 1.1;
    canvas.drawLine(
      Offset(size.width * .05, size.height * .86),
      Offset(size.width * .38, size.height * .52),
      accent,
    );
    canvas.drawLine(
      Offset(size.width * .38, size.height * .52),
      Offset(size.width * .64, size.height * .66),
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
