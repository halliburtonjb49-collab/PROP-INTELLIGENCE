import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS runner declares Sign in with Apple capability', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();

    expect(entitlements, contains('com.apple.developer.applesignin'));
    expect(entitlements, contains('<string>Default</string>'));
  });

  test(
    'Apple uses native ID-token auth and mobile OAuth avoids embedded views',
    () {
      final source = File('lib/services/auth_service.dart').readAsStringSync();

      expect(source, contains('SignInWithApple.getAppleIDCredential'));
      expect(source, contains('signInWithIdToken'));
      expect(source, contains('LaunchMode.externalApplication'));
      expect(source, isNot(contains('LaunchMode.inAppBrowserView')));
    },
  );

  test('a transient auth initialization failure cannot abort app launch', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('authInitialization.timeout'));
    expect(source, contains('Supabase initialization failed:'));
    expect(source, contains("then((_) => AuthManager.instance.attach())"));
    expect(
      source.indexOf('Supabase initialization failed:'),
      lessThan(source.indexOf('runApp(const PropIntelligenceApp())')),
    );
  });
}
