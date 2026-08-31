import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/engagement_tracker.dart';
import '../services/player_image_resolver.dart';

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
    this.cacheIdentity = '',
    this.player = '',
    this.sport = '',
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final bool showShimmer;
  final String cacheIdentity;
  final String player;
  final String sport;

  static String _stableCacheKey(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('pi_photo')
      ..remove('revision');
    final nested = query['url'];
    if (nested != null && nested.isNotEmpty) {
      query['url'] = _stableCacheKey(nested);
    }
    return uri
        .replace(queryParameters: query.isEmpty ? null : query)
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final sourceImage = imageUrl.trim().isNotEmpty
        ? imageUrl
        : resolveCanonicalPlayerImagePath(
            player: player,
            sport: sport,
            identityKey: cacheIdentity,
          );
    if (sourceImage.isEmpty) {
      return _buildFallback();
    }

    final primaryUrl = resolvePlayerImagePath(
      sourceImage,
      // Web sports CDNs are loaded directly first. The API proxy remains the
      // retry path below, which avoids accepting an opaque provider/proxy
      // placeholder as a successfully rendered black player photo.
      useApiProxyForRemoteImages: !kIsWeb,
      identityKey: cacheIdentity,
    );
    final resolvedFallback = resolvePlayerImageFallbackPath(
      sourceImage,
      identityKey: cacheIdentity,
    );
    final retryUrl =
        resolvedFallback.isNotEmpty && resolvedFallback != primaryUrl
        ? resolvedFallback
        : primaryUrl != sourceImage
        ? sourceImage
        : '';
    final identityPrefix = cacheIdentity.trim().isEmpty
        ? ''
        : '${cacheIdentity.trim()}|';
    final primaryCacheKey = '$identityPrefix${_stableCacheKey(primaryUrl)}';
    final retryCacheKey = '$identityPrefix${_stableCacheKey(retryUrl)}';

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        key: ValueKey(primaryCacheKey),
        imageUrl: primaryUrl,
        cacheKey: primaryCacheKey,
        width: width,
        height: height,
        fit: fit,
        alignment: Alignment.center,
        imageBuilder: (context, imageProvider) => Stack(
          fit: StackFit.expand,
          children: [
            _buildFallback(),
            Image(
              image: imageProvider,
              fit: fit,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            ),
          ],
        ),
        // Enhanced rendering quality
        filterQuality: FilterQuality.high,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        // Keep the decoded athlete bitmap mounted while refreshed prop data
        // resolves to the same (or a revised) image URL. Replacing it with a
        // placeholder on every feed rebuild caused visible photo blinking.
        useOldImageOnUrlChange: true,
        placeholder: (context, url) => _buildFallback(),
        // Enhanced error handling
        errorWidget: (context, url, error) {
          if (retryUrl.isEmpty || retryUrl == primaryUrl) {
            return _buildFallback();
          }
          return CachedNetworkImage(
            key: ValueKey(retryCacheKey),
            imageUrl: retryUrl,
            cacheKey: retryCacheKey,
            width: width,
            height: height,
            fit: fit,
            alignment: Alignment.center,
            imageBuilder: (context, imageProvider) => Stack(
              fit: StackFit.expand,
              children: [
                _buildFallback(),
                Image(
                  image: imageProvider,
                  fit: fit,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ],
            ),
            filterQuality: FilterQuality.high,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            useOldImageOnUrlChange: true,
            memCacheWidth: width != null ? (width! * 2).toInt() : null,
            memCacheHeight: height != null ? (height! * 2).toInt() : null,
            maxWidthDiskCache: 800,
            maxHeightDiskCache: 800,
            placeholder: (_, _) => _buildFallback(),
            errorWidget: (_, failedUrl, _) {
              EngagementTracker.instance.recordOperational(
                'MEDIA_FAILURE',
                endpoint: failedUrl,
                provider: Uri.tryParse(failedUrl)?.host ?? 'unknown',
                mediaType: 'player_photo',
              );
              return _buildFallback();
            },
          );
        },
        // Memory cache configuration
        memCacheWidth: width != null ? (width! * 2).toInt() : null,
        memCacheHeight: height != null ? (height! * 2).toInt() : null,
        // Use 2x resolution for retina displays
        maxWidthDiskCache: 800,
        maxHeightDiskCache: 800,
      ),
    );
  }

  // ignore: unused_element
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
          color: const Color(0xFFD4AF37).withValues(alpha: 0.72),
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
    this.cacheIdentity = '',
    this.player = '',
    this.sport = '',
  });

  final String imageUrl;
  final double radius;
  final IconData fallbackIcon;
  final String cacheIdentity;
  final String player;
  final String sport;

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
      cacheIdentity: cacheIdentity,
      player: player,
      sport: sport,
    );
  }
}
