import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/screens/prop_builder_screen.dart';

void main() {
  test('native Windows notifications are never initialized on the web', () {
    expect(supportsWindowsNotifications(true, TargetPlatform.windows), isFalse);
  });

  test('native Windows notifications remain enabled on Windows desktop', () {
    expect(supportsWindowsNotifications(false, TargetPlatform.windows), isTrue);
    expect(supportsWindowsNotifications(false, TargetPlatform.macOS), isFalse);
  });
}
