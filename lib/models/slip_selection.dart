import 'prop_data.dart';

enum PickSide { over, under }

class SlipSelection {
  final PropData prop;
  final PickSide side;

  const SlipSelection({required this.prop, required this.side});

  String get id => '${prop.id}-${side.name}';

  String get sideLabel {
    return side == PickSide.over ? 'OVER' : 'UNDER';
  }

  double? get odds {
    return side == PickSide.over ? prop.overOdds : prop.underOdds;
  }
}
