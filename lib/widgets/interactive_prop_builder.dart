import 'package:flutter/material.dart';

import '../services/slip_manager.dart';
import '../theme/app_colors.dart';
import 'dashboard_panel.dart';

class InteractiveConstructorEngineWidget extends StatefulWidget {
  const InteractiveConstructorEngineWidget({super.key});

  @override
  State<InteractiveConstructorEngineWidget> createState() =>
      _InteractiveConstructorEngineWidgetState();
}

class _InteractiveConstructorEngineWidgetState
    extends State<InteractiveConstructorEngineWidget> {
  String selectedStatCategory = 'Points';
  double targetThresholdValue = 25.5;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROP BUILDER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Construct alternative parlay configurations and combine custom player variables to simulate combined odds matrices.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 14),
          DashboardPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. CHOOSE STATISTIC TARGET',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatCategory,
                  dropdownColor: AppColors.panel,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: AppColors.panelLight,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white10),
                    ),
                  ),
                  items: const ['Points', 'Rebounds', 'Assists', 'Threes']
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      selectedStatCategory = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  '2. ADJUST VALUE THRESHOLD: ${targetThresholdValue.toStringAsFixed(1)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Slider(
                  value: targetThresholdValue,
                  min: 0.5,
                  max: 45.5,
                  divisions: 90,
                  activeColor: AppColors.gold,
                  inactiveColor: Colors.white10,
                  onChanged: (value) {
                    setState(() {
                      targetThresholdValue = double.parse(
                        value.toStringAsFixed(1),
                      );
                    });
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final customConstructedProp = {
                        'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
                        'player_name': 'Custom Parlay Leg',
                        'market_type': selectedStatCategory,
                        'line': targetThresholdValue,
                        'sportsbook': 'CUSTOM',
                        'odds_data': const [
                          {
                            'bookmaker': 'Custom',
                            'over_odds': -110,
                            'under_odds': -110,
                            'last_update': 'Manual',
                          },
                        ],
                        'is_goblin_line': false,
                      };
                      SlipManager.togglePropSelection(customConstructedProp);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'ADD CUSTOM LEG TO CURRENT SLIP',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
