/// System-generated OVER/UNDER direction is a Pro entitlement.
///
/// Core members can still inspect factual lines, odds, schedules, movement,
/// and player research, and can manually select either side.
bool canShowSystemRecommendation({required bool hasEdgeAccess}) =>
    hasEdgeAccess;

/// Returns a normalized suggested side only for an entitled Pro member.
///
/// Keeping this at the presentation boundary prevents cached Pro payloads or
/// client-side market calculations from leaking a direction after a user
/// switches to Core/Free access.
String? gatedSystemRecommendationSide({
  required bool hasEdgeAccess,
  required String? recommendation,
}) {
  if (!canShowSystemRecommendation(hasEdgeAccess: hasEdgeAccess)) return null;
  final side = recommendation?.trim().toUpperCase();
  return side == 'OVER' || side == 'UNDER' ? side : null;
}
