import 'package:daily_spin_flutter/controllers/active_slip_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('adds unique props and skips duplicates', () async {
    final controller = ActiveSlipController();
    await controller.load();

    final firstAdd = await controller.addLegs([
      {'prop_id': 'prop-1', 'player': 'Player One', 'line': 15.5},
    ]);

    final duplicateAdd = await controller.addLegs([
      {'prop_id': 'prop-1', 'player': 'Player One', 'line': 15.5},
    ]);

    expect(firstAdd, 1);
    expect(duplicateAdd, 0);
    expect(controller.legCount, 1);
  });

  test('removes a prop', () async {
    final controller = ActiveSlipController();
    await controller.load();
    await controller.addLegs([
      {'prop_id': 'prop-1', 'player': 'Player One', 'line': 15.5},
    ]);

    await controller.removeLeg('prop-1');
    expect(controller.isEmpty, true);
  });

  test('preserves ordered positions', () async {
    final controller = ActiveSlipController();
    await controller.load();

    await controller.addLegs([
      {'prop_id': 'prop-1'},
      {'prop_id': 'prop-2'},
    ]);

    await controller.reorder(0, 1);

    expect(controller.legs.first['prop_id'], 'prop-2');
    expect(controller.legs.last['prop_id'], 'prop-1');
  });
}
