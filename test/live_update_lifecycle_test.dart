import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime socket callbacks cannot disconnect a replacement owner', () {
    final source = File(
      'lib/services/live_update_service.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('if (owner != null && !identical(_channel, owner)) return;'),
    );
    expect(source, contains('if (!identical(_channel, channel)) return;'));
    expect(
      RegExp(
        r'final channel = _channel;\s*_channel = null;\s*'
        r'await channel\?\.sink\.close\(\);',
      ).hasMatch(source),
      isTrue,
    );
  });
}
