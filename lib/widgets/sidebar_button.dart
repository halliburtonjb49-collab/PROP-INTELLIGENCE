import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_sound_service.dart';
import '../services/auth_manager.dart';
import '../theme/app_colors.dart' as app_colors;
import 'feature_tier_badge.dart';

class SidebarButton extends StatelessWidget {
  static const double standardHeight = 44;
  static const double standardIconSize = 17;
  static const double standardFontSize = 10;
  final String label;
  final bool selected;
  final SubscriptionTier? requiredTier;
  final bool hasProUpgrade;
  final bool showGoldBar;
  final String? badge;
  final List<IconData>? leadingIcons;
  final List<Color>? leadingIconColors;
  final List<String>? leadingEmojis;
  final List<Color>? leadingEmojiGradient;
  final String? leadingImagePath;
  final IconData? trailingIcon;
  final Key? trailingIconKey;
  final VoidCallback? onTap;

  const SidebarButton({
    super.key,
    required this.label,
    this.selected = false,
    this.requiredTier,
    this.hasProUpgrade = false,
    this.showGoldBar = false,
    this.badge,
    this.leadingIcons,
    this.leadingIconColors,
    this.leadingEmojis,
    this.leadingEmojiGradient,
    this.leadingImagePath,
    this.trailingIcon,
    this.trailingIconKey,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final session = AuthManager.instance.sessionState.value;
    final hasRequiredAccess = switch (requiredTier) {
      null => true,
      SubscriptionTier.free => true,
      SubscriptionTier.core => session.hasCoreAccess,
      SubscriptionTier.edge => session.hasEdgeAccess,
    };
    final isLockedUpgrade = requiredTier != null && !hasRequiredAccess;
    final isActiveWatchlist = label.toUpperCase() == 'SLIP WATCHER';
    final watchlistHasActiveSlips =
        isActiveWatchlist && (int.tryParse((badge ?? '0').trim()) ?? 0) > 0;
    final textColor = selected || watchlistHasActiveSlips || isLockedUpgrade
        ? app_colors.AppColors.gold
        : Colors.white;
    final textWeight =
        selected || watchlistHasActiveSlips || isLockedUpgrade
        ? FontWeight.w900
        : FontWeight.w700;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              unawaited(AppSoundService.instance.play(AppSoundEvent.button));
              onTap!();
            },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: standardHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? app_colors.AppColors.gold.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? app_colors.AppColors.gold.withValues(alpha: 0.52)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (showGoldBar) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: selected
                      ? app_colors.AppColors.gold
                      : app_colors.AppColors.gold.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (leadingImagePath != null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors:
                          leadingEmojiGradient ??
                          const [Color(0xFF203246), Color(0xFF314A60)],
                    ),
                    border: Border.all(color: const Color(0x73FFC72C)),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      leadingImagePath!,
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ] else if (leadingEmojis != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: leadingEmojis!
                    .map(
                      (emoji) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors:
                                  leadingEmojiGradient ??
                                  const [Color(0xFF203246), Color(0xFF314A60)],
                            ),
                            border: Border.all(color: const Color(0x73FFC72C)),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(width: 8),
            ] else if (leadingIcons != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(leadingIcons!.length, (index) {
                  final icon = leadingIcons![index];
                  final color =
                      leadingIconColors != null &&
                          index < leadingIconColors!.length
                      ? leadingIconColors![index]
                      : textColor;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(icon, size: standardIconSize, color: color),
                  );
                }),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: label.contains('\n')
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 2,
                        softWrap: false,
                        style: TextStyle(
                          color: textColor,
                          fontSize: standardFontSize,
                          height: 1.15,
                          fontWeight: textWeight,
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  : Text(
                      label,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: textColor,
                        fontSize: standardFontSize,
                        height: 1.15,
                        fontWeight: textWeight,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
            if (trailingIcon != null) ...[
              Icon(
                trailingIcon,
                key: trailingIconKey,
                size: 14,
                color: app_colors.AppColors.gold,
              ),
              const SizedBox(width: 6),
            ],
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: app_colors.AppColors.gold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Color(0xFF07131F),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (badge == null && isLockedUpgrade)
              FeatureTierBadge(
                tier: requiredTier!,
                hasProUpgrade: hasProUpgrade,
              ),
          ],
        ),
      ),
    );
  }
}
