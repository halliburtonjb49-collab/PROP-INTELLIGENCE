import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/player_image_resolver.dart';

void main() {
  test('translates legacy bundled player images to the API endpoint', () {
    expect(
      resolvePlayerImagePath('assets/players/aaron_judge.png'),
      endsWith('/player-images/aaron_judge.png'),
    );
  });

  test('preserves remote and non-player asset paths', () {
    expect(
      resolvePlayerImagePath('https://cdn.example.com/player.png'),
      'https://cdn.example.com/player.png',
    );
    expect(
      resolvePlayerImagePath('assets/branding/logo.png'),
      'assets/branding/logo.png',
    );
  });
}
