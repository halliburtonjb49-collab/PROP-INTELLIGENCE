/// Current base payout rules for the pick'em products represented in PI.
///
/// These tables intentionally model only standard selections. Alternative
/// lines, boosted/easier picks, correlated selections, promotions, voids, and
/// jurisdiction-specific products can change the multiplier shown by a site.
/// In those cases the provider-displayed multiplier remains authoritative.
String normalizePickemSite(String value) {
  final source = value.toUpperCase();
  if (source.contains('PRIZEPICKS') || source.contains('PRIZE PICKS')) {
    return 'PRIZEPICKS';
  }
  if (source.contains('UNDERDOG')) return 'UNDERDOG';
  if (source.contains('BETR')) return 'BETR';
  if (source.contains('PICK6') || source.contains('PICK 6')) return 'PICK6';
  if (source.contains('FANDUEL PICKS')) return 'FANDUEL_PICKS';
  if (source.contains('FANDUEL')) return 'FANDUEL';
  if (source.contains('DRAFTKINGS')) return 'DRAFTKINGS';
  return 'PRIZEPICKS';
}

List<String> pickemEntryTypesForSite(String site) => switch (site) {
  'PRIZEPICKS' => const ['POWER', 'FLEX'],
  'UNDERDOG' => const ['STANDARD', 'FLEX'],
  'BETR' => const ['PERFECT', 'FLEX'],
  'PICK6' => const ['CONTEST'],
  'FANDUEL_PICKS' => const ['DISCONTINUED'],
  'FANDUEL' || 'DRAFTKINGS' => const ['PARLAY'],
  _ => const ['STANDARD'],
};

bool isPoolBasedPayout(String site) => site == 'PICK6';

bool isDiscontinuedPickemProduct(String site) => site == 'FANDUEL_PICKS';

/// Returns base payout multipliers keyed by the number of correct selections.
/// An empty map means the provider determines the payout dynamically.
Map<int, double> basePickemPayoutOutcomes({
  required String site,
  required String entryType,
  required int legCount,
}) {
  final type = entryType.toUpperCase();
  if (site == 'PRIZEPICKS' && type == 'POWER') {
    final multiplier = const {
      2: 3.0,
      3: 6.0,
      4: 10.0,
      5: 20.0,
      6: 37.5,
    }[legCount];
    return multiplier == null ? const {} : {legCount: multiplier};
  }
  if (site == 'PRIZEPICKS' && type == 'FLEX') {
    return switch (legCount) {
      2 => const {2: 2.0, 1: 0.5},
      3 => const {3: 3.0, 2: 1.0},
      4 => const {4: 6.0, 3: 1.5},
      5 => const {5: 10.0, 4: 2.0, 3: 0.4},
      6 => const {6: 25.0, 5: 2.0, 4: 0.4},
      _ => const {},
    };
  }
  if (site == 'UNDERDOG' && type == 'STANDARD') {
    final multiplier = const {
      2: 3.5,
      3: 6.5,
      4: 12.0,
      5: 20.0,
      6: 35.0,
      7: 65.0,
      8: 120.0,
    }[legCount];
    return multiplier == null ? const {} : {legCount: multiplier};
  }
  if (site == 'UNDERDOG' && type == 'FLEX') {
    return switch (legCount) {
      3 => const {3: 3.25, 2: 1.09},
      4 => const {4: 6.0, 3: 1.5},
      5 => const {5: 10.0, 4: 2.5},
      6 => const {6: 25.0, 5: 2.6, 4: 0.25},
      7 => const {7: 40.0, 6: 2.75, 5: 0.5},
      8 => const {8: 80.0, 7: 3.0, 6: 1.0},
      _ => const {},
    };
  }
  if (site == 'BETR' && type == 'PERFECT') {
    final multiplier = const {
      2: 3.0,
      3: 5.0,
      4: 10.0,
      5: 20.0,
      6: 30.0,
      7: 50.0,
      8: 100.0,
    }[legCount];
    return multiplier == null ? const {} : {legCount: multiplier};
  }
  if (site == 'BETR' && type == 'FLEX') {
    return switch (legCount) {
      3 => const {3: 3.0, 2: 1.0},
      4 => const {4: 6.0, 3: 1.5},
      5 => const {5: 10.0, 4: 2.0, 3: 0.4},
      6 => const {6: 20.0, 5: 1.5, 4: 1.0},
      7 => const {7: 35.0, 6: 2.0, 5: 1.25},
      8 => const {8: 50.0, 7: 2.0, 6: 1.5, 5: 1.25},
      9 => const {9: 100.0, 8: 2.0, 7: 1.5, 6: 1.25},
      10 => const {10: 200.0, 9: 2.0, 8: 1.5, 7: 1.25, 6: 1.0},
      _ => const {},
    };
  }
  return const {};
}

double? basePickemMaxMultiplier({
  required String site,
  required String entryType,
  required int legCount,
}) {
  final outcomes = basePickemPayoutOutcomes(
    site: site,
    entryType: entryType,
    legCount: legCount,
  );
  return outcomes[legCount];
}

String formatPickemMultiplier(double multiplier) {
  if (multiplier == multiplier.roundToDouble()) {
    return multiplier.toStringAsFixed(0);
  }
  return multiplier
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
