import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/prop_grid.dart';

void main() {
  test('research cards retain a readable minimum width', () {
    expect(propGridColumnCount(390), 1);
    expect(propGridColumnCount(719.9), 1);
    expect(propGridColumnCount(720), 2);
    expect(propGridColumnCount(768), 2);
    expect(propGridColumnCount(1100), 2);
    expect(propGridColumnCount(1239.9), 2);
    expect(propGridColumnCount(1240), 3);
    expect(propGridColumnCount(1600), 3);
  });

  test('card spacing is denser on phones and tablets', () {
    expect(propGridSpacing(390), 8);
    expect(propGridSpacing(768), 10);
    expect(propGridSpacing(1200), 12);
  });
}
