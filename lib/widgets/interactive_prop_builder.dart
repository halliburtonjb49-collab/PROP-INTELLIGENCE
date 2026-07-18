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
  static const _markets = ['Points', 'Rebounds', 'Assists', 'Threes'];
  String selectedStatCategory = 'Points';
  double targetThresholdValue = 25.5;

  void _addLeg() {
    SlipManager.togglePropSelection({
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
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$selectedStatCategory ${targetThresholdValue.toStringAsFixed(1)} added to your slip.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'PROP BUILDER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Build a custom leg, set its line, then add it to your active slip.',
            style: TextStyle(color: AppColors.silver, fontSize: 13),
          ),
          const SizedBox(height: 20),
          DashboardPanel(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final controls = [
                  _StepSection(
                    number: '01',
                    title: 'Choose a market',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _markets
                          .map((market) {
                            final selected = market == selectedStatCategory;
                            return ChoiceChip(
                              label: Text(market),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => selectedStatCategory = market),
                              selectedColor: AppColors.blue.withValues(
                                alpha: .18,
                              ),
                              backgroundColor: AppColors.panelLight,
                              side: BorderSide(
                                color: selected
                                    ? AppColors.blue
                                    : Colors.white12,
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? AppColors.blue
                                    : Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                  _StepSection(
                    number: '02',
                    title: 'Set the line',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              '0.5',
                              style: TextStyle(color: Colors.white38),
                            ),
                            Expanded(
                              child: Slider(
                                value: targetThresholdValue,
                                min: 0.5,
                                max: 45.5,
                                divisions: 90,
                                activeColor: AppColors.blue,
                                inactiveColor: Colors.white10,
                                onChanged: (value) => setState(
                                  () => targetThresholdValue = double.parse(
                                    value.toStringAsFixed(1),
                                  ),
                                ),
                              ),
                            ),
                            const Text(
                              '45.5',
                              style: TextStyle(color: Colors.white38),
                            ),
                          ],
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.gunmetal,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.blue.withValues(alpha: .45),
                            ),
                          ),
                          child: Text(
                            '${targetThresholdValue.toStringAsFixed(1)} $selectedStatCategory',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (compact) ...[
                      controls[0],
                      const SizedBox(height: 24),
                      controls[1],
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: controls[0]),
                          const SizedBox(width: 28),
                          Expanded(child: controls[1]),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: compact ? double.infinity : 280,
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _addLeg,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('ADD TO ACTIVE SLIP'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StepSection extends StatelessWidget {
  const _StepSection({
    required this.number,
    required this.title,
    required this.child,
  });

  final String number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              number,
              style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}
