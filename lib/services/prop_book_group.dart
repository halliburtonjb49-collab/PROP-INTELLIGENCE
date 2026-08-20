import '../models/prop_data.dart';

/// The same prop as offered by several sportsbooks.
///
/// The board renders one card per book, so 13,053 distinct props arrive as
/// 28,194 cards and the worst of them appear fourteen times. This collapses
/// them to one entry each without discarding a single alternative: every
/// book stays reachable through [variants], and each variant keeps its own
/// prop id so a pick lands on the book the user actually chose.
class PropBookGroup {
  const PropBookGroup({required this.representative, required this.variants});

  /// The variant to show when the card is closed.
  final PropData representative;

  /// Every book offering this prop, best first, including the
  /// representative. Never empty.
  final List<PropData> variants;

  String get groupId => representative.propGroupId.isEmpty
      ? representative.id
      : representative.propGroupId;

  int get bookCount => variants.length;

  bool get hasAlternatives => variants.length > 1;

  /// True when the books disagree about the number, which is the case worth
  /// showing rather than hiding: it is the reason to shop.
  bool get linesDiffer => variants.map((prop) => prop.line).toSet().length > 1;
}

double _priceForRecommendedSide(PropData prop) {
  final side = prop.recommendedSide.trim().toUpperCase();
  final odds = side == 'UNDER' ? prop.underOdds : prop.overOdds;
  if (odds == null) return double.negativeInfinity;
  // American odds order by payout directly: +150 beats -110 beats -200.
  return odds;
}

/// Collapse props so each offer appears once, ordered best book first.
///
/// A prop the backend could not identify keeps its own group, so an
/// unidentifiable prop is never folded onto a card that belongs to someone
/// else. Input order is preserved between groups, because the caller has
/// already sorted the board and this must not reorder it.
List<PropBookGroup> collapsePropsByBook(List<PropData> props) {
  final order = <String>[];
  final grouped = <String, List<PropData>>{};
  for (final prop in props) {
    final key = prop.propGroupId.isEmpty ? 'solo:${prop.id}' : prop.propGroupId;
    final bucket = grouped.putIfAbsent(key, () {
      order.add(key);
      return <PropData>[];
    });
    bucket.add(prop);
  }
  return order
      .map((key) {
        final variants = [...grouped[key]!];
        variants.sort((left, right) {
          // A stale price is not an option, however good it looks.
          final selectable =
              (right.isSelectable ? 1 : 0) - (left.isSelectable ? 1 : 0);
          if (selectable != 0) return selectable;
          final price = _priceForRecommendedSide(
            right,
          ).compareTo(_priceForRecommendedSide(left));
          if (price != 0) return price;
          // Stable: two books at the same price must not swap between rebuilds.
          return left.sportsbook.compareTo(right.sportsbook);
        });
        return PropBookGroup(
          representative: variants.first,
          variants: variants,
        );
      })
      .toList(growable: false);
}
