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

  test('can use the CORS-enabled sports CDN directly on web', () {
    const url = 'https://a.espncdn.com/i/headshots/nba/players/full/1.png';

    final resolved = Uri.parse(
      resolvePlayerImagePath(url, useApiProxyForRemoteImages: false),
    );

    expect(resolved.origin, 'https://a.espncdn.com');
    expect(resolved.path, '/combiner/i');
    expect(
      resolved.queryParameters['img'],
      '/i/headshots/nba/players/full/1.png',
    );
    expect(resolved.queryParameters['w'], '160');
    expect(resolved.queryParameters['h'], '160');
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
