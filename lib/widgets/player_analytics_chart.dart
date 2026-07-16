import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class PlayerAnalyticsChart extends StatelessWidget {
  final double targetLine;
  final List<double> last10GameStats;

  const PlayerAnalyticsChart({
    super.key,
    required this.targetLine,
    required this.last10GameStats,
  });

  @override
  Widget build(BuildContext context) {
    const primaryYellow = Color(0xFFFFD700);
    final safeTarget = targetLine <= 0 ? 1.0 : targetLine;
    final highestStat = last10GameStats.isEmpty
        ? safeTarget
        : last10GameStats.reduce((a, b) => a > b ? a : b);
    final maxY = (highestStat > safeTarget ? highestStat : safeTarget) * 1.25;

    return SizedBox(
      height: 160,
      child: Padding(
        padding: const EdgeInsets.only(top: 12, right: 12),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(enabled: true),
            titlesData: FlTitlesData(
              show: true,
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) => Text(
                    'G${value.toInt() + 1}',
                    style: const TextStyle(color: Colors.grey, fontSize: 9),
                  ),
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: safeTarget,
                  color: primaryYellow.withValues(alpha: 0.8),
                  strokeWidth: 2,
                  dashArray: const [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.centerRight,
                    style: const TextStyle(
                      color: primaryYellow,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    labelResolver: (_) =>
                        ' Line: ${safeTarget.toStringAsFixed(1)}',
                  ),
                ),
              ],
            ),
            barGroups: List.generate(last10GameStats.length, (index) {
              final actualStat = last10GameStats[index];
              final hitOver = actualStat >= safeTarget;

              return BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: actualStat,
                    color: hitOver
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFF5252),
                    width: 14,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
