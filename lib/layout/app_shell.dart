import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.leftSidebar,
    required this.topNavigation,
    required this.content,
    required this.rightSidebar,
    this.activeSlipCount = 0,
    this.mobileSelectedIndex = 0,
    this.onMobileBoard,
    this.onMobileGameMarkets,
  });

  final Widget leftSidebar;
  final Widget topNavigation;
  final Widget content;
  final Widget rightSidebar;
  final int activeSlipCount;
  final int mobileSelectedIndex;
  final VoidCallback? onMobileBoard;
  final VoidCallback? onMobileGameMarkets;

  static const double leftWidth = 244;
  static const double rightWidth = 332;
  static const double topHeight = 84;

  ({double left, double right, double gap, double padding}) _metrics(
    double width,
  ) {
    if (width < 1180) {
      return (left: 178, right: 224, gap: 7, padding: 7);
    }
    if (width < 1450) {
      return (left: 204, right: 270, gap: 9, padding: 9);
    }
    return (left: leftWidth, right: rightWidth, gap: 12, padding: 12);
  }

  Widget _surface({
    required Widget child,
    required BorderRadius borderRadius,
    bool highlighted = false,
  }) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xE607111B),
          borderRadius: borderRadius,
          border: Border.all(
            color: highlighted ? AppColors.borderGold : AppColors.border,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          return _MobileAppShell(
            leftSidebar: leftSidebar,
            topNavigation: topNavigation,
            content: content,
            rightSidebar: rightSidebar,
            activeSlipCount: activeSlipCount,
            selectedIndex: mobileSelectedIndex,
            onBoard: onMobileBoard,
            onGameMarkets: onMobileGameMarkets,
          );
        }
        final metrics = _metrics(constraints.maxWidth);
        final radius = BorderRadius.circular(18);

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
                          child: leftSidebar,
                        ),
                      ),
                      SizedBox(width: metrics.gap),
                      Expanded(
                        child: Column(
                          children: [
                            SizedBox(
                              height: topHeight,
                              child: _surface(
                                borderRadius: radius,
                                highlighted: true,
                                child: topNavigation,
                              ),
                            ),
                            SizedBox(height: metrics.gap),
                            Expanded(
                              child: _surface(
                                borderRadius: radius,
                                child: content,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: metrics.gap),
                      SizedBox(
                        width: metrics.right,
                        child: _surface(
                          borderRadius: radius,
                          child: rightSidebar,
                        ),
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

class _MobileAppShell extends StatefulWidget {
  const _MobileAppShell({
    required this.leftSidebar,
    required this.topNavigation,
    required this.content,
    required this.rightSidebar,
    required this.activeSlipCount,
    required this.selectedIndex,
    required this.onBoard,
    required this.onGameMarkets,
  });

  final Widget leftSidebar;
  final Widget topNavigation;
  final Widget content;
  final Widget rightSidebar;
  final int activeSlipCount;
  final int selectedIndex;
  final VoidCallback? onBoard;
  final VoidCallback? onGameMarkets;

  @override
  State<_MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends State<_MobileAppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void didUpdateWidget(covariant _MobileAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.key != widget.content.key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scaffold = _scaffoldKey.currentState;
        if (scaffold?.isDrawerOpen ?? false) scaffold?.closeDrawer();
        if (scaffold?.isEndDrawerOpen ?? false) scaffold?.closeEndDrawer();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawerWidth = MediaQuery.sizeOf(context).width.clamp(260.0, 340.0);
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
        child: Drawer(
          backgroundColor: Colors.transparent,
          child: SafeArea(child: widget.rightSidebar),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _FrontPageWorkspaceBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Column(
                children: [
                  Container(
                    height: 62,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xE607111B),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppColors.borderGold),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Open workspace navigation',
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          icon: const Icon(
                            Icons.menu_rounded,
                            color: AppColors.gold,
                          ),
                        ),
                        Expanded(child: widget.topNavigation),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              key: const ValueKey('mobile-active-slip-button'),
                              tooltip: 'Open account and active slip',
                              onPressed: () =>
                                  _scaffoldKey.currentState?.openEndDrawer(),
                              icon: const Icon(
                                Icons.receipt_long_rounded,
                                color: AppColors.gold,
                              ),
                            ),
                            if (widget.activeSlipCount > 0)
                              Positioned(
                                right: 0,
                                top: 2,
                                child: Container(
                                  key: const ValueKey(
                                    'mobile-active-slip-count',
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: AppColors.gold,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    widget.activeSlipCount > 99
                                        ? '99+'
                                        : '${widget.activeSlipCount}',
                                    style: const TextStyle(
                                      color: Color(0xFF06111B),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  Expanded(
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
                  const SizedBox(height: 7),
                  _MobileBottomNavigation(
                    selectedIndex: widget.selectedIndex,
                    activeSlipCount: widget.activeSlipCount,
                    onBoard: widget.onBoard,
                    onGameMarkets: widget.onGameMarkets,
                    onSlip: () => _scaffoldKey.currentState?.openEndDrawer(),
                    onMenu: () => _scaffoldKey.currentState?.openDrawer(),
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

class _MobileBottomNavigation extends StatelessWidget {
  const _MobileBottomNavigation({
    required this.selectedIndex,
    required this.activeSlipCount,
    required this.onBoard,
    required this.onGameMarkets,
    required this.onSlip,
    required this.onMenu,
  });

  final int selectedIndex;
  final int activeSlipCount;
  final VoidCallback? onBoard;
  final VoidCallback? onGameMarkets;
  final VoidCallback onSlip;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xF207111B),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.borderGold),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18)],
      ),
      child: Row(
        children: [
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-board'),
              icon: Icons.dashboard_customize_outlined,
              label: 'BOARD',
              selected: selectedIndex == 0,
              onTap: onBoard,
            ),
          ),
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-game-markets'),
              icon: Icons.sports_rounded,
              label: 'GAMES',
              selected: selectedIndex == 1,
              onTap: onGameMarkets,
            ),
          ),
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-active-slip'),
              icon: Icons.receipt_long_rounded,
              label: 'SLIP',
              selected: selectedIndex == 2,
              badge: activeSlipCount,
              onTap: onSlip,
            ),
          ),
          Expanded(
            child: _MobileNavItem(
              key: const ValueKey('mobile-nav-menu'),
              icon: Icons.grid_view_rounded,
              label: 'MENU',
              selected: selectedIndex == 3,
              onTap: onMenu,
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.gold : AppColors.textSecondary;
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
                ? AppColors.gold.withValues(alpha: .11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AppColors.gold : Colors.transparent,
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
                            color: Color(0xFF06111B),
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
