import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color surfacePrimary = Color(0xFF09131F);
  static const Color surfaceSecondary = Color(0xFF0D1926);
  static const Color surfaceElevated = Color(0xFF122131);
  static const Color piGold = Color(0xFFD4AF37);
  static const Color piGoldBright = Color(0xFFE7C75A);
  static const Color piGoldMuted = Color(0xFF8F7A3B);
  static const Color coreSilver = Color(0xFFC0C7D1);
  static const Color positive = Color(0xFF35D6A0);
  static const Color informational = Color(0xFF79CBE8);
  static const Color destructive = Color(0xFFFF6B6B);
  static const Color textPrimary = Color(0xFFF4F7FA);
  static const Color bgBase = Color(0xFF080D15);
  static const Color bgPanel = Color(0xFF111822);

  static const Color goldHighlight = Color(0xFFFFE89D);
  static const Color goldLight = Color(0xFFDECA8A);
  static const Color goldMid = Color(0xFFA59256);
  static const Color goldShadow = Color(0xFF645529);

  static const Color chromeHighlight = Color(0xFFFEFEFF);
  static const Color chromeLight = Color(0xFFE5E2E2);
  static const Color chromeMid = Color(0xFF868080);
  static const Color chromeShadow = Color(0xFF29323E);

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldHighlight, goldMid, goldShadow],
  );

  static const LinearGradient chromeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [chromeHighlight, chromeMid, chromeShadow],
  );

  // Compatibility names used throughout the existing responsive workspace.
  static const Color background = bgBase;
  static const Color sidebar = Color(0xFF0C131D);
  static const Color panel = bgPanel;
  static const Color panelLight = Color(0xFF18212D);
  static const Color gunmetal = chromeShadow;
  static const Color gunmetalLight = Color(0xFF3D4856);
  static const Color border = chromeShadow;
  static const Color borderGold = goldShadow;
  static const Color gold = goldMid;
  static const Color goldMuted = goldShadow;
  static const Color white = chromeHighlight;
  static const Color silver = chromeLight;
  static const Color textSecondary = Color(0xFFB7B4B4);
  static const Color textMuted = chromeMid;
  static const Color blue = Color(0xFF9EDCE8);
  static const Color red = Color(0xFFD85A30);
  static const Color success = Color(0xFF56D38A);
  static const Color danger = Color(0xFFD85A30);
  static const Color warning = Color(0xFFFFE89D);
  static const Color goldSurface = Color(0xFF211C0B);
}
