import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marketing OAuth cannot strand an authenticated user at the root', () {
    final source = File('marketing_site/auth-modal.js').readAsStringSync();

    expect(
      source,
      contains("['/', '/login', '/signup', '/auth/callback']"),
    );
    expect(
      source,
      contains("redirectTo: window.location.origin + '/auth/callback'"),
    );
    expect(
      source,
      isNot(contains("redirectTo: window.location.origin + '/workspace'")),
    );
  });
}
