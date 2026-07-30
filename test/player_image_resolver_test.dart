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

  test('routes approved sports CDN photos through the API proxy', () {
    final resolved = resolvePlayerImagePath(
      'https://a.espncdn.com/i/headshots/nba/players/full/1.png',
      apiBaseUrl: 'https://api.propsintell.com',
    );

    final uri = Uri.parse(resolved);
    expect(uri.origin, 'https://api.propsintell.com');
    expect(uri.path, '/player-image-proxy');
    expect(
      uri.queryParameters['url'],
      'https://a.espncdn.com/i/headshots/nba/players/full/1.png',
    );
  });

  test('does not proxy unknown image hosts', () {
    expect(
      resolvePlayerImagePath(
        'https://cdn.example.com/player.png',
        apiBaseUrl: 'https://api.propsintell.com',
      ),
      'https://cdn.example.com/player.png',
    );
  });
}
