import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supabase_service.dart';

const Set<String> _ownerEmails = {
  'propsintell@gmail.com',
};
const Set<String> _ownerUserIds = {'7fdb460c-dcaa-42ac-89c1-e9950b9b9c55'};

@visibleForTesting
bool isPasswordRecoveryUri(Uri uri) =>
    uri.queryParameters['auth_action'] == 'recovery' ||
    uri.fragment.split('&').contains('type=recovery');

@visibleForTesting
String resolveAccountRole({
  required String? email,
  required Object? role,
  String? userId,
}) {
  if (_ownerUserIds.contains(userId?.trim().toLowerCase())) {
    return 'owner';
  }
  final normalizedEmail = email?.trim().toLowerCase() ?? '';
  if (_ownerEmails.contains(normalizedEmail)) {
    return 'owner';
  }
  final normalizedRole = role?.toString().trim().toLowerCase() ?? '';
  // Owner access is bound only to the verified UUID/email above. Never let
  // mutable token metadata promote a second account to owner.
  return const {'admin', 'tester'}.contains(normalizedRole)
      ? normalizedRole
      : 'user';
}

enum SubscriptionTier {
  free,
  core,
  edge;

  bool get hasCoreAccess => this == core || this == edge;
  bool get hasEdgeAccess => this == edge;
  String get displayName => switch (this) {
    free => 'Free',
    core => 'Core',
    edge => 'Pro',
  };

  static SubscriptionTier fromDatabase(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'core' => core,
      'edge' || 'pro' || 'elite' => edge,
      _ => free,
    };
  }
}

class AppChangeRequest {
  const AppChangeRequest({
    required this.id,
    required this.requesterEmail,
    required this.title,
    required this.description,
    required this.status,
    required this.ownerResponse,
    required this.createdAt,
    required this.reviewedAt,
  });

  final int id;
  final String requesterEmail;
  final String title;
  final String description;
  final String status;
  final String? ownerResponse;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  bool get isPending => status == 'pending';

  factory AppChangeRequest.fromJson(Map<String, dynamic> json) {
    return AppChangeRequest(
      id: (json['id'] as num?)?.toInt() ?? 0,
      requesterEmail: json['requester_email']?.toString() ?? 'Unknown admin',
      title: json['title']?.toString() ?? 'Untitled request',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString().toLowerCase() ?? 'pending',
      ownerResponse: json['owner_response']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      reviewedAt: DateTime.tryParse(json['reviewed_at']?.toString() ?? ''),
    );
  }
}

class AuthSessionState {
  final bool ready;
  final bool authenticated;
  final bool isPremium;
  final SubscriptionTier subscriptionTier;
  final SubscriptionTier? accessPreviewTier;
  final String role;
  final String? userId;
  final String? email;
  final String? username;
  final String? avatarUrl;
  final String? assignedMemberRole;
  final int? founderNumber;
  final String message;

  String get normalizedRole => role.trim().toLowerCase();
  String get normalizedAssignedMemberRole =>
      assignedMemberRole?.trim().toLowerCase() ?? '';
  bool get isOwner => normalizedRole == 'owner';
  bool get isAdmin =>
      normalizedRole == 'admin' || normalizedAssignedMemberRole == 'admin';
  bool get isTester =>
      normalizedRole == 'tester' || normalizedAssignedMemberRole == 'tester';
  bool get requiresPaidPlan =>
      authenticated &&
      !isOwner &&
      !isAdmin &&
      !isTester &&
      effectiveSubscriptionTier == SubscriptionTier.free;
  bool get isAccessPreviewActive => isOwner && accessPreviewTier != null;
  SubscriptionTier get grantedSubscriptionTier =>
      switch (assignedMemberRole?.trim().toLowerCase()) {
        'core' => SubscriptionTier.core,
        'pro' || 'pro_founder' || 'edge' => SubscriptionTier.edge,
        _ => SubscriptionTier.free,
      };
  SubscriptionTier get effectiveSubscriptionTier {
    if (isAccessPreviewActive) return accessPreviewTier!;
    return subscriptionTier.index >= grantedSubscriptionTier.index
        ? subscriptionTier
        : grantedSubscriptionTier;
  }

  bool get hasCoreAccess => isAccessPreviewActive
      ? effectiveSubscriptionTier.hasCoreAccess
      : effectiveSubscriptionTier.hasCoreAccess ||
            isOwner ||
            isAdmin ||
            isTester;
  bool get hasEdgeAccess => isAccessPreviewActive
      ? effectiveSubscriptionTier.hasEdgeAccess
      : effectiveSubscriptionTier.hasEdgeAccess ||
            isOwner ||
            isAdmin ||
            isTester;

