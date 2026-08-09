import '../models/prop_data.dart';

/// Returns the display category that belongs to the provider's canonical
/// market key. The key is the identity attached to the line and projection,
/// so it must take precedence over a stale or loosely populated label.
String canonicalCategoryFromMarketKey(PropData prop) {
  final sport = prop.sport.trim().toUpperCase();
  if (sport != 'NBA' && sport != 'WNBA') return '';

  final raw = prop.marketKey.trim();
  if (raw.isEmpty) return '';

  final key = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool has(String value) => key.contains(value);
  if (has('points rebounds assists') || has('pts reb ast') || has(' pra')) {
    return 'PRA';
  }
  if (has('points rebounds')) return 'POINTS + REBOUNDS';
  if (has('points assists')) return 'POINTS + ASSISTS';
  if (has('rebounds assists')) return 'REBOUNDS + ASSISTS';
  if (has('double double')) return 'DOUBLE DOUBLE';
  if (has('three pointers') || has('threes')) return '3-POINTERS MADE';
  // Matched on 'fantasy' rather than 'fantasy score', and decided before
  // 'points'. The provider's key is player_fantasy_points, which contains
  // the word points, so the narrower test has to win or a fantasy line
  // reaches the card labelled POINTS -- a 36.5 fantasy number against a
  // real points line of 15.
  //
  // This function decides first and short-circuits the rest of the
  // categoriser, so fixing the fallback alone changed nothing at all.
  if (has('fantasy')) return 'FANTASY SCORE';
  if (has('points')) return 'POINTS';
  if (has('rebounds')) return 'REBOUNDS';
  if (has('assists')) return 'ASSISTS';
  if (has('blocks')) return 'BLOCKS';
  if (has('steals')) return 'STEALS';
  return '';
}

String normalizedApiCategory(PropData prop) {
  final canonical = canonicalCategoryFromMarketKey(prop);
  if (canonical.isNotEmpty) return canonical;

  final normalized = prop.category
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty ||
      const {'other', 'unknown', 'n/a', 'na'}.contains(normalized)) {
    return '';
  }

  final sport = prop.sport.trim().toUpperCase();
  final aliases = switch (sport) {
    'NBA' || 'WNBA' => const {'3-pointers': '3-POINTERS MADE'},
    'NFL' => const {
      'touchdowns': 'TOTAL TOUCHDOWNS',
      'rushing attempts': 'RUSH ATTEMPTS',
    },
    'MLB' => const {
      'strikeouts': 'PITCHER STRIKEOUTS',
      'outs recorded': 'PITCHER OUTS',
    },
    'TENNIS' => const {'games won': 'TOTAL GAMES WON'},
    'PGA' => const {
      'birdies': 'BIRDIES OR BETTER',
      'fairways': 'FAIRWAYS HIT',
      'greens': 'GREENS IN REGULATION',
    },
    'UFC' => const {'submissions': 'SUBMISSION ATTEMPTS'},
    _ => const <String, String>{},
  };
  return aliases[normalized] ?? normalized.toUpperCase();
}
