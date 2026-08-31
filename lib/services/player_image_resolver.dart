import 'package:flutter/foundation.dart';

import 'api_service.dart';

// Increment only when the player-photo delivery pipeline changes. Keeping the
// revision in the shared resolver invalidates previously cached opaque/black
// responses across the board, slips, history, and specialty views together.
const String _playerImageRevision = '20260831-3';

String resolveCanonicalPlayerImagePath({
  required String player,
  required String sport,
  required String identityKey,
  String? apiBaseUrl,
}) {
  if (player.trim().isEmpty || sport.trim().isEmpty) return '';
  // Flutter web can decode a perfectly valid cross-origin JPEG as an opaque
  // black texture on iOS/WebKit. Route web photos through the public site's
  // same-origin API rewrite; native clients continue to use the API host.
  final resolvedBase = apiBaseUrl ?? (kIsWeb ? '' : ApiService.baseUrl);
  final base = resolvedBase.trim().replaceFirst(RegExp(r'/$'), '');
  return Uri.parse('$base/api/player-photo')
      .replace(
        queryParameters: {
          'player': player.trim(),
          'sport': sport.trim().toUpperCase(),
          if (identityKey.trim().isNotEmpty) 'identity': identityKey.trim(),
          'revision': _playerImageRevision,
        },
      )
      .toString();
}

String resolvePlayerImagePath(
  String rawPath, {
  String? apiBaseUrl,
  bool? useApiProxyForRemoteImages,
  String identityKey = '',
}) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    final revisedRemote = _versionedSupportedRemoteImage(
      trimmed,
      identityKey: identityKey,
    );
    // Browser image requests can use these CORS-enabled sports CDNs directly,
    // avoiding a second network hop through Render for every player card.
    if (!(useApiProxyForRemoteImages ?? !kIsWeb)) {
      return revisedRemote;
    }
    return _proxySupportedPlayerImage(
      revisedRemote,
      apiBaseUrl: apiBaseUrl ?? ApiService.baseUrl,
      identityKey: identityKey,
    );
  }

  final base = (apiBaseUrl ?? ApiService.baseUrl).trim();
  final normalizedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  const bundledPrefix = 'assets/players/';
  if (trimmed.startsWith(bundledPrefix)) {
    final filename = trimmed.substring(bundledPrefix.length);
    return '$normalizedBase/player-images/$filename';
  }
  if (trimmed.startsWith('assets/')) return trimmed;

  final normalizedPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return '$normalizedBase$normalizedPath';
}

/// Returns a server-proxied retry URL for supported remote player images.
/// Web cards use the smaller direct CDN image first, then this path if the
/// browser/CDN request fails. Native clients already use the proxy first.
String resolvePlayerImageFallbackPath(
  String rawPath, {
  String? apiBaseUrl,
  String identityKey = '',
}) {
  final trimmed = rawPath.trim();
  if (!trimmed.startsWith('https://')) return '';
  final fallback = _proxySupportedPlayerImage(
    _versionedSupportedRemoteImage(trimmed, identityKey: identityKey),
    apiBaseUrl: apiBaseUrl ?? ApiService.baseUrl,
    identityKey: identityKey,
  );
  return fallback == trimmed ? '' : fallback;
}

String _proxySupportedPlayerImage(
  String imageUrl, {
  required String apiBaseUrl,
  String identityKey = '',
}) {
  final imageUri = Uri.tryParse(imageUrl);
  final apiBase = apiBaseUrl.trim();
  final apiUri = Uri.tryParse(apiBase);
  if (imageUri == null ||
      apiUri == null ||
      apiUri.host.isEmpty ||
      imageUri.scheme != 'https' ||
      !_proxiedImageHosts.contains(imageUri.host.toLowerCase())) {
    return imageUrl;
  }

  final normalizedBase = apiBase.endsWith('/')
      ? apiBase.substring(0, apiBase.length - 1)
      : apiBase;
  return Uri.parse('$normalizedBase/player-image-proxy')
      .replace(
        queryParameters: {
          'url': imageUrl,
          'revision': _playerImageRevision,
          if (identityKey.trim().isNotEmpty) 'identity': identityKey.trim(),
        },
      )
      .toString();
}

String _versionedSupportedRemoteImage(
  String imageUrl, {
  String identityKey = '',
}) {
  final uri = Uri.tryParse(imageUrl);
  if (uri == null || !_proxiedImageHosts.contains(uri.host.toLowerCase())) {
    return imageUrl;
  }
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'pi_photo': _playerImageRevision,
          if (identityKey.trim().isNotEmpty) 'pi_identity': identityKey.trim(),
        },
      )
      .toString();
}

const Set<String> _proxiedImageHosts = {'a.espncdn.com', 'img.mlbstatic.com'};
