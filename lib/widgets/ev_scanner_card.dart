import 'package:flutter/material.dart';

import '../theme/prop_intelligence_colors.dart';
import 'prop_intelligence_branded_logo.dart';
import 'context_help.dart';

class PositiveEvScannerCard extends StatelessWidget {
  final String player;
  final String propType;
  final double lineValue;
  final String slowBookmaker;
  final int slowBookOdds;
  final double evPercentage;
  final double fairProbability;

  const PositiveEvScannerCard({
    super.key,
    required this.player,
    required this.propType,
    required this.lineValue,
    required this.slowBookmaker,
    required this.slowBookOdds,
    required this.evPercentage,
    required this.fairProbability,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PropIntelligenceColors.darkCardBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: PropIntelligenceColors.premiumGold.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const PropIntelligenceBrandedLogo(
                    height: 22,
                    showSubtext: false,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    player,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+$evPercentage% EV',
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const ContextHelp(
                    title: 'Expected value (+EV)',
                    message:
                        'Positive expected value means the model believes the offered odds are better than the estimated fair odds. EV is a long-run mathematical estimate; an individual wager can still lose.',
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BET TARGET MARKET',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$propType O/U $lineValue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Tooltip(
                    message:
                        'Model-estimated probability before sportsbook margin',
                    child: Text(
                      'FAIR PROB',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$fairProbability%',
                    style: const TextStyle(
                      color: PropIntelligenceColors.premiumGold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'MISPRICED BOOK',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$slowBookmaker (${slowBookOdds > 0 ? '+$slowBookOdds' : slowBookOdds})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
