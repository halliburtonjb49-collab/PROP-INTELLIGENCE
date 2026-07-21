import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Professional player image widget with enhanced rendering quality,
/// progressive loading, and improved error handling
class PlayerImageWidget extends StatelessWidget {
  const PlayerImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.person,
    this.fallbackIconSize = 32,
    this.showShimmer = true,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final bool showShimmer;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return _buildFallback();
    }

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        // Enhanced rendering quality
        filterQuality: FilterQuality.high,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 200),
        // Progressive loading placeholder
        placeholder: (context, url) =>
            showShimmer ? _buildShimmerPlaceholder() : _buildFallback(),
        // Enhanced error handling
        errorWidget: (context, url, error) => _buildFallback(),
        // Memory cache configuration
        memCacheWidth: width != null ? (width! * 2).toInt() : null,
        memCacheHeight: height != null ? (height! * 2).toInt() : null,
        // Use 2x resolution for retina displays
        maxWidthDiskCache: 800,
        maxHeightDiskCache: 800,
      ),
    );
  }

  Widget _buildShimmerPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A2332),
            const Color(0xFF0E1621),
            const Color(0xFF1A2332),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: fallbackIconSize * 0.7,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2332), Color(0xFF0E1621)],
        ),
      ),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: fallbackIconSize,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

/// Circular avatar version of player image
class PlayerAvatarWidget extends StatelessWidget {
  const PlayerAvatarWidget({
    super.key,
    required this.imageUrl,
    this.radius = 24,
    this.fallbackIcon = Icons.person,
  });

  final String imageUrl;
  final double radius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return PlayerImageWidget(
      imageUrl: imageUrl,
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(radius),
      fallbackIcon: fallbackIcon,
      fallbackIconSize: radius,
    );
  }
}
