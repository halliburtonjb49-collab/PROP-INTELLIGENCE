import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ProviderReliabilityBanner extends StatelessWidget {
  const ProviderReliabilityBanner({
    super.key,
    required this.reliability,
    required this.selectedSite,
    this.coverageIssue,
    this.onDetails,
  });

  final Map<String, dynamic> reliability;
  final String selectedSite;
  final Map<String, dynamic>? coverageIssue;
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    if (reliability.isEmpty && coverageIssue == null) {
      return const SizedBox.shrink();
    }
    final status = reliability['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final age = (reliability['latestAgeMinutes'] as num?)?.toInt();
    final events = (reliability['eventCount'] as num?)?.toInt() ?? 0;
    final providers = (reliability['providerCount'] as num?)?.toInt() ?? 0;
    final expected =
        (reliability['expectedProviderCount'] as num?)?.toInt() ?? providers;
    final horizon = (reliability['horizonDays'] as num?)?.toInt() ?? 3;
    final recovering =
        ((reliability['recovery'] as Map?)?['requested'] as bool?) == true;
    final healthy = status == 'HEALTHY';
    final color = healthy ? const Color(0xFF55D6A3) : AppColors.gold;
    final freshness = age == null
        ? 'FRESHNESS UNKNOWN'
        : age == 0
        ? 'UPDATED NOW'
        : 'UPDATED ${age}M AGO';

    return Container(
      key: const ValueKey('provider-reliability-banner'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111A24),
        border: Border.all(color: color.withValues(alpha: 0.85)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onDetails,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    healthy
                        ? Icons.verified_rounded
                        : Icons.monitor_heart_outlined,
                    color: color,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$freshness  |  $horizon-DAY: $events EVENTS  |  '
                      '$providers/$expected PROVIDERS'
                      '${recovering ? '  |  RECOVERY RUNNING' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.15,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (onDetails != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.silver,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (coverageIssue != null)
            Container(
              key: const ValueKey('provider-coverage-warning'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF2A2110),
                border: Border(top: BorderSide(color: AppColors.gold)),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
              ),
              child: Text(
                _coverageMessage(coverageIssue!),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _coverageMessage(Map<String, dynamic> issue) {
    final category = issue['category']?.toString() ?? 'THIS CATEGORY';
    final selectedCount = (issue['selectedCount'] as num?)?.toInt() ?? 0;
    final benchmarkCount = (issue['benchmarkCount'] as num?)?.toInt() ?? 0;
    return 'LIMITED $selectedSite FEED | $category: $selectedCount synced; '
        'comparison coverage has $benchmarkCount for the same games. '
        'Refreshing automatically.';
  }
}

class ProviderReliabilitySheet extends StatelessWidget {
  const ProviderReliabilitySheet({super.key, required this.reliability});

  final Map<String, dynamic> reliability;

  @override
  Widget build(BuildContext context) {
    final providers =
        (reliability['providers'] as List?)
            ?.whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    final days =
        (reliability['days'] as List?)
            ?.whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'DATA RELIABILITY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Text(
                'Live provider freshness and upcoming slate coverage. '
                'Missing rows are never replaced with another site’s lines.',
                style: TextStyle(color: AppColors.silver, height: 1.4),
              ),
              const SizedBox(height: 18),
              const _SectionLabel('NEXT THREE DAYS'),
              const SizedBox(height: 8),
              ...days.map(
                (day) => _ReliabilityRow(
                  title: day['date']?.toString() ?? 'Unknown date',
                  detail:
                      '${day['eventCount'] ?? 0} events | '
                      '${day['propCount'] ?? 0} props | '
                      '${day['providerCount'] ?? 0} providers',
                  status: (day['propCount'] as num?)?.toInt() == 0
                      ? 'WAITING'
                      : 'READY',
                ),
              ),
              const SizedBox(height: 18),
              const _SectionLabel('PROVIDERS'),
              const SizedBox(height: 8),
              ...providers.map(
                (provider) => _ReliabilityRow(
                  title: provider['provider']?.toString() ?? 'UNKNOWN',
                  detail:
                      '${provider['propCount'] ?? 0} props | '
                      '${provider['eventCount'] ?? 0} events | '
                      '${provider['ageMinutes'] == null ? 'age unknown' : '${provider['ageMinutes']}m old'}',
                  status: provider['status']?.toString() ?? 'UNKNOWN',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.gold,
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
    ),
  );
}

class _ReliabilityRow extends StatelessWidget {
  const _ReliabilityRow({
    required this.title,
    required this.detail,
    required this.status,
  });

  final String title;
  final String detail;
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toUpperCase();
    final healthy = normalized == 'LIVE' || normalized == 'READY';
    final color = healthy ? const Color(0xFF55D6A3) : AppColors.gold;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.gunmetalLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: AppColors.silver, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            normalized,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
