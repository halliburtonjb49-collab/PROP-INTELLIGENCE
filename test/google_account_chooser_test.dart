import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google OAuth always requests the account chooser', () {
    final source = File('lib/services/auth_service.dart').readAsStringSync();

    expect(source, contains("const {'prompt': 'select_account'}"));
    expect(source, contains('provider == OAuthProvider.google'));
  });
}
