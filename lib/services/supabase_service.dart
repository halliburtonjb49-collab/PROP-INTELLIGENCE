import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static bool _initialized = false;
  static String? _runtimeSupabaseUrl;
  static String? _runtimeSupabaseAnonKey;

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
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );

    _initialized = true;
    debugPrint('Supabase initialized successfully.');
  }
}
