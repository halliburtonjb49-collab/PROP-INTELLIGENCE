import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PersonalEdgeDimension {
  const PersonalEdgeDimension({
    required this.dimension,
    required this.name,
    required this.hitRate,
    required this.resolvedLegs,
  });

  final String dimension;
  final String name;
  final double hitRate;
  final int resolvedLegs;

  String get evidence => resolvedLegs >= 20 ? 'ESTABLISHED' : 'DEVELOPING';
}

List<PersonalEdgeDimension> buildPersonalEdgeProfile(
  Map<String, dynamic> performance, {
  int minimumResolvedLegs = 5,
}) {
  const sources = <(String, String)>[
    ('SPORT', 'leg_performance_by_sport'),
    ('MARKET', 'leg_performance_by_market'),
    ('SIDE', 'leg_performance_by_side'),
    ('CONFIDENCE', 'leg_performance_by_confidence'),
    ('PROP SITE', 'leg_performance_by_prop_site'),
  ];
  final result = <PersonalEdgeDimension>[];
  for (final source in sources) {
    final candidates = <PersonalEdgeDimension>[];
    for (final raw in (performance[source.$2] as List? ?? const [])) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final resolved = (row['resolved_legs'] as num?)?.toInt() ?? 0;
      final name = row['name']?.toString().trim() ?? '';
      if (resolved < minimumResolvedLegs || name.isEmpty) continue;
      candidates.add(
        PersonalEdgeDimension(
          dimension: source.$1,
          name: name,
          hitRate: (row['leg_hit_rate'] as num?)?.toDouble() ?? 0,
          resolvedLegs: resolved,
        ),
      );
    }
    candidates.sort((a, b) {
      final rate = b.hitRate.compareTo(a.hitRate);
      return rate != 0 ? rate : b.resolvedLegs.compareTo(a.resolvedLegs);
    });
    if (candidates.isNotEmpty) result.add(candidates.first);
  }
  return result;
}

class PersonalEdgeProfileCard extends StatelessWidget {
  const PersonalEdgeProfileCard({super.key, required this.performance});

  final Map<String, dynamic> performance;

  @override
  Widget build(BuildContext context) {
    final dimensions = buildPersonalEdgeProfile(performance);
    return Container(
      key: const ValueKey('personal-edge-profile'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: .75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.person_search_outlined,
                color: AppColors.gold,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'PERSONAL EDGE PROFILE',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Your strongest researched segments from your own graded Builder history. Pending legs are excluded.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (dimensions.isEmpty)
            const Text(
              'Keep tracking builds. Each segment needs at least 5 resolved legs before PI identifies a personal edge.',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in dimensions)
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 155,
                      maxWidth: 220,
                    ),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.dimension,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${item.hitRate.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${item.resolvedLegs} resolved · ${item.evidence}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          const Text(
            'Personal history describes past tracking results; it does not guarantee future outcomes.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 8),
          ),
        ],
      ),
    );
  }
}
