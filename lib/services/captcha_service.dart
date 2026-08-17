import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/foundation.dart';

class CaptchaChallengeResult {
  final bool required;
  final String? token;

  const CaptchaChallengeResult({required this.required, this.token});

  bool get passed => !required || (token?.isNotEmpty ?? false);
}

class CaptchaService {
  static const String _siteKey = String.fromEnvironment(
    'TURNSTILE_SITE_KEY',
    defaultValue: '',
  );
  static const String _configuredBaseUrl = String.fromEnvironment(
    'TURNSTILE_BASE_URL',
    defaultValue: 'https://app.propsintell.com/',
  );
  static const bool _required = bool.fromEnvironment(
    'TURNSTILE_REQUIRED',
    defaultValue: false,
  );

  static bool get isEnabled => _siteKey.trim().isNotEmpty;
  static bool get isMisconfigured => _required && !isEnabled;

  static String get _baseUrl {
    if (kIsWeb && Uri.base.origin.startsWith('https://')) {
      return '${Uri.base.origin}/';
    }
    return _configuredBaseUrl;
  }

  static Future<CaptchaChallengeResult> tokenFor(String action) async {
    if (!isEnabled) {
      return CaptchaChallengeResult(required: _required);
    }
    final turnstile = CloudflareTurnstile.invisible(
      siteKey: _siteKey,
      baseUrl: _baseUrl,
      action: action,
    );
    try {
      final token = await turnstile.getToken();
      return CaptchaChallengeResult(required: true, token: token);
    } on TurnstileException catch (error) {
      debugPrint('Turnstile challenge failed: ${error.message}');
      return const CaptchaChallengeResult(required: true);
    } finally {
      await turnstile.dispose();
    }
  }
}
