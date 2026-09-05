import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'web_session_bridge.dart';

class SupabaseService {
  SupabaseService._();

  static bool _initialized = false;
  static String? _runtimeSupabaseUrl;
  static String? _runtimeSupabaseAnonKey;
  static Future<Session?>? _webSessionRecovery;

  static void configure({required String url, required String anonKey}) {
    _runtimeSupabaseUrl = url.trim();
    _runtimeSupabaseAnonKey = anonKey.trim();
  }

  static String get _supabaseUrl {
    if ((_runtimeSupabaseUrl ?? '').isNotEmpty) {
      return _runtimeSupabaseUrl!;
    }
    return const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  }

  static String get _supabaseAnonKey {
    if ((_runtimeSupabaseAnonKey ?? '').isNotEmpty) {
      return _runtimeSupabaseAnonKey!;
    }
    return const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  }

  static bool get isConfigured =>
      _supabaseUrl.trim().isNotEmpty && _supabaseAnonKey.trim().isNotEmpty;

  static bool get isInitialized => _initialized;

  static SupabaseClient? get client {
    if (!_initialized) {
      return null;
    }
    return Supabase.instance.client;
  }

  static String? get persistedAccessToken => persistedWebAccessToken();

  static Future<Session?> recoverPersistedWebSession({
    bool forceRefresh = false,
  }) async {
    if (!_initialized) return null;
    final auth = Supabase.instance.client.auth;
    if (!forceRefresh && auth.currentSession != null) {
      return auth.currentSession;
    }
    final refreshToken = persistedWebRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return auth.currentSession;
    }
    final recovery = _webSessionRecovery ??= auth
        .setSession(
          refreshToken,
          accessToken: forceRefresh ? null : persistedWebAccessToken(),
        )
        .timeout(const Duration(seconds: 8))
        .then((response) => response.session);
    try {
      return await recovery;
    } finally {
      if (identical(_webSessionRecovery, recovery)) {
        _webSessionRecovery = null;
      }
    }
  }

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (!isConfigured) {
      debugPrint(
        'Supabase skipped: SUPABASE_URL/SUPABASE_ANON_KEY dart defines are missing.',
      );
      return;
    }

    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
        localStorage: SharedPreferencesLocalStorage(
          // Match supabase-js on pipropsintell.com. Marketing login, Google
          // OAuth, Flutter session restoration, sign-out, and protected prop
          // requests must all read and update one canonical session.
          persistSessionKey: 'sb-doncoxjilytojmnpukxi-auth-token',
        ),
      ),
    );

    _initialized = true;
    if (kIsWeb) {
      // Supabase.initialize has already restored its locally persisted
      // session. Do not hold the first frame behind a forced network token
      // exchange (previously up to eight seconds). Import the canonical
      // product-site session in the background; protected API requests can
      // use the restored/persisted access token immediately and already retry
      // once with a forced refresh if the server reports 401.
      unawaited(
        recoverPersistedWebSession(forceRefresh: true)
            .timeout(const Duration(seconds: 8))
            .then<void>((_) {})
            .catchError((Object error) {
              debugPrint('Supabase web session recovery deferred: $error');
            }),
      );
    }
    debugPrint('Supabase initialized successfully.');
  }
}
