import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/main_dashboard.dart';

void main() {
  test('phone widths get sport tabs the sidebar cannot provide', () {
    // Below the shell's 1000px breakpoint the rail is a drawer behind the
    // menu button, so the board otherwise shows one sport's categories as
    // its primary cut -- PRA and DOUBLE-DOUBLE over a board that also holds
    // baseball -- with no way to change sport in sight.
    expect(
      wholeBoardSportsBelong(
        viewportWidth: 390,
        canSelectSport: true,
        sportsWithInventory: 3,
      ),
      isTrue,
    );
  });

  test('desktop widths do not duplicate the visible sidebar', () {
    // The rail is on screen there and already carries this control.
    expect(
      wholeBoardSportsBelong(
        viewportWidth: 1440,
        canSelectSport: true,
        sportsWithInventory: 3,
      ),
      isFalse,
    );
  });

  test('the breakpoint matches the shell that hides the sidebar', () {
    expect(
      wholeBoardSportsBelong(
        viewportWidth: 999,
        canSelectSport: true,
        sportsWithInventory: 2,
      ),
      isTrue,
    );
    expect(
      wholeBoardSportsBelong(
        viewportWidth: 1000,
        canSelectSport: true,
        sportsWithInventory: 2,
      ),
      isFalse,
    );
  });

  test('a single sport is not offered as a choice', () {
    expect(
      wholeBoardSportsBelong(
        viewportWidth: 390,
        canSelectSport: true,
        sportsWithInventory: 1,
      ),
      isFalse,
    );
  });

  test('no handler means no row', () {
    expect(
      wholeBoardSportsBelong(
        viewportWidth: 390,
        canSelectSport: false,
        sportsWithInventory: 4,
      ),
      isFalse,
    );
  });
}
