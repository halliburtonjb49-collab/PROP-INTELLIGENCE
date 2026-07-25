import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/services/auth_manager.dart';

void main() {
  test('recognizes the explicit web password-recovery marker', () {
    expect(
      isPasswordRecoveryUri(
        Uri.parse(
          'https://app.propsintell.com/?auth_action=recovery&code=example',
        ),
      ),
      isTrue,
    );
  });

  test('recognizes legacy implicit-flow recovery fragments', () {
    expect(
      isPasswordRecoveryUri(
        Uri.parse('https://app.propsintell.com/#type=recovery&access_token=x'),
      ),
      isTrue,
    );
  });

  test('does not treat ordinary authentication redirects as recovery', () {
    expect(
      isPasswordRecoveryUri(
        Uri.parse('https://app.propsintell.com/?code=example'),
      ),
      isFalse,
    );
  });
}
