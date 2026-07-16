import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AuthActionResult {
  final bool success;
  final String message;
  final int suggestedRetrySeconds;

  const AuthActionResult({
    required this.success,
    required this.message,
    this.suggestedRetrySeconds = 0,
  });
}

class SportsAppAuthService {
  int _extractRetryAfterSeconds(String message) {
    final lowered = message.toLowerCase();
    final minuteMatch = RegExp(r'(\d+)\s*minute').firstMatch(lowered);
    if (minuteMatch != null) {
      final minutes = int.tryParse(minuteMatch.group(1) ?? '');
      if (minutes != null && minutes > 0) {
        return minutes * 60;
      }
    }
    final secondMatch = RegExp(r'(\d+)\s*second').firstMatch(lowered);
    if (secondMatch != null) {
      final seconds = int.tryParse(secondMatch.group(1) ?? '');
      if (seconds != null && seconds > 0) {
        return seconds;
      }
    }
    // Conservative fallback for Supabase auth email rate limits.
    return 900;
  }

  SupabaseClient? get _supabase => SupabaseService.client;
  static const String _authEmailRedirectUrl = String.fromEnvironment(
    'AUTH_EMAIL_REDIRECT_URL',
    defaultValue: '',
  );
  static Set<String>? _cachedCloudWatchlistPlayerNames;

  static String _normalizePlayerName(String value) =>
      value.trim().toLowerCase();

