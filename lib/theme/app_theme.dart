import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'prop_intelligence_colors.dart';

abstract final class AppTheme {
  static ThemeData get theme {
    final baseTheme = ThemeData.dark();
    return baseTheme.copyWith(
      scaffoldBackgroundColor: PropIntelligenceColors.darkCanvasBg,
      cardColor: PropIntelligenceColors.darkCardBg,
      dividerColor: Colors.white10,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppColors.gold,
        secondary: AppColors.blue,
        surface: AppColors.panel,
      ),
      textTheme: baseTheme.textTheme
          .apply(
            bodyColor: PropIntelligenceColors.metallicSilver,
            displayColor: Colors.white,
          )
          .copyWith(
            titleLarge: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: AppColors.white),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.panel),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.sidebar,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        helperStyle: const TextStyle(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.4),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.panelLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: const TextStyle(color: AppColors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 450),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.background,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.background,
          elevation: 0,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .35,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.white,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: .3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .25,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return PropIntelligenceColors.premiumGold;
          }
          if (states.contains(WidgetState.hovered)) {
            return PropIntelligenceColors.premiumGold.withValues(alpha: .9);
          }
          return PropIntelligenceColors.premiumGold.withValues(alpha: .82);
        }),
        trackColor: WidgetStateProperty.all(AppColors.panelLight),
        trackBorderColor: WidgetStateProperty.all(AppColors.borderGold),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(9),
        interactive: true,
      ),
    );
  }
}
