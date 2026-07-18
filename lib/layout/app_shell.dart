import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.leftSidebar,
    required this.topNavigation,
    required this.content,
    required this.rightSidebar,
  });

  final Widget leftSidebar;
  final Widget topNavigation;
  final Widget content;
  final Widget rightSidebar;

  static const double leftWidth = 245;
  static const double rightWidth = 340;
  static const double topHeight = 72;

  ({double left, double right}) _sidebarWidths(double width) {
    // Flutter reports logical pixels. On a typical 150% scaled Windows display
    // a 1920px window is only 1280 logical pixels wide, so using the full-size
    // desktop rails leaves almost no room for the primary workspace.
    if (width < 1360) {
      return (left: 180, right: 240);
    }
    if (width < 1600) {
      return (left: 210, right: 285);
    }
    return (left: leftWidth, right: rightWidth);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _sidebarWidths(constraints.maxWidth);
        return Scaffold(
          backgroundColor: AppColors.background,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF07131E), AppColors.background],
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  SizedBox(width: widths.left, child: leftSidebar),
                  Container(width: 1, color: AppColors.border),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(height: topHeight, child: topNavigation),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66000000),
                                      blurRadius: 22,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: content,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, color: AppColors.border),
                  SizedBox(width: widths.right, child: rightSidebar),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