  static void _rebuildCloudCacheFromRows(List<Map<String, dynamic>> rows) {
    _cachedCloudWatchlistPlayerNames = rows
        .map((row) => row['player_name']?.toString() ?? '')
        .map(_normalizePlayerName)
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  String _friendlyAuthMessage(Object error, {required bool isRegistering}) {
    if (error is AuthApiException) {
      final code = (error.code ?? '').toLowerCase();
      if (code == 'email_not_confirmed') {
        return 'Email not confirmed yet. Check your inbox, confirm your account, then sign in.';
      }
      if (code == 'invalid_credentials') {
        return 'Invalid email or password. Please check both and retry.';
      }
      if (code == 'user_already_exists') {
        return 'An account already exists for this email. Try signing in instead.';
      }
      if (code == 'over_email_send_rate_limit' ||
          code == 'over_request_rate_limit') {
        return 'Too many attempts right now. Please wait a minute and try again.';
      }
      if (error.message.isNotEmpty) {
        return error.message;
      }
    }

    if (error is AuthException && error.message.isNotEmpty) {
      return error.message;
    }

    return isRegistering
        ? 'Registration failed. Please verify your email/password and try again.'
        : 'Sign in failed. Please verify your credentials and try again.';
  }

  String? get _redirectUrlOrNull {
    final value = _authEmailRedirectUrl.trim();
    return value.isEmpty ? null : value;
  }

  /// Registers a brand new user record and returns a structured result.
  Future<AuthActionResult> createNewUserAccount(
    String email,
    String password,
  ) async {
    final client = _supabase;
    if (client == null) {
      return const AuthActionResult(
        success: false,
        message: 'Registration unavailable: Supabase is not configured.',
      );
    }

    try {
      final response = await client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: _redirectUrlOrNull,
      );

      if (response.user != null && response.session != null) {
        return const AuthActionResult(
          success: true,
          message: 'Account created successfully. You are now signed in.',
        );
      }

      if (response.user != null) {
        return const AuthActionResult(
          success: true,
          message:
              'Account created. Confirm your email first, then use Sign In.',
        );
      }

      return const AuthActionResult(
        success: false,
        message: 'Registration did not complete. Please try again.',
      );
    } catch (e) {
      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(e, isRegistering: true),
      );
    }
  }

  /// Logs a returning user securely into their data tracking profiles dashboard.
  Future<AuthActionResult> loginUserAccount(
    String email,
    String password,
  ) async {
    final client = _supabase;
    if (client == null) {
      return const AuthActionResult(
        success: false,
        message: 'Sign in unavailable: Supabase is not configured.',
      );
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user != null) {
        return const AuthActionResult(success: true, message: 'Welcome back!');
      }
      return const AuthActionResult(
        success: false,
        message: 'Sign in failed: no user session returned.',
      );
    } catch (e) {
      debugPrint('Login structural failure: $e');
      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(e, isRegistering: false),
      );
    }
  }

  Future<AuthActionResult> sendPasswordResetEmail(String email) async {
    final client = _supabase;
    final trimmedEmail = email.trim();
    if (client == null) {
      return const AuthActionResult(
        success: false,
        message: 'Password reset unavailable: Supabase is not configured.',
      );
    }
    if (trimmedEmail.isEmpty) {
      return const AuthActionResult(
        success: false,
        message: 'Enter your email address first.',
      );
    }

    try {
      await client.auth.resetPasswordForEmail(
        trimmedEmail,
        redirectTo: _redirectUrlOrNull,
      );
      return const AuthActionResult(
        success: true,
        message: 'Password reset email sent. Check your inbox.',
      );
    } catch (e) {
      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(e, isRegistering: false),
      );
    }
  }

  Future<AuthActionResult> signInWithProvider(OAuthProvider provider) async {
    final client = _supabase;
    if (client == null) {
      return const AuthActionResult(
        success: false,
        message: 'Social sign in unavailable: Supabase is not configured.',
      );
    }

    try {
      final launched = await client.auth.signInWithOAuth(
        provider,
        redirectTo: _redirectUrlOrNull,
      );
      return AuthActionResult(
        success: launched,
        message: launched
            ? 'Opening secure sign in…'
            : 'Unable to open the selected sign-in provider.',
      );
    } catch (e) {
      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(e, isRegistering: false),
      );
    }
  }

  Future<AuthActionResult> resendVerificationEmail(String email) async {
    final client = _supabase;
    final trimmedEmail = email.trim();

    if (client == null) {
      return const AuthActionResult(
        success: false,
        message: 'Resend unavailable: Supabase is not configured.',
      );
    }

    if (trimmedEmail.isEmpty) {
      return const AuthActionResult(
        success: false,
        message: 'Enter your email first, then tap Resend verification email.',
      );
    }

    try {
      await client.auth.resend(
        type: OtpType.signup,
        email: trimmedEmail,
        emailRedirectTo: _redirectUrlOrNull,
      );
      return const AuthActionResult(
        success: true,
        message:
            'Verification email sent. Check inbox and spam, then confirm and sign in.',
      );
    } catch (e) {
      if (e is AuthApiException) {
        final code = (e.code ?? '').toLowerCase();
        if (code == 'over_email_send_rate_limit' ||
            code == 'over_request_rate_limit') {
          final retryInSeconds = _extractRetryAfterSeconds(e.message);
          final retryInMinutes = (retryInSeconds / 60).ceil();
          return AuthActionResult(
            success: false,
            message:
                'Too many verification attempts. Please wait about $retryInMinutes minutes, then try resend once.',
            suggestedRetrySeconds: retryInSeconds,
          );
        }
      }

      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(e, isRegistering: true),
      );
    }
  }

  /// Syncs an item straight to the user's persistent remote cloud table watchlist.
  Future<void> savePlayerToCloudWatchlist(
    String playerUuid,
    String playerName,
  ) async {
    final client = _supabase;
    if (client == null) {
      return;
    }

    final user = client.auth.currentUser;
    if (user == null) {
      return;
    }

    await client.from('user_watchlists').upsert({
      'user_id': user.id,
      'player_id': playerUuid,
      'player_name': playerName,
    }, onConflict: 'user_id,player_id');
  }

  Future<List<Map<String, dynamic>>> loadCloudWatchlist() async {
    final client = _supabase;
    if (client == null) {
      return [];
    }

    final user = client.auth.currentUser;
    if (user == null) {
      return [];
    }

    final response = await client
        .from('user_watchlists')
        .select('player_id, player_name, created_at, updated_at')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    final rows = (response as List<dynamic>)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    _rebuildCloudCacheFromRows(rows);
    return rows;
  }

  /// Returns true when the player's name is present in cloud watchlist rows.
  Future<bool> isPlayerInCloudWatchlist(
    String playerName, {
    bool refresh = false,
  }) async {
    final normalized = _normalizePlayerName(playerName);
    if (normalized.isEmpty) {
      return false;
    }

    if (refresh || _cachedCloudWatchlistPlayerNames == null) {
      await loadCloudWatchlist();
    }

    final cached = _cachedCloudWatchlistPlayerNames;
    if (cached == null) {
      return false;
    }

    return cached.contains(normalized);
  }

  Future<void> upsertCloudWatchlist(
    List<Map<String, dynamic>> watchlist,
  ) async {
    final client = _supabase;
    if (client == null || watchlist.isEmpty) {
      return;
    }

    final user = client.auth.currentUser;
    if (user == null) {
      return;
    }

    final payload = watchlist
        .map((item) {
          final playerId = item['prop_id']?.toString().trim() ?? '';
          final playerName =
              item['player_name']?.toString().trim() ??
              item['player']?.toString().trim() ??
              '';
          if (playerId.isEmpty || playerName.isEmpty) {
            return null;
          }
          return <String, dynamic>{
            'user_id': user.id,
            'player_id': playerId,
            'player_name': playerName,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    if (payload.isEmpty) {
      return;
    }

    await client
        .from('user_watchlists')
        .upsert(payload, onConflict: 'user_id,player_id');
  }

  /// Securely inserts a player prop target directly into cloud PostgreSQL.
  Future<void> addPlayerToCloudWatchlist(
    String playerName,
    String sport,
  ) async {
    final client = _supabase;
    if (client == null) {
      return;
    }

    final user = client.auth.currentUser;
    if (user == null) {
      return;
    }

    final playerId = _normalizePlayerName(playerName);
    try {
      await client.from('user_watchlists').insert({
        'user_id': user.id,
        'player_id': playerId,
        'player_name': playerName,
        'sport': sport.toUpperCase(),
      });
      (_cachedCloudWatchlistPlayerNames ??= <String>{}).add(
        _normalizePlayerName(playerName),
      );
      debugPrint('Persistent cloud sync successful for $playerName');
    } catch (_) {
      // Fallback for schemas that do not yet include the sport column.
      try {
        await client.from('user_watchlists').insert({
          'user_id': user.id,
          'player_id': playerId,
          'player_name': playerName,
        });
        (_cachedCloudWatchlistPlayerNames ??= <String>{}).add(
          _normalizePlayerName(playerName),
        );
        debugPrint('Persistent cloud sync successful for $playerName');
      } catch (e) {
        debugPrint('Database sync error: $e');
      }
    }
  }

  /// Removes a player target from the persistent cloud watchlist.
  Future<void> removePlayerFromCloudWatchlist(String playerName) async {
    final client = _supabase;
    if (client == null) {
      return;
    }

    final user = client.auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      await client.from('user_watchlists').delete().match({
        'user_id': user.id,
        'player_name': playerName,
      });
      _cachedCloudWatchlistPlayerNames?.remove(
        _normalizePlayerName(playerName),
      );
      debugPrint('Removed $playerName from persistent cloud schema');
    } catch (e) {
      debugPrint('Database deletion failure: $e');
    }
  }
}
