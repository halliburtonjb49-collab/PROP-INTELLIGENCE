import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/slip_history_panel.dart';

void main() {
  test('Core Slip Watcher uses standard tracking only', () {
    expect(
      supportsEnhancedSlipWatcher(
        mode: SlipHistoryMode.active,
        hasProAccess: false,
      ),
      isFalse,
    );
  });

  test('Pro Slip Watcher enables enhanced live tracking', () {
    expect(
      supportsEnhancedSlipWatcher(
        mode: SlipHistoryMode.active,
        hasProAccess: true,
      ),
      isTrue,
    );
  });

  test('Past Slip History does not poll active live stats', () {
    expect(
      supportsEnhancedSlipWatcher(
        mode: SlipHistoryMode.history,
        hasProAccess: true,
      ),
      isFalse,
    );
  });
}
