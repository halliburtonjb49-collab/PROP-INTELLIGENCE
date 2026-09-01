import 'dart:convert';

import 'package:web/web.dart' as web;

const _sessionKey = 'sb-doncoxjilytojmnpukxi-auth-token';

Map<String, dynamic>? _persistedSession() {
  final raw = web.window.localStorage.getItem(_sessionKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

String? persistedWebAccessToken() =>
    _persistedSession()?['access_token']?.toString();

String? persistedWebRefreshToken() =>
    _persistedSession()?['refresh_token']?.toString();
