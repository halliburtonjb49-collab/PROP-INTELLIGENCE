import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/auth_manager.dart';

void main() {
  group('resolvePublicUsername', () {
    test('uses a saved public display name first', () {
      expect(
        resolvePublicUsername(
          userId: 'abc123',
          metadata: const {'name': 'Google Name'},
          profileDisplayName: 'Prop Captain',
        ),
        'prop_captain',
      );
    });

    test('normalizes a Google profile name into a username', () {
      expect(
        resolvePublicUsername(
          userId: 'abc123',
          metadata: const {'full_name': 'Jordan Halliburton'},
        ),
        'jordan_halliburton',
      );
    });

    test('creates a stable fallback without using the email address', () {
      expect(
        resolvePublicUsername(
          userId: '94AF-218C-0000',
          metadata: const {'email': 'private@example.com'},
        ),
        'user_94af218c',
      );
    });
  });
}
