import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web scoreboards avoid one HTML platform view per team logo', () {
    const paths = <String>[
      'lib/widgets/scoreboard_view.dart',
      'lib/widgets/scoreboard_navigation_ribbon.dart',
      'lib/pages/scoreboard_page.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('WebHtmlElementStrategy.never'),
        reason: '$path must render primary logos inside Flutter on web.',
      );
      expect(
        source,
        contains('resolvePlayerImageFallbackPath'),
        reason: '$path must retain a compatibility fallback.',
      );
      expect(
        source,
        contains('nativeFallback'),
        reason: '$path may use an HTML image only after primary decode fails.',
      );
    }
  });
}
