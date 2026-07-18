import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

enum SubscriptionTier {
  free,
  core,
  edge;

  bool get hasCoreAccess => this == core || this == edge;
  bool get hasEdgeAccess => this == edge;

  static SubscriptionTier fromDatabase(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'core' => core,
      'edge' || 'pro' || 'elite' => edge,
      _ => free,
    };
  }
}

class AuthSessionState {
  final bool ready;
  final bool authenticated;
  final bool isPremium;
  final SubscriptionTier subscriptionTier;
  final String role;
  final String? userId;
  final String? email;
  final String message;

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';
  bool get isTester => role == 'tester';
  bool get hasCoreAccess =>
      subscriptionTier.hasCoreAccess || isOwner || isAdmin || isTester;
  bool get hasEdgeAccess =>
      subscriptionTier.hasEdgeAccess || isOwner || isAdmin || isTester;

  const AuthSessionState({
    required this.ready,
    required this.authenticated,
    required this.isPremium,
    required this.subscriptionTier,
    required this.role,
    required this.userId,
    required this.email,
    required this.message,
  });

  const AuthSessionState.loading()
    : ready = false,
      authenticated = false,
      isPremium = false,
      subscriptionTier = SubscriptionTier.free,
      role = 'user',
      userId = null,
      email = null,
      message = 'Initializing auth...';

  const AuthSessionState.unavailable()
    : ready = true,
      authenticated = false,
      isPremium = false,
      subscriptionTier = SubscriptionTier.free,
      role = 'user',
      userId = null,
      email = null,
      message = 'Supabase auth is not configured.';

  const AuthSessionState.signedOut()
    : ready = true,
      authenticated = false,
      isPremium = false,
      subscriptionTier = SubscriptionTier.free,
      role = 'user',
      userId = null,
      email = null,
      message = 'Signed out';
}

class AuthManager {
  AuthManager._();

  static final AuthManager instance = AuthManager._();

  final ValueNotifier<AuthSessionState> sessionState =
      ValueNotifier<AuthSessionState>(const AuthSessionState.loading());
  final ValueNotifier<bool> passwordRecoveryRequested = ValueNotifier<bool>(
    false,
  );

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
      if (event.event == AuthChangeEvent.passwordRecovery) {
        passwordRecoveryRequested.value = true;
      }
      unawaited(_setSession(event.session));
    });
  }

  Future<void> completePasswordRecovery(String password) async {
    final trimmedPassword = password.trim();
    if (trimmedPassword.length < 8) {
      throw ArgumentError('Password must be at least 8 characters.');
    }

    final client = _requireClient();
    if (client.auth.currentSession == null) {
      throw StateError(
        'This password-reset link has expired. Request a new link and try again.',
      );
    }

    await client.auth.updateUser(UserAttributes(password: trimmedPassword));
    passwordRecoveryRequested.value = false;
    await _setSession(client.auth.currentSession);
  }

  Future<void> cancelPasswordRecovery() async {
    passwordRecoveryRequested.value = false;
    await signOut();
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
    passwordRecoveryRequested.value = false;
    sessionState.value = const AuthSessionState.signedOut();
  }

  Future<Map<String, dynamic>> assignUserRole({
    required String email,
    required String role,
  }) async {
    if (!sessionState.value.isOwner) {
      throw StateError('Only an owner can assign account roles.');
    }

    final normalizedEmail = email.trim().toLowerCase();
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Enter the user email address.');
    }
    if (!const {'admin', 'tester', 'user'}.contains(normalizedRole)) {
      throw ArgumentError('Role must be admin, tester, or user.');
    }

    final response = await _requireClient().rpc(
      'assign_user_role',
      params: {'target_email': normalizedEmail, 'target_role': normalizedRole},
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'email': normalizedEmail, 'role': normalizedRole};
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

    final role = (user.appMetadata['role'] ?? 'user')
        .toString()
        .trim()
        .toLowerCase();
    final hasPrivilegedRole =
        role == 'owner' || role == 'admin' || role == 'tester';
    var isPremium = hasPrivilegedRole;
    var subscriptionTier = hasPrivilegedRole
        ? SubscriptionTier.edge
        : SubscriptionTier.free;
    try {
      final row = await _client
          ?.from('user_profiles')
          .select('is_premium, subscription_tier')
          .eq('id', user.id)
          .maybeSingle();
      if (row is Map<String, dynamic>) {
        final raw = row['is_premium'];
        if (raw is bool) {
          isPremium = raw || hasPrivilegedRole;
        }
        subscriptionTier = hasPrivilegedRole
            ? SubscriptionTier.edge
            : SubscriptionTier.fromDatabase(row['subscription_tier']);
        // Preserve full access for legacy premium accounts during migration.
        if (subscriptionTier == SubscriptionTier.free && raw == true) {
          subscriptionTier = SubscriptionTier.edge;
        }
      }
    } catch (_) {
      // Privileged roles retain full access even if profile lookup is unavailable.
      isPremium = hasPrivilegedRole;
      subscriptionTier = hasPrivilegedRole
          ? SubscriptionTier.edge
          : SubscriptionTier.free;
    }

    sessionState.value = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium: isPremium,
      subscriptionTier: subscriptionTier,
      role: role,
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
