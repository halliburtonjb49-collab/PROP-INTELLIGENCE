import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get theme {
    const base = AppColors.bgBase;
    const panel = AppColors.bgPanel;
    const gold = AppColors.goldMid;
    const goldHi = AppColors.goldHighlight;
    const chrome = AppColors.chromeMid;
    const chromeLine = AppColors.chromeShadow;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      scaffoldBackgroundColor: base,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        onPrimary: base,
        secondary: chrome,
        onSecondary: base,
        surface: panel,
        onSurface: AppColors.chromeLight,
        error: AppColors.red,
        onError: base,
        outline: chromeLine,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgPanel,
        foregroundColor: AppColors.chromeLight,
        elevation: 0,
        iconTheme: IconThemeData(color: chrome),
        titleTextStyle: TextStyle(
          color: AppColors.chromeLight,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.goldShadow)),
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w900,
          letterSpacing: -.35,
          height: 1.05,
        ),
        headlineSmall: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w900,
          letterSpacing: -.15,
          height: 1.08,
        ),
        bodyLarge: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        bodyMedium: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w600,
          height: 1.22,
        ),
        bodySmall: TextStyle(
          color: chrome,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: goldHi,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
          height: 1.08,
        ),
        titleMedium: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
          height: 1.12,
        ),
        titleSmall: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w800,
          letterSpacing: .15,
          height: 1.12,
        ),
        labelLarge: TextStyle(
          color: base,
          fontWeight: FontWeight.w900,
          letterSpacing: .45,
          height: 1,
        ),
        labelMedium: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w900,
          letterSpacing: .35,
          height: 1,
        ),
        labelSmall: TextStyle(
          color: chrome,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
          height: 1,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 40),
          backgroundColor: gold,
          foregroundColor: base,
          disabledBackgroundColor: AppColors.goldShadow,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .45,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          backgroundColor: gold,
          foregroundColor: base,
          disabledBackgroundColor: AppColors.goldShadow,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .45,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          foregroundColor: AppColors.chromeLight,
          side: const BorderSide(color: chrome),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 38),
          foregroundColor: goldHi,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: chromeLine),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        hintStyle: const TextStyle(color: chrome),
        labelStyle: const TextStyle(color: chrome),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: chromeLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: chromeLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: base,
        selectedItemColor: goldHi,
        unselectedItemColor: chrome,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: base,
        indicatorColor: AppColors.goldShadow.withValues(alpha: .4),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? goldHi : chrome);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(color: selected ? goldHi : chrome, fontSize: 12);
        }),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: base,
        indicatorColor: AppColors.goldShadow,
        selectedIconTheme: IconThemeData(color: goldHi, size: 21),
        unselectedIconTheme: IconThemeData(color: chrome, size: 20),
        selectedLabelTextStyle: TextStyle(
          color: goldHi,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .35,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: chrome,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: goldHi,
        unselectedLabelColor: chrome,
        indicatorColor: gold,
        dividerColor: chromeLine,
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        minTileHeight: 42,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        iconColor: chrome,
        textColor: AppColors.chromeLight,
        titleTextStyle: TextStyle(
          color: AppColors.chromeLight,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
        ),
        subtitleTextStyle: TextStyle(
          color: chrome,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(AppColors.bgPanelAlt),
        dataRowColor: WidgetStatePropertyAll(panel),
        dividerThickness: .5,
        horizontalMargin: 14,
        columnSpacing: 20,
        headingTextStyle: TextStyle(
          color: goldHi,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: .45,
        ),
        dataTextStyle: TextStyle(
          color: AppColors.chromeLight,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        textStyle: const TextStyle(
          color: AppColors.chromeLight,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: chromeLine),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.goldShadow),
        ),
        textStyle: const TextStyle(
          color: AppColors.chromeLight,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        waitDuration: const Duration(milliseconds: 450),
      ),
      iconTheme: const IconThemeData(color: chrome),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: chrome),
      ),
      dividerTheme: const DividerThemeData(color: chromeLine, thickness: .5),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: const TextStyle(
          color: AppColors.chromeLight,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        contentTextStyle: const TextStyle(color: chrome, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: gold,
        secondarySelectedColor: gold,
        checkmarkColor: base,
        labelStyle: const TextStyle(
          color: AppColors.chromeLight,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .25,
        ),
        secondaryLabelStyle: const TextStyle(
          color: base,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
        side: const BorderSide(color: chromeLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgPanel,
        modalBackgroundColor: AppColors.bgPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          side: BorderSide(color: AppColors.goldShadow),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: panel,
        contentTextStyle: const TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.goldShadow),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? gold : chrome,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.goldShadow
              : chromeLine,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? gold : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(base),
        side: const BorderSide(color: chrome),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? gold : chrome,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: gold,
        linearTrackColor: chromeLine,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(gold.withValues(alpha: .82)),
        trackColor: const WidgetStatePropertyAll(panel),
        trackBorderColor: const WidgetStatePropertyAll(chromeLine),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(9),
        interactive: true,
      ),
    );
  }
}
