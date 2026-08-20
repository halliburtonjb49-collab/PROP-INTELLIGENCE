import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/player_image_widget.dart';

void main() {
  testWidgets('player image keeps the previous frame while its URL changes', (
    tester,
  ) async {
    const url = 'https://img.mlbstatic.com/player.png';
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayerImageWidget(imageUrl: url, width: 48, height: 48),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage).first,
    );
    expect(image.imageUrl, url);
    expect(image.useOldImageOnUrlChange, isTrue);
    expect(image.fadeInDuration, Duration.zero);
    expect(image.fadeOutDuration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing player image renders a visible fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayerAvatarWidget(
          imageUrl: '',
          radius: 24,
          fallbackIcon: Icons.person_rounded,
        ),
      ),
    );

    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
