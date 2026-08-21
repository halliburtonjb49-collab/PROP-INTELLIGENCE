import 'package:flutter/foundation.dart';

import 'api_service.dart';

String resolvePlayerImagePath(
  String rawPath, {
  String? apiBaseUrl,
  bool? useApiProxyForRemoteImages,
}) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    // Browser image requests can use these CORS-enabled sports CDNs directly,
    // avoiding a second network hop through Render for every player card.
    if (!(useApiProxyForRemoteImages ?? !kIsWeb)) {
      return trimmed;
    }
    return _proxySupportedPlayerImage(
      trimmed,
      apiBaseUrl: apiBaseUrl ?? ApiService.baseUrl,
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
String resolvePlayerImageFallbackPath(String rawPath, {String? apiBaseUrl}) {
  final trimmed = rawPath.trim();
  if (!trimmed.startsWith('https://')) return '';
  final fallback = _proxySupportedPlayerImage(
    trimmed,
    apiBaseUrl: apiBaseUrl ?? ApiService.baseUrl,
  );
  return fallback == trimmed ? '' : fallback;
}

String _proxySupportedPlayerImage(
  String imageUrl, {
  required String apiBaseUrl,
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
  return Uri.parse(
    '$normalizedBase/player-image-proxy',
  ).replace(queryParameters: {'url': imageUrl}).toString();
}

const Set<String> _proxiedImageHosts = {'a.espncdn.com', 'img.mlbstatic.com'};
