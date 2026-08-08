import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer-facing Dart source contains no common mojibake sequences', () {
    const brokenLeadCodeUnits = {0x00c2, 0x00c3, 0x00e2, 0x00f0};
    final affected = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.codeUnits.any(brokenLeadCodeUnits.contains)) {
        affected.add(entity.path);
      }
    }

    expect(
      affected,
      isEmpty,
      reason: 'Replace corrupted customer-facing characters in: $affected',
    );
  });
}
