import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/saved_slip.dart';
import 'package:prop_intelligence/widgets/slip_history_panel.dart';

SavedSlip slip(String id, DateTime? createdAt) => SavedSlip(
  id: id,
  status: 'won',
  stake: 10,
  potentialPayout: 20,
  createdAt: createdAt,
  legs: const [],
);

void main() {
  test('Core Slip Watcher receives live tracking', () {
    expect(
      supportsEnhancedSlipWatcher(
        mode: SlipHistoryMode.active,
        hasProAccess: false,
      ),
      isTrue,
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

  test('tickets are ordered newest first with missing dates last', () {
    final sorted = sortSlipsNewestFirst([
      slip('older', DateTime.utc(2026, 9, 5, 12)),
      slip('unknown', null),
      slip('newest', DateTime.utc(2026, 9, 7, 8)),
    ]);

    expect(sorted.map((item) => item.id), ['newest', 'older', 'unknown']);
  });

  test('tickets are grouped into newest-first calendar days', () {
    final sections = groupSlipsByLocalDay([
      slip('morning', DateTime(2026, 9, 7, 8)),
      slip('yesterday', DateTime(2026, 9, 6, 20)),
      slip('evening', DateTime(2026, 9, 7, 19)),
    ]);

    expect(sections.length, 2);
    expect(sections.first.day, DateTime(2026, 9, 7));
    expect(sections.first.slips.map((item) => item.id), ['evening', 'morning']);
    expect(sections.last.slips.single.id, 'yesterday');
  });
}
