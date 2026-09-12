import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marketing OAuth cannot strand an authenticated user at the root', () {
    final source = File('marketing_site/auth-modal.js').readAsStringSync();

    expect(source, contains("['/', '/login', '/signup', '/auth/callback']"));
    expect(
      source,
      contains("redirectTo: window.location.origin + '/auth/callback'"),
    );
    expect(
      source,
      isNot(contains("redirectTo: window.location.origin + '/workspace'")),
    );
  });

  test('marketing OAuth callback is processed before Flutter starts', () {
    final config = File('vercel.json').readAsStringSync();
    final splitConfig = File('marketing_site/vercel.json').readAsStringSync();

    expect(
      config,
      contains(
        '"source": "/auth/callback",\n      "destination": "/index.html"',
      ),
    );
    expect(
      splitConfig,
      contains('"source": "/auth/callback",\n      "destination": "/"'),
    );
  });
}