  const AuthSessionState({
    required this.ready,
    required this.authenticated,
    required this.isPremium,
    required this.subscriptionTier,
    this.accessPreviewTier,
    required this.role,
    required this.userId,
    required this.email,
    this.username,
    this.avatarUrl,
    this.assignedMemberRole,
    this.founderNumber,
    required this.message,
  });

  const AuthSessionState.loading()
    : ready = false,
      authenticated = false,
      isPremium = false,
      subscriptionTier = SubscriptionTier.free,
      accessPreviewTier = null,
      role = 'user',
      userId = null,
      email = null,
      username = null,
      avatarUrl = null,
      assignedMemberRole = null,
      founderNumber = null,
      message = 'Initializing auth...';

  const AuthSessionState.unavailable()
    : ready = true,
      authenticated = false,
      isPremium = false,
      subscriptionTier = SubscriptionTier.free,
      accessPreviewTier = null,
      role = 'user',
      userId = null,
      email = null,
      username = null,
      avatarUrl = null,
      assignedMemberRole = null,
      founderNumber = null,
      message = 'Supabase auth is not configured.';

  const AuthSessionState.signedOut()
    : ready = true,
      authenticated = false,
      isPremium = false,
      subscriptionTier = SubscriptionTier.free,
      accessPreviewTier = null,
      role = 'user',
      userId = null,
      email = null,
      username = null,
      avatarUrl = null,
      assignedMemberRole = null,
      founderNumber = null,
      message = 'Signed out';
}

