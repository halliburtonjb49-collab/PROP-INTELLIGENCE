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

  test('iOS submission metadata supports iPhone and iPad release review', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      project,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.propintelligence.app'),
    );
    expect(project, contains('TARGETED_DEVICE_FAMILY = "1,2"'));
    expect(
      project,
      contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements'),
    );
    expect(project, contains('PrivacyInfo.xcprivacy in Resources'));
    expect(plist, contains('<key>ITSAppUsesNonExemptEncryption</key>'));
    expect(plist, contains('<false/>'));
  });

  test('privacy manifest declares the account and app data in use', () {
    final manifest = File(
      'ios/Runner/PrivacyInfo.xcprivacy',
    ).readAsStringSync();

    for (final dataType in [
      'NSPrivacyCollectedDataTypeName',
      'NSPrivacyCollectedDataTypeEmailAddress',
      'NSPrivacyCollectedDataTypeUserID',
      'NSPrivacyCollectedDataTypePurchaseHistory',
      'NSPrivacyCollectedDataTypeProductInteraction',
      'NSPrivacyCollectedDataTypeOtherUserContent',
    ]) {
      expect(manifest, contains(dataType));
    }
    expect(manifest, contains('<key>NSPrivacyTracking</key>'));
    expect(manifest, contains('<false/>'));
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

  test('review-critical account and purchase actions stay available', () {
    final accountPanel = File(
      'lib/widgets/auth_account_panel.dart',
    ).readAsStringSync();
    final paywall = File('lib/screens/paywall_screen.dart').readAsStringSync();

    expect(accountPanel, contains("ValueKey('delete-account-button')"));
    expect(accountPanel, contains('DELETE ACCOUNT'));
    expect(accountPanel, contains('MANAGE SUBSCRIPTION'));
    expect(paywall, contains('RESTORE PURCHASES'));
    expect(paywall, contains('TERMS OF USE'));
    expect(paywall, contains('PRIVACY POLICY'));
  });

  test('native launch does not expose the OneSignal SDK sample dialog', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      isNot(contains('Your OneSignal SDK integration is complete!')),
    );
    expect(source, isNot(contains('_showOneSignalRegistrationConfirmation')));
  });

  test('customer-facing source has no unfinished-product labels', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('.backup'));

    for (final source in sources) {
      final contents = source.readAsStringSync().toUpperCase();
      expect(contents, isNot(contains('LOREM IPSUM')), reason: source.path);
      expect(contents, isNot(contains('COMING SOON')), reason: source.path);
    }
  });
}
