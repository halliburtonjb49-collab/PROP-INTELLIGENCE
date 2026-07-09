class LineMovementAlert {
  const LineMovementAlert({
    required this.id,
    required this.propId,
    required this.player,
    required this.message,
    required this.severity,
    required this.createdAt,
    this.wasRead = false,
  });

  final String id;
  final String propId;
  final String player;
  final String message;
  final String severity;
  final DateTime createdAt;
  final bool wasRead;

  LineMovementAlert copyWith({bool? wasRead}) {
    return LineMovementAlert(
      id: id,
      propId: propId,
      player: player,
      message: message,
      severity: severity,
      createdAt: createdAt,
      wasRead: wasRead ?? this.wasRead,
    );
  }
}
