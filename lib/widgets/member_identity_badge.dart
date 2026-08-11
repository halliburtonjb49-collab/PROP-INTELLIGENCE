import 'dart:async';

import 'package:flutter/material.dart';

import '../models/member_identity.dart';
import '../services/app_sound_service.dart';
import '../theme/app_colors.dart';

class MemberIdentityBadge extends StatelessWidget {
  const MemberIdentityBadge({
    super.key,
    required this.username,
    required this.role,
    this.founderNumber,
    this.compact = false,
    this.showUsername = true,
  });

  final String username;
  final MemberIdentityRole role;
  final int? founderNumber;
  final bool compact;
  final bool showUsername;

  String get founderLabel => founderNumber == null
      ? role.label
      : '${role.label} #${founderNumber!.toString().padLeft(3, '0')}';

  @override
  Widget build(BuildContext context) {
    final imageSize = compact ? 64.0 : 84.0;
    return Semantics(
      button: true,
      label: 'View @$username $founderLabel profile',
      child: InkWell(
        key: ValueKey('member-identity-$username'),
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          unawaited(AppSoundService.instance.play(AppSoundEvent.button));
          _showProfile(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoleImage(role: role, size: imageSize),
              if (showUsername) ...[
                SizedBox(width: compact ? 5 : 8),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@$username',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: role == MemberIdentityRole.owner
                              ? AppColors.gold
                              : Colors.white,
                          fontSize: compact ? 11 : 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        founderLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: role == MemberIdentityRole.admin
                              ? AppColors.blue
                              : AppColors.gold,
                          fontSize: compact ? 8 : 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProfile(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('member-identity-profile'),
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.gold),
      ),
      title: Row(
        children: [
          _RoleImage(role: role, size: 160),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@$username', overflow: TextOverflow.ellipsis),
                Text(
                  founderLabel,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Text(
        role.description,
        style: const TextStyle(color: AppColors.silver, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    ),
  );
}

class _RoleImage extends StatelessWidget {
  const _RoleImage({required this.role, required this.size});

  final MemberIdentityRole role;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = role.assetPath;
    if (asset == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.panelLight,
          border: Border.all(color: AppColors.gunmetalLight),
        ),
        child: Icon(Icons.person_outline_rounded, size: size * .55),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .16),
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
