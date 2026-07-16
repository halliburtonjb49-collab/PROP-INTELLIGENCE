import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AuthSessionState {
  final bool ready;
  final bool authenticated;
  final bool isPremium;
  final String? userId;
  final String? email;
  final String message;

  const AuthSessionState({
    required this.ready,
    required this.authenticated,
    required this.isPremium,
    required this.userId,
    required this.email,
    required this.message,
  });

  const AuthSessionState.loading()
    : ready = false,
      authenticated = false,
      isPremium = false,
      userId = null,
      email = null,
      message = 'Initializing auth...';

  const AuthSessionState.unavailable()
    : ready = true,
      authenticated = false,
      isPremium = false,
      userId = null,
      email = null,
      message = 'Supabase auth is not configured.';

  const AuthSessionState.signedOut()
    : ready = true,
      authenticated = false,
      isPremium = false,
      userId = null,
      email = null,
      message = 'Signed out';
}

class AuthManager {
  AuthManager._();

  static final AuthManager instance = AuthManager._();

  final ValueNotifier<AuthSessionState> sessionState =
      ValueNotifier<AuthSessionState>(const AuthSessionState.loading());

  StreamSubscription<AuthState>? _authSubscription;

  SupabaseClient? get _client => SupabaseService.client;

  void attach() {
    final client = _client;
    if (client == null) {
      sessionState.value = const AuthSessionState.unavailable();
      return;
    }

    unawaited(_setSession(client.auth.currentSession));

    _authSubscription ??= client.auth.onAuthStateChange.listen((event) {
      unawaited(_setSession(event.session));
    });
  }

  Future<void> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? profileMetadata,
  }) async {
    final client = _requireClient();

    await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: profileMetadata,
    );

    await saveProfileTrackingState({
      'last_auth_event': 'signup',
      'email': email.trim(),
    });

    await _setSession(client.auth.currentSession);
  }

  Future<void> signIn({required String email, required String password}) async {
    final client = _requireClient();

    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    await saveProfileTrackingState({
      'last_auth_event': 'signin',
      'email': email.trim(),
    });

    await _setSession(client.auth.currentSession);
  }

  Future<void> signOut() async {
    final client = _requireClient();
    await client.auth.signOut();
    sessionState.value = const AuthSessionState.signedOut();
  }

  Future<void> refreshSessionState() async {
    final client = _client;
    if (client == null) {
      sessionState.value = const AuthSessionState.unavailable();
      return;
    }
    await _setSession(client.auth.currentSession);
  }

  Future<void> saveProfileTrackingState(
    Map<String, dynamic> trackingState,
  ) async {
    final client = _requireClient();
    final user = client.auth.currentUser;
    if (user == null) {
      return;
    }

    final payload = <String, dynamic>{
      'user_id': user.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      ...trackingState,
    };

    // Expected table schema:
    // user_profile_tracking_states(user_id text primary key, updated_at timestamptz, ...json fields)
    await client.from('user_profile_tracking_states').upsert(payload);
  }

  Future<void> upsertUserProfile({
    String? displayName,
    String? avatarUrl,
  }) async {
    final client = _requireClient();
    final user = client.auth.currentUser;
    if (user == null) {
      return;
    }

    final payload = <String, dynamic>{
      'id': user.id,
      'email': user.email,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    // Expected table schema:
    // user_profiles(id text primary key, email text, display_name text, avatar_url text, updated_at timestamptz)
    await client.from('user_profiles').upsert(payload);
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Supabase is not initialized. Provide SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
    return client;
  }

  Future<void> _setSession(Session? session) async {
    final user = session?.user;
    if (user == null) {
      sessionState.value = const AuthSessionState.signedOut();
      return;
    }

    var isPremium = false;
    try {
      final row = await _client
          ?.from('user_profiles')
          .select('is_premium')
          .eq('id', user.id)
          .maybeSingle();
      if (row is Map<String, dynamic>) {
        final raw = row['is_premium'];
        if (raw is bool) {
          isPremium = raw;
        }
      }
    } catch (_) {
      // Keep auth usable even if profile table/column is not ready.
      isPremium = false;
    }

    sessionState.value = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium: isPremium,
      userId: user.id,
      email: user.email,
      message: 'Authenticated',
    );
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
  }
}
