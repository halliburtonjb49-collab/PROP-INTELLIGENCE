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
      return _optimizedWebPlayerImage(trimmed);
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

String _optimizedWebPlayerImage(String imageUrl) {
  final imageUri = Uri.tryParse(imageUrl);
  if (imageUri == null ||
      imageUri.host.toLowerCase() != 'a.espncdn.com' ||
      !imageUri.path.startsWith('/i/headshots/')) {
    return imageUrl;
  }
  // ESPN originals can exceed 300 KB. The official combiner returns a
  // card-sized CORS-enabled image, cutting first-paint transfer dramatically.
  return Uri.https('a.espncdn.com', '/combiner/i', {
    'img': imageUri.path,
    'w': '160',
    'h': '160',
    'scale': 'crop',
    'cquality': '80',
    'location': 'origin',
  }).toString();
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
