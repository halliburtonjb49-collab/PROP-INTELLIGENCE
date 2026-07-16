import 'package:flutter/material.dart';

class GoblinManager {
  // Tracks whether Goblins-only mode is active.
  static final ValueNotifier<bool> showGoblinsOnly = ValueNotifier<bool>(false);

  static void toggleGoblinFilter() {
    showGoblinsOnly.value = !showGoblinsOnly.value;
  }
}
