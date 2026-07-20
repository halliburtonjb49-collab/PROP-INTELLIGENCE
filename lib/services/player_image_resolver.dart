import 'api_service.dart';

String resolvePlayerImagePath(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }

  final base = ApiService.baseUrl.trim();
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
