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
    'NBA' || 'WNBA' => const {
      'player points': 'POINTS',
      'player rebounds': 'REBOUNDS',
      'player assists': 'ASSISTS',
      'player points rebounds assists': 'PRA',
      'player points rebounds': 'POINTS + REBOUNDS',
      'player points assists': 'POINTS + ASSISTS',
      'player rebounds assists': 'REBOUNDS + ASSISTS',
      '3-pointers': '3-POINTERS MADE',
    },
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

/// The display category for a market, derived from its raw key.
///
/// Compound and derived markets must be decided before the single-word
/// markets they contain. For example, fantasy points must be decided before
/// points and hits + runs + RBIs before RBIs.
bool _matchesAny(String value, List<String> matches) =>
    matches.any(value.contains);
String marketCategoryFor(String sport, String rawMarket) {
  final raw = rawMarket
      .toUpperCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (sport == 'NBA' || sport == 'WNBA') {
    if (_matchesAny(raw, ['DOUBLE DOUBLE', 'DOUBLEDOUBLE'])) {
      return 'DOUBLE DOUBLE';
    }
    if (_matchesAny(raw, [
      'PRA',
      'PTS REB AST',
      'POINTS REBOUNDS ASSISTS',
      'POINTS + REBOUNDS + ASSISTS',
    ])) {
      return 'PRA';
    }
    if (_matchesAny(raw, ['POINTS REBOUNDS', 'POINTS + REBOUNDS', 'PTS REB'])) {
      return 'POINTS + REBOUNDS';
    }
    if (_matchesAny(raw, ['POINTS ASSISTS', 'POINTS + ASSISTS', 'PTS AST'])) {
      return 'POINTS + ASSISTS';
    }
    if (_matchesAny(raw, [
      'REBOUNDS ASSISTS',
      'REBOUNDS + ASSISTS',
      'REB AST',
    ])) {
      return 'REBOUNDS + ASSISTS';
    }
    // The feed calls this market player_fantasy_points, which reads as
    // FANTASY POINTS here -- not FANTASY SCORE. Matching only the
    // latter let it fall through to the generic POINTS test below,
    // which any string containing POINTS passes. A 36.5 fantasy line
    // was then drawn on the card as a 36.5 points line, against a
    // player whose actual points line was 15.
    if (raw.contains('FANTASY')) {
      return 'FANTASY SCORE';
    }
    if (_matchesAny(raw, ['BLOCKS STEALS', 'BLOCKS + STEALS', 'STOCKS'])) {
      return 'BLOCKS + STEALS';
    }
    if (raw.contains('TURNOVER')) {
      return 'TURNOVERS';
    }
    if (_matchesAny(raw, ['FREE THROWS MADE', 'FREE THROWS'])) {
      return 'FREE THROWS MADE';
    }
    if (_matchesAny(raw, ['FIELD GOALS MADE', 'FIELD GOALS'])) {
      return 'FIELD GOALS MADE';
    }
    if (_matchesAny(raw, [
      '3 POINTERS MADE',
      'THREE POINTERS MADE',
      '3PM',
      'MADE THREES',
    ])) {
      return '3-POINTERS MADE';
    }
    if (_matchesAny(raw, ['POINTS', 'PLAYER POINTS'])) {
      return 'POINTS';
    }
    if (_matchesAny(raw, ['REBOUNDS', 'PLAYER REBOUNDS'])) {
      return 'REBOUNDS';
    }
    if (_matchesAny(raw, ['ASSISTS', 'PLAYER ASSISTS'])) {
      return 'ASSISTS';
    }
    if (raw.contains('BLOCK')) {
      return 'BLOCKS';
    }
    if (raw.contains('STEAL')) {
      return 'STEALS';
    }
  }
  if (sport == 'NFL') {
    if (raw.contains('PASSING YARD')) {
      return 'PASSING YARDS';
    }
    if (raw.contains('RUSHING YARD')) {
      return 'RUSHING YARDS';
    }
    if (_matchesAny(raw, ['RUSHING ATTEMPT', 'RUSH ATTEMPT'])) {
      return 'RUSH ATTEMPTS';
    }
    if (raw.contains('RECEIVING YARD')) {
      return 'RECEIVING YARDS';
    }
    if (_matchesAny(raw, [
      'TOTAL TOUCHDOWNS',
      'ANYTIME TOUCHDOWN',
      'TOUCHDOWNS',
      'TOTAL TDS',
    ])) {
      return 'TOTAL TOUCHDOWNS';
    }
    // Four different markets contain the word RECEPTION, and a bare
    // substring test gave all of them to RECEPTIONS -- so a 65.5 receiving
    // yards line was drawn as RECEPTIONS 65.5 against a real receptions line
    // of about four. Same defect as the fantasy market, different word.
    if (_matchesAny(raw, ['RUSH RECEPTION YDS', 'RUSH REC YDS'])) {
      return 'RUSH + REC YARDS';
    }
    if (_matchesAny(raw, ['RECEPTION YDS', 'RECEIVING YARDS', 'REC YDS'])) {
      return 'RECEIVING YARDS';
    }
    if (_matchesAny(raw, ['RECEPTION TDS', 'RECEIVING TDS', 'REC TDS'])) {
      return 'RECEIVING TDS';
    }
    if (_matchesAny(raw, ['RECEPTION LONGEST', 'LONGEST RECEPTION'])) {
      return 'LONGEST RECEPTION';
    }
    if (raw.contains('RECEPTION')) {
      return 'RECEPTIONS';
    }
    if (raw.contains('PASS ATTEMPT')) {
      return 'PASS ATTEMPTS';
    }
    if (_matchesAny(raw, ['PASS COMPLETION', 'COMPLETIONS'])) {
      return 'COMPLETIONS';
    }
  }
  if (sport == 'SOCCER') {
    if (_matchesAny(raw, ['SHOTS ON TARGET', 'SHOT ON TARGET', 'SOT'])) {
      return 'SHOTS ON TARGET';
    }
    if (raw.contains('SHOT')) {
      return 'SHOTS';
    }
    if (raw.contains('GOAL') && !raw.contains('GOALKEEPER')) {
      return 'GOALS';
    }
    if (raw.contains('ASSIST')) {
      return 'ASSISTS';
    }
    if (_matchesAny(raw, [
      'PASSES ATTEMPTED',
      'PASS ATTEMPTS',
      'TOTAL PASSES',
    ])) {
      return 'PASSES ATTEMPTED';
    }
    if (raw.contains('SAVE')) {
      return 'SAVES';
    }
    if (raw.contains('TACKLE')) {
      return 'TACKLES';
    }
  }
  if (sport == 'MLB') {
    if (_matchesAny(raw, [
      'PITCHER STRIKEOUTS',
      'PITCHING STRIKEOUTS',
      'STRIKEOUTS THROWN',
      'PITCHER KS',
    ])) {
      return 'PITCHER STRIKEOUTS';
    }
    if (_matchesAny(raw, ['PITCHER OUTS', 'OUTS RECORDED', 'PITCHING OUTS'])) {
      return 'PITCHER OUTS';
    }
    if (raw.contains('HITS ALLOWED')) {
      return 'HITS ALLOWED';
    }
    if (_matchesAny(raw, ['HOME RUNS', 'HOME RUN'])) {
      return 'HOME RUNS';
    }
    // Decided before RBIS, which it contains. A hits+runs+rbis line runs
    // around three; an rbis line runs under one, so collapsing them puts a
    // number on the card that belongs to a different bet.
    if (_matchesAny(raw, ['HITS RUNS RBIS', 'HITS RUNS RBI'])) {
      return 'HITS + RUNS + RBIS';
    }
    if (_matchesAny(raw, ['RBIS', 'RBI', 'RUNS BATTED IN'])) {
      return 'RBIS';
    }
    if (raw.contains('TOTAL BASE')) {
      return 'TOTAL BASES';
    }
    if (_matchesAny(raw, ['PLAYER HITS', 'HITS'])) {
      return 'HITS';
    }
  }
  if (sport == 'TENNIS') {
    if (raw.contains('ACE')) {
      return 'ACES';
    }
    if (_matchesAny(raw, ['TOTAL GAMES WON', 'GAMES WON', 'PLAYER GAMES'])) {
      return 'TOTAL GAMES WON';
    }
    if (_matchesAny(raw, ['MATCH WINNER', 'MONEYLINE', 'TO WIN MATCH'])) {
      return 'MATCH WINNER';
    }
  }
  if (sport == 'PGA') {
    if (_matchesAny(raw, ['BIRDIES OR BETTER', 'BIRDIES', 'BIRDIE'])) {
      return 'BIRDIES OR BETTER';
    }
    if (_matchesAny(raw, ['ROUND SCORE', 'STROKES', 'ROUND STROKES'])) {
      return 'ROUND SCORE';
    }
    if (raw.contains('FAIRWAY')) {
      return 'FAIRWAYS HIT';
    }
    if (_matchesAny(raw, ['GREENS IN REGULATION', 'GIR'])) {
      return 'GREENS IN REGULATION';
    }
    if (raw.contains('HOLES PLAYED')) {
      return 'HOLES PLAYED';
    }
    if (_matchesAny(raw, ['MAKE CUT', 'MADE CUT', 'TO MAKE THE CUT'])) {
      return 'MAKE CUT';
    }
  }
  if (sport == 'UFC') {
    if (_matchesAny(raw, [
      'SIGNIFICANT STRIKES',
      'SIG STRIKES',
      'SIG. STRIKES',
      'SIGNIFICANT STRIKES LANDED',
    ])) {
      return 'SIGNIFICANT STRIKES';
    }
    if (_matchesAny(raw, [
      'TOTAL STRIKES',
      'STRIKES LANDED',
      'TOTAL STRIKES LANDED',
    ])) {
      return 'TOTAL STRIKES';
    }
    if (_matchesAny(raw, [
      'TAKEDOWN ATTEMPTS',
      'TAKEDOWNS ATTEMPTED',
      'TD ATTEMPTS',
    ])) {
      return 'TAKEDOWN ATTEMPTS';
    }
    if (_matchesAny(raw, ['TAKEDOWNS', 'TAKEDOWNS LANDED', 'TD LANDED'])) {
      return 'TAKEDOWNS';
    }
    if (_matchesAny(raw, [
      'CONTROL TIME',
      'GROUND CONTROL TIME',
      'TOP CONTROL TIME',
    ])) {
      return 'CONTROL TIME';
    }
    if (_matchesAny(raw, ['KNOCKDOWNS', 'KNOCKDOWNS LANDED'])) {
      return 'KNOCKDOWNS';
    }
    if (_matchesAny(raw, ['SUBMISSION ATTEMPTS', 'SUB ATTEMPTS'])) {
      return 'SUBMISSION ATTEMPTS';
    }
    if (_matchesAny(raw, ['FIGHT TIME', 'TOTAL FIGHT TIME', 'TIME OF FIGHT'])) {
      return 'FIGHT TIME';
    }
    if (_matchesAny(raw, [
      'TOTAL ROUNDS',
      'ROUNDS COMPLETED',
      'FIGHT ROUNDS',
    ])) {
      return 'ROUNDS';
    }
    if (_matchesAny(raw, [
      'FIGHT WINNER',
      'MATCH WINNER',
      'MONEYLINE',
      'TO WIN',
    ])) {
      return 'FIGHT WINNER';
    }
    if (_matchesAny(raw, [
      'METHOD OF VICTORY',
      'WIN METHOD',
      'KO TKO',
      'SUBMISSION',
      'DECISION',
    ])) {
      return 'METHOD OF VICTORY';
    }
  }
  return raw;
}
