import 'package:flutter/material.dart';

class BuilderStrategyPanel extends StatelessWidget {
  const BuilderStrategyPanel({
    super.key,
    required this.isLoading,
    required this.strategy,
    required this.marketLabel,
    required this.onApply,
  });

  final bool isLoading;
  final Map<String, dynamic>? strategy;
  final String Function(String value) marketLabel;
  final VoidCallback onApply;

  Map<String, dynamic>? _strategyItem(String key) {
    final item = strategy?[key];
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    return null;
  }

  String _strategyName(String key) {
    return _strategyItem(key)?['name']?.toString() ?? 'Not enough data';
  }

  double _strategyHitRate(String key) {
    return (_strategyItem(key)?['hit_rate'] as num?)?.toDouble() ?? 0;
  }

  int _strategySample(String key) {
    return (_strategyItem(key)?['sample_size'] as num?)?.toInt() ?? 0;
  }

  Widget _strategyMetric(
    BuildContext context, {
    required String label,
    required String value,
    required String detail,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const LinearProgressIndicator();
    final resolvedStrategy = strategy;
    if (resolvedStrategy == null) {
      return const Text('Strategy recommendations are unavailable.');
    }
    final enoughData = resolvedStrategy['enough_data'] == true;
    final resolvedLegs =
        (resolvedStrategy['resolved_legs'] as num?)?.toInt() ?? 0;
    final requiredLegs =
        (resolvedStrategy['minimum_required_legs'] as num?)?.toInt() ?? 10;
    final warnings = resolvedStrategy['warnings'] as List<dynamic>? ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'RECOMMENDED STRATEGY',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Chip(
                label: Text(
                  enoughData
                      ? 'DATA READY'
                      : '$resolvedLegs/$requiredLegs LEGS',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 3 : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 1 ? 4 : 1.8,
                children: [
                  _strategyMetric(
                    context,
                    label: 'BEST SPORT',
                    value: _strategyName('recommended_sport'),
                    detail:
                        '${_strategyHitRate('recommended_sport').toStringAsFixed(1)}% hit rate • ${_strategySample('recommended_sport')} legs',
                    icon: Icons.sports,
                  ),
                  _strategyMetric(
                    context,
                    label: 'BEST PROP SITE',
                    value: _strategyName('recommended_prop_site'),
                    detail:
                        '${_strategyHitRate('recommended_prop_site').toStringAsFixed(1)}% hit rate • ${_strategySample('recommended_prop_site')} legs',
                    icon: Icons.storefront,
                  ),
                  _strategyMetric(
                    context,
                    label: 'BEST MARKET',
                    value: marketLabel(_strategyName('recommended_market')),
                    detail:
                        '${_strategyHitRate('recommended_market').toStringAsFixed(1)}% hit rate • ${_strategySample('recommended_market')} legs',
                    icon: Icons.query_stats,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  'Minimum Edge: ${resolvedStrategy['recommended_minimum_edge']}%',
                ),
              ),
              Chip(
                label: Text(
                  'Minimum Confidence: ${resolvedStrategy['recommended_minimum_confidence']}%',
                ),
              ),
              Chip(
                label: Text(
                  'Recommended Legs: ${resolvedStrategy['recommended_leg_count']}',
                ),
              ),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 17),
                    const SizedBox(width: 7),
                    Expanded(child: Text(warning.toString())),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enoughData ? onApply : null,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('APPLY RECOMMENDED STRATEGY'),
            ),
          ),
        ],
      ),
    );
  }
}