String resolvePublicUsername({
  required String userId,
  Map<String, dynamic> metadata = const <String, dynamic>{},
  String? profileDisplayName,
}) {
  final candidates = <Object?>[
    profileDisplayName,
    metadata['username'],
    metadata['preferred_username'],
    metadata['display_name'],
    metadata['full_name'],
    metadata['name'],
  ];

  for (final candidate in candidates) {
    final normalized = candidate
        ?.toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized != null && normalized.length >= 3) {
      return normalized.length <= 24 ? normalized : normalized.substring(0, 24);
    }
  }

  final safeId = userId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final suffix = safeId.isEmpty
      ? 'member'
      : safeId.substring(0, safeId.length.clamp(0, 8));
  return 'user_$suffix';
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
  bool _restoringInitialSession = false;
  int _profileRefreshGeneration = 0;
  String? _lastMemberJoinNotificationUserId;
  SubscriptionTier? _recentVerifiedPurchaseTier;
  String? _recentVerifiedPurchaseUserId;
  DateTime? _recentVerifiedPurchaseExpiresAt;
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.propsintell.com',
  );

  SupabaseClient? get _client => SupabaseService.client;

  void attach() {
    final client = _client;
    if (client == null) {
      sessionState.value = const AuthSessionState.unavailable();
      return;
    }

    if (kIsWeb &&
        client.auth.currentSession != null &&
        isPasswordRecoveryUri(Uri.base)) {
      passwordRecoveryRequested.value = true;
    }
    final restoredSession = client.auth.currentSession;
    _restoringInitialSession = restoredSession != null;
    if (restoredSession == null) {
      unawaited(_setSession(null));
    } else {
      // Mobile browsers can restore an expired JWT from storage before the
      // Supabase refresh finishes. Rendering the workspace at that point
      // starts the prop request with the stale token (401) and can briefly
      // evaluate entitlement metadata from the wrong session snapshot.
      // Keep AuthSessionState.loading active until one refresh attempt has
      // completed, then build either the authenticated shell or login screen.
      unawaited(_restoreInitialSession(client, restoredSession));
    }

    _authSubscription ??= client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        passwordRecoveryRequested.value = true;
      }
      if (!_restoringInitialSession) {
        unawaited(_setSession(event.session));
      }
    });
  }

  Future<void> _restoreInitialSession(
    SupabaseClient client,
    Session restoredSession,
  ) async {
    var usableSession = restoredSession;
    try {
      final refreshed = await client.auth.refreshSession();
      usableSession = refreshed.session ?? restoredSession;
    } catch (_) {
      // _setSession still resolves the restored identity. Protected requests
      // retain their normal retry/error behavior if the network is offline.
    } finally {
      _restoringInitialSession = false;
    }
    await _setSession(usableSession);
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

    await _setSession(client.auth.currentSession);
    unawaited(
      saveProfileTrackingState({
        'last_auth_event': 'signup',
        'email': email.trim(),
      }).catchError((_) {}),
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    final client = _requireClient();

    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    await _setSession(client.auth.currentSession);
    unawaited(
      saveProfileTrackingState({
        'last_auth_event': 'signin',
        'email': email.trim(),
      }).catchError((_) {}),
    );
  }

  Future<void> signOut() async {
    final client = _requireClient();
    _profileRefreshGeneration++;
    try {
      await client.auth.signOut();
    } finally {
      // A failed remote sign-out must not trap an expired user on a screen.
      passwordRecoveryRequested.value = false;
      sessionState.value = const AuthSessionState.signedOut();
    }
    if (kIsWeb) {
      await launchUrl(
        Uri.parse('https://pipropsintell.com/login'),
        webOnlyWindowName: '_self',
      );
    }
  }

  void setOwnerAccessPreview(SubscriptionTier? tier) {
    final current = sessionState.value;
    if (!current.isOwner) {
      throw StateError('Only an owner can preview subscription access.');
    }
    sessionState.value = AuthSessionState(
      ready: current.ready,
      authenticated: current.authenticated,
      isPremium: current.isPremium,
      subscriptionTier: current.subscriptionTier,
      accessPreviewTier: tier,
      role: current.role,
      userId: current.userId,
      email: current.email,
      username: current.username,
      avatarUrl: current.avatarUrl,
      assignedMemberRole: current.assignedMemberRole,
      founderNumber: current.founderNumber,
      message: current.message,
    );
    debugPrint(
      tier == null
          ? 'Owner access preview disabled.'
          : 'Owner access preview set to ${tier.name}.',
    );
  }

  void setPublicUsername(String username) {
    final current = sessionState.value;
    if (!current.authenticated) return;
    sessionState.value = AuthSessionState(
      ready: current.ready,
      authenticated: current.authenticated,
      isPremium: current.isPremium,
      subscriptionTier: current.subscriptionTier,
      accessPreviewTier: current.accessPreviewTier,
      role: current.role,
      userId: current.userId,
      email: current.email,
      username: username,
      avatarUrl: current.avatarUrl,
      assignedMemberRole: current.assignedMemberRole,
      founderNumber: current.founderNumber,
      message: current.message,
    );
  }

  Future<Map<String, dynamic>> assignUserRole({
    required String email,
    required String role,
    int? founderNumber,
  }) async {
    if (!sessionState.value.isOwner) {
      throw StateError('Only an owner can assign account roles.');
    }

    final normalizedEmail = email.trim().toLowerCase();
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Enter the user email address.');
    }
    if (!const {
      'admin',
      'core',
      'pro',
      'pro_founder',
      'user',
    }.contains(normalizedRole)) {
      throw ArgumentError(
        'Role must be Admin, Core, Pro, Pro Founder, or User.',
      );
    }
    if (normalizedRole == 'pro_founder' &&
        (founderNumber == null || founderNumber < 1 || founderNumber > 999)) {
      throw ArgumentError(
        'Pro Founder requires a unique number from 1 to 999.',
      );
    }

    final response = await _requireClient().rpc(
      'assign_member_identity_role',
      params: {
        'target_email': normalizedEmail,
        'target_role': normalizedRole,
        'target_founder_number': normalizedRole == 'pro_founder'
            ? founderNumber
            : null,
      },
    );
    if (response is Map<String, dynamic>) {
      return response;
    }
    return <String, dynamic>{'email': normalizedEmail, 'role': normalizedRole};
  }

  Future<AppChangeRequest> submitChangeRequest({
    required String title,
    required String description,
  }) async {
    if (!sessionState.value.isAdmin) {
      throw StateError('Only administrators can submit change requests.');
    }
    final response = await _requireClient().rpc(
      'submit_app_change_request',
      params: {
        'request_title': title.trim(),
        'request_description': description.trim(),
      },
    );
    return AppChangeRequest.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<List<AppChangeRequest>> listChangeRequests() async {
    final state = sessionState.value;
    if (!state.isOwner && !state.isAdmin) {
      throw StateError(
        'Change requests require owner or administrator access.',
      );
    }
    final response = await _requireClient().rpc('list_app_change_requests');
    final rows = response is List ? response : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => AppChangeRequest.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<AppChangeRequest> reviewChangeRequest({
    required int requestId,
    required bool approved,
    String? response,
  }) async {
    if (!sessionState.value.isOwner) {
      throw StateError('Only the owner can review change requests.');
    }
    final result = await _requireClient().rpc(
      'review_app_change_request',
      params: {
        'request_id': requestId,
        'decision': approved ? 'approved' : 'denied',
        'response': response?.trim(),
      },
    );
    return AppChangeRequest.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> refreshSessionState() async {
    final client = _client;
    if (client == null) {
      sessionState.value = const AuthSessionState.unavailable();
      return;
    }
    await _setSession(client.auth.currentSession);
  }

  /// Applies a tier that was already verified by the billing SDK immediately.
  ///
  /// RevenueCat webhooks remain the authoritative persisted source, but they
  /// can take a few seconds to update the profile row. Holding the verified
  /// purchase briefly prevents a successful checkout from bouncing through
  /// the paywall or showing the wrong tier while that webhook catches up.
  void applyVerifiedPurchaseTier(SubscriptionTier purchasedTier) {
    final current = sessionState.value;
    if (!current.authenticated || current.userId == null) return;

    final effectiveTier = current.subscriptionTier.index >= purchasedTier.index
        ? current.subscriptionTier
        : purchasedTier;
    _recentVerifiedPurchaseTier = effectiveTier;
    _recentVerifiedPurchaseUserId = current.userId;
    _recentVerifiedPurchaseExpiresAt = DateTime.now().add(
      const Duration(seconds: 45),
    );
    sessionState.value = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium: true,
      subscriptionTier: effectiveTier,
      accessPreviewTier: current.accessPreviewTier,
      role: current.role,
      userId: current.userId,
      email: current.email,
      username: current.username,
      avatarUrl: current.avatarUrl,
      assignedMemberRole: current.assignedMemberRole,
      founderNumber: current.founderNumber,
      message: 'Subscription active',
    );
  }

  SubscriptionTier _preserveRecentVerifiedPurchase(
    String userId,
    SubscriptionTier candidate,
  ) {
    final verifiedTier = _recentVerifiedPurchaseTier;
    final expiresAt = _recentVerifiedPurchaseExpiresAt;
    final isCurrent =
        verifiedTier != null &&
        _recentVerifiedPurchaseUserId == userId &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt);
    if (!isCurrent) return candidate;
    return verifiedTier.index > candidate.index ? verifiedTier : candidate;
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

  void setAvatarUrl(String? avatarUrl) {
    final current = sessionState.value;
    if (!current.authenticated) return;
    sessionState.value = AuthSessionState(
      ready: current.ready,
      authenticated: current.authenticated,
      isPremium: current.isPremium,
      subscriptionTier: current.subscriptionTier,
      accessPreviewTier: current.accessPreviewTier,
      role: current.role,
      userId: current.userId,
      email: current.email,
      username: current.username,
      avatarUrl: avatarUrl,
      assignedMemberRole: current.assignedMemberRole,
      founderNumber: current.founderNumber,
      message: current.message,
    );
  }

  Future<void> updateAvatarUrl(String? avatarUrl) async {
    final client = _requireClient();
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before changing your profile photo.');
    }
    await client.from('user_profiles').upsert({
      'id': user.id,
      'email': user.email,
      'avatar_url': avatarUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    setAvatarUrl(avatarUrl);
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

    var role = resolveAccountRole(
      email: user.email,
      role: user.appMetadata['role'],
      userId: user.id,
    );
    // Safari can restore a valid Supabase session before every user field has
    // been reconstructed from storage. Resolve the one protected owner record
    // server-side before evaluating the paid-plan gate so the verified owner
    // can never be downgraded by browser-specific session hydration timing.
    if (role != 'owner') {
      try {
        final ownerResult = await _client?.rpc(
          'is_app_owner',
          params: <String, dynamic>{'target_user_id': user.id},
        );
        if (ownerResult == true) role = 'owner';
      } catch (_) {
        // The fixed UUID/email allowlist remains the secure offline fallback.
      }
    }
    final metadataUsername = resolvePublicUsername(
      userId: user.id,
      metadata: user.userMetadata ?? const <String, dynamic>{},
    );
    final metadataAvatarUrl =
        user.userMetadata?['avatar_url']?.toString().trim() ??
        user.userMetadata?['picture']?.toString().trim();
    final hasPrivilegedRole =
        role == 'owner' || role == 'admin' || role == 'tester';
    if (hasPrivilegedRole) {
      // Privileged access is resolved from the verified owner email or signed
      // auth metadata, so do not block login on a second profile-table request.
      sessionState.value = AuthSessionState(
        ready: true,
        authenticated: true,
        isPremium: true,
        subscriptionTier: SubscriptionTier.edge,
        accessPreviewTier: null,
        role: role,
        userId: user.id,
        email: user.email,
        username: metadataUsername,
        avatarUrl: metadataAvatarUrl,
        message: 'Authenticated',
      );
      return;
    }

    final metadataTier = SubscriptionTier.fromDatabase(
      user.appMetadata['subscription_tier'] ??
          user.userMetadata?['subscription_tier'],
    );
    // Render the authenticated shell immediately. The API still performs the
    // authoritative membership check on every protected request; this
    // provisional UI state only prevents profile I/O from blocking sign-in.
    final metadataProvisionalTier = metadataTier == SubscriptionTier.free
        ? SubscriptionTier.core
        : metadataTier;
    final provisionalTier = _preserveRecentVerifiedPurchase(
      user.id,
      metadataProvisionalTier,
    );
    sessionState.value = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium: provisionalTier != SubscriptionTier.free,
      subscriptionTier: provisionalTier,
      accessPreviewTier: null,
      role: role,
      userId: user.id,
      email: user.email,
      username: metadataUsername,
      avatarUrl: metadataAvatarUrl,
      message: 'Authenticated; refreshing membership',
    );
    if (_lastMemberJoinNotificationUserId != user.id) {
      unawaited(_notifyMemberJoined(session!));
    }
    final generation = ++_profileRefreshGeneration;
    unawaited(
      _refreshProfileSession(user: user, role: role, generation: generation),
    );
  }

  Future<void> _notifyMemberJoined(Session session) async {
    final user = session.user;
    if (_lastMemberJoinNotificationUserId == user.id) {
      return;
    }
    final token = session.accessToken;
    if (token.isEmpty) {
      return;
    }
    try {
      final uri = Uri.parse('$_apiBaseUrl/api/operations/member-joined');
      final response = await http.post(
        uri,
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, String>{
          'email': user.email ?? '',
          'source': 'app_session',
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastMemberJoinNotificationUserId = user.id;
      }
    } catch (_) {
      // Best-effort only: signup notification failure must not block auth.
    }
  }

  Future<void> _refreshProfileSession({
    required User user,
    required String role,
    required int generation,
  }) async {
    var isPremium = false;
    var subscriptionTier = SubscriptionTier.free;
    String? profileDisplayName;
    String? profileAvatarUrl;
    String? assignedMemberRole;
    int? founderNumber;
    var profileLoaded = false;
    try {
      final row = await _client
          ?.from('user_profiles')
          .select(
            'is_premium, subscription_tier, display_name, avatar_url, '
            'assigned_member_role, founder_number',
          )
          .eq('id', user.id)
          .maybeSingle();
      profileLoaded = true;
      if (row is Map<String, dynamic>) {
        profileDisplayName = row['display_name']?.toString();
        profileAvatarUrl = row['avatar_url']?.toString().trim();
        final raw = row['is_premium'];
        if (raw is bool) {
          isPremium = raw;
        }
        subscriptionTier = SubscriptionTier.fromDatabase(
          row['subscription_tier'],
        );
        assignedMemberRole = row['assigned_member_role']?.toString();
        founderNumber = (row['founder_number'] as num?)?.toInt();
        // Preserve full access for legacy premium accounts during migration.
        if (subscriptionTier == SubscriptionTier.free && raw == true) {
          subscriptionTier = SubscriptionTier.edge;
        }
      }
    } catch (_) {
      // Keep the signed token's provisional access visible while an
      // intermittent profile request recovers. Protected APIs remain the
      // authority for actual access.
      return;
    }

    if (!profileLoaded ||
        generation != _profileRefreshGeneration ||
        _client?.auth.currentUser?.id != user.id) {
      return;
    }
    final effectiveSubscriptionTier = _preserveRecentVerifiedPurchase(
      user.id,
      subscriptionTier,
    );
    sessionState.value = AuthSessionState(
      ready: true,
      authenticated: true,
      isPremium:
          isPremium || effectiveSubscriptionTier != SubscriptionTier.free,
      subscriptionTier: effectiveSubscriptionTier,
      accessPreviewTier: null,
      role: role,
      userId: user.id,
      email: user.email,
      username: resolvePublicUsername(
        userId: user.id,
        metadata: user.userMetadata ?? const <String, dynamic>{},
        profileDisplayName: profileDisplayName,
      ),
      avatarUrl: (profileAvatarUrl ?? '').isNotEmpty
          ? profileAvatarUrl
          : user.userMetadata?['avatar_url']?.toString() ??
                user.userMetadata?['picture']?.toString(),
      assignedMemberRole: assignedMemberRole,
      founderNumber: founderNumber,
      message: 'Authenticated',
    );
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
  }
}
