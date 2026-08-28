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
        bodyLarge: TextStyle(color: AppColors.chromeLight),
        bodyMedium: TextStyle(color: AppColors.chromeLight),
        bodySmall: TextStyle(color: chrome),
        titleLarge: TextStyle(
          color: goldHi,
          fontWeight: FontWeight.w900,
          letterSpacing: .4,
        ),
        titleMedium: TextStyle(
          color: AppColors.chromeLight,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: TextStyle(color: base),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: base,
          disabledBackgroundColor: AppColors.goldShadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: base,
          disabledBackgroundColor: AppColors.goldShadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.chromeLight,
          side: const BorderSide(color: chrome),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: goldHi),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: chromeLine),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        hintStyle: const TextStyle(color: chrome),
        labelStyle: const TextStyle(color: chrome),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: chromeLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: chromeLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
