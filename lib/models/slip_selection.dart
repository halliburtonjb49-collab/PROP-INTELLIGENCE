import 'prop_data.dart';

enum PickSide { over, under }

class SlipSelection {
  final PropData prop;
  final PickSide side;
  final String? customSideLabel;
  final double? customOdds;

  const SlipSelection({
    required this.prop,
    required this.side,
    this.customSideLabel,
    this.customOdds,
  });

  String get id => '${prop.id}-${side.name}';

  String get sideLabel {
    return customSideLabel?.trim().toUpperCase() ??
        (side == PickSide.over ? 'OVER' : 'UNDER');
  }

  double? get odds {
    return customOdds ??
        (side == PickSide.over ? prop.overOdds : prop.underOdds);
  }
}
