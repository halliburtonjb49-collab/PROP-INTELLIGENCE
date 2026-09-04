import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/layout/app_shell.dart';
import 'package:prop_intelligence/widgets/main_dashboard.dart';

void main() {
  test('dedicated phone experience stops below 600 logical pixels', () {
    expect(usePhoneShell(320), isTrue);
    expect(usePhoneBoardLayout(599), isTrue);
    expect(usePhoneShell(600), isFalse);
    expect(usePhoneBoardLayout(600), isFalse);
  });
}
