import 'package:flutter/material.dart';

class FilterManager {
  // Tracks active sportsbook filter selections. Default state is ALL.
  static final ValueNotifier<Set<String>> activeBookFilter =
      ValueNotifier<Set<String>>({'ALL'});

  static void updateFilter(String sportsbookName) {
    final normalized = sportsbookName.toUpperCase();
    final current = Set<String>.from(activeBookFilter.value);

    if (normalized == 'ALL') {
      activeBookFilter.value = {'ALL'};
      return;
    }

    current.remove('ALL');
    if (current.contains(normalized)) {
      current.remove(normalized);
    } else {
      current.add(normalized);
    }

    activeBookFilter.value = current.isEmpty ? {'ALL'} : current;
  }
}
