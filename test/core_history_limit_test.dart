import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/models/saved_slip.dart';
import 'package:prop_intelligence/widgets/slip_history_panel.dart';

void main() {
  SavedSlip slip(String id, DateTime createdAt) => SavedSlip(
    id: id,
    status: 'won',
    stake: 10,
    potentialPayout: 20,
    createdAt: createdAt,
    legs: const [],
  );

  test('Core history is limited to the latest 14 days', () {
    final now = DateTime.utc(2026, 7, 24, 12);
    final slips = [
      slip('recent', now.subtract(const Duration(days: 2))),
      slip('boundary', now.subtract(const Duration(days: 14))),
      slip('old', now.subtract(const Duration(days: 15))),
    ];

    final visible = limitHistoryForCore(slips, hasProAccess: false, now: now);

    expect(visible.map((item) => item.id), ['recent', 'boundary']);
  });

  test('Pro history remains unlimited', () {
    final now = DateTime.utc(2026, 7, 24, 12);
    final slips = [
      slip('recent', now),
      slip('old', now.subtract(const Duration(days: 300))),
    ];

    expect(
      limitHistoryForCore(slips, hasProAccess: true, now: now),
      hasLength(2),
    );
  });
}
