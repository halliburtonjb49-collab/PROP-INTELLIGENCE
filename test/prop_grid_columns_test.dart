import 'package:flutter_test/flutter_test.dart';
import 'package:prop_intelligence/widgets/prop_grid.dart';

void main() {
  test('research cards retain a readable minimum width', () {
    expect(propGridColumnCount(390), 1);
    expect(propGridColumnCount(768), 1);
    expect(propGridColumnCount(819.9), 1);
    expect(propGridColumnCount(820), 2);
    expect(propGridColumnCount(1100), 2);
    expect(propGridColumnCount(1239.9), 2);
    expect(propGridColumnCount(1240), 3);
    expect(propGridColumnCount(1600), 3);
  });
}
