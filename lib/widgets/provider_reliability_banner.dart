import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_manager.dart';
import '../theme/app_colors.dart';

class ProviderReliabilityBanner extends StatelessWidget {
  const ProviderReliabilityBanner({
    super.key,
    required this.reliability,
    required this.selectedSite,
    this.coverageIssue,
    this.onDetails,
    this.feedIsRecovery = false,
  });

  final Map<String, dynamic> reliability;
  final String selectedSite;
  final Map<String, dynamic>? coverageIssue;
  final VoidCallback? onDetails;

  /// The board is being served from the durable snapshot because the live
  /// catalog could not be reached. The lines are real but may be hours old,
  /// and nothing else on the card distinguishes them from current ones.
  final bool feedIsRecovery;

  @override
  Widget build(BuildContext context) {
    // A recovery feed must announce itself even when no reliability
    // telemetry arrived; those are the moments it matters most.
    if (reliability.isEmpty && coverageIssue == null && !feedIsRecovery) {
      return const SizedBox.shrink();
    }
    final status = reliability['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final age = (reliability['latestAgeMinutes'] as num?)?.toInt();
    final events = (reliability['eventCount'] as num?)?.toInt() ?? 0;
    final providers = (reliability['providerCount'] as num?)?.toInt() ?? 0;
    final expected =
        (reliability['expectedProviderCount'] as num?)?.toInt() ?? providers;
    final withoutInventory = (expected - providers).clamp(0, expected);
    final providerRows = (reliability['providers'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final staleProviders = providerRows.where((provider) {
      final providerStatus = provider['status']?.toString().toUpperCase() ?? '';
      final providerAge = (provider['ageMinutes'] as num?)?.toInt();
      return providerStatus == 'STALE' ||
          providerStatus == 'OFFLINE' ||
          providerStatus == 'ERROR' ||
          (providerAge != null && providerAge >= 15);
    }).toList(growable: false);
    final showOwnerStaleAlert =
        AuthManager.instance.sessionState.value.isOwner &&
        staleProviders.isNotEmpty;
    final horizon =
        (reliability['futureDays'] as num?)?.toInt() ??
        (reliability['horizonDays'] as num?)?.toInt() ??
        3;
    final recovering =
        ((reliability['recovery'] as Map?)?['requested'] as bool?) == true;
    final stale = feedIsRecovery || (age != null && age >= 15);
    final aging = !stale && age != null && age >= 8;
    final healthy = status == 'HEALTHY' && !stale;
    final color = stale
        ? const Color(0xFFFF8A80)
        : aging
        ? AppColors.gold
        : healthy
        ? const Color(0xFF55D6A3)
        : AppColors.gold;
    final freshness = age == null
        ? 'FRESHNESS UNKNOWN'
        : age == 0
        ? 'UPDATED NOW'
        : 'UPDATED ${age}M AGO';
    final freshnessState = stale
        ? 'STALE DATA'
        : aging
        ? 'REFRESH DUE'
        : 'LIVE';

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
          if (feedIsRecovery)
            Container(
              key: const ValueKey('feed-recovery-warning'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF3A1D14),
                border: Border(
                  bottom: BorderSide(color: AppColors.gold, width: 1),
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    color: AppColors.gold,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'RECOVERY FEED  |  LINES MAY BE OUT OF DATE  |  '
                      'CONFIRM AT THE SPORTSBOOK BEFORE BETTING',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.15,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (showOwnerStaleAlert)
            Container(
              key: const ValueKey('owner-stale-provider-alert'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF3A1D14),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFFF8A80), width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notification_important_rounded,
                    color: Color(0xFFFF8A80),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'OWNER ALERT  |  STALE PROVIDER${staleProviders.length == 1 ? '' : 'S'}: '
                      '${staleProviders.map((row) => row['provider']?.toString() ?? 'UNKNOWN').join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                      '$freshnessState  |  $freshness  |  '
                      '$horizon-DAY: $events EVENTS  |  '
                      '$providers ACTIVE  |  $withoutInventory WITHOUT CURRENT INVENTORY'
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

class ProviderReliabilitySheet extends StatefulWidget {
  const ProviderReliabilitySheet({super.key, required this.reliability});

  final Map<String, dynamic> reliability;

  @override
  State<ProviderReliabilitySheet> createState() =>
      _ProviderReliabilitySheetState();
}

class _ProviderReliabilitySheetState extends State<ProviderReliabilitySheet> {
  Timer? _timer;
  late DateTime _now;
  String _selectedSport = 'ALL';

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _countdown() {
    final target = DateTime.tryParse(
      widget.reliability['nextAutoRefreshAtUtc']?.toString() ?? '',
    )?.toLocal();
    if (target == null) return 'Refresh schedule unavailable';
    final remaining = target.difference(_now);
    if (remaining.isNegative) return 'Automatic refresh due now';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    return 'Automatic refresh in ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _clock(Object? raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (value == null) return 'not available';
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final reliability = widget.reliability;
    final providers = (reliability['providers'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final days = (reliability['days'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final health = (reliability['marketHealth'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    health.sort((a, b) {
      final coverageCompare = ((a['coveragePercent'] as num?)?.toInt() ?? 0)
          .compareTo((b['coveragePercent'] as num?)?.toInt() ?? 0);
      if (coverageCompare != 0) return coverageCompare;
      return ((b['propCount'] as num?)?.toInt() ?? 0).compareTo(
        (a['propCount'] as num?)?.toInt() ?? 0,
      );
    });
    final sports =
        health
            .map((row) => row['sport']?.toString() ?? 'OTHER')
            .toSet()
            .toList()
          ..sort();
    final activeSport =
        _selectedSport == 'ALL' || sports.contains(_selectedSport)
        ? _selectedSport
        : 'ALL';
    final filteredHealth = activeSport == 'ALL'
        ? health
        : health
              .where((row) => row['sport']?.toString() == activeSport)
              .toList(growable: false);
    final missingToday = days.isEmpty
        ? const <String>[]
        : (days.first['missingProviders'] as List? ?? const [])
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false);
    final greenCount = health
        .where((row) => row['status']?.toString().toUpperCase() == 'GREEN')
        .length;
    final yellowCount = health
        .where((row) => row['status']?.toString().toUpperCase() == 'YELLOW')
        .length;
    final redCount = health
        .where((row) => row['status']?.toString().toUpperCase() == 'RED')
        .length;

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          shrinkWrap: true,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'THREE-DAY SLATE CENTER',
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
              'Today plus the next three dates. Provider gaps and potentially '
              'missing markets are surfaced; another site\'s lines are never substituted.',
              style: TextStyle(color: AppColors.silver, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.gold),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sync_rounded,
                    size: 16,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_countdown()} | Last successful sync ${_clock(reliability['latestDataUpdatedAt'])}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel('TODAY + NEXT THREE DAYS'),
            const SizedBox(height: 8),
            ...days.map((day) => _SlateDayRow(day: day, clock: _clock)),
            if (health.isNotEmpty) ...[
              const SizedBox(height: 18),
              const _SectionLabel('MARKET HEALTH MAP'),
              const SizedBox(height: 5),
              const Text(
                'Provider coverage by sport and category, weakest markets first. '
                'Red is a research warning, not proof that every provider offers that market.',
                style: TextStyle(
                  color: AppColors.silver,
                  fontSize: 9,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                key: const ValueKey('market-health-summary'),
                spacing: 7,
                runSpacing: 7,
                children: [
                  _HealthSummary(
                    label: 'HEALTHY',
                    count: greenCount,
                    color: const Color(0xFF55D6A3),
                  ),
                  _HealthSummary(
                    label: 'WATCH',
                    count: yellowCount,
                    color: AppColors.gold,
                  ),
                  _HealthSummary(
                    label: 'LIMITED',
                    count: redCount,
                    color: const Color(0xFFFF8A80),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                key: const ValueKey('market-health-sport-filters'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['ALL', ...sports]
                      .map((sport) {
                        final selected = sport == activeSport;
                        return Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: ChoiceChip(
                            label: Text(sport),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedSport = sport),
                            labelStyle: TextStyle(
                              color: selected ? Colors.black : Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                            selectedColor: AppColors.gold,
                            backgroundColor: AppColors.panel,
                            side: const BorderSide(
                              color: AppColors.gunmetalLight,
                            ),
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 9),
              Container(
                key: const ValueKey('market-health-map'),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  border: Border.all(color: AppColors.gunmetalLight),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: filteredHealth
                      .map(
                        (row) => _MarketHealthRow(
                          row: row,
                          showSport: activeSport == 'ALL',
                          isLast: identical(row, filteredHealth.last),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const _SectionLabel('PROVIDERS'),
            const SizedBox(height: 8),
            ...providers.map(
              (provider) {
                final age = (provider['ageMinutes'] as num?)?.toInt();
                final rawStatus = provider['status']?.toString() ?? 'UNKNOWN';
                final normalized = rawStatus.toUpperCase();
                final stale = normalized == 'STALE' ||
                    normalized == 'OFFLINE' ||
                    normalized == 'ERROR' ||
                    (age != null && age >= 15);
                return _ReliabilityRow(
                  title: provider['provider']?.toString() ?? 'UNKNOWN',
                  detail:
                      '${provider['propCount'] ?? 0} props | '
                      '${provider['eventCount'] ?? 0} events | '
                      'last successful update ${age == null ? 'unknown' : age == 0 ? 'now' : '${age}m ago'}',
                  status: stale ? 'STALE FEED' : rawStatus,
                );
              },
            ),
            ...missingToday.map(
              (provider) => _ReliabilityRow(
                title: provider,
                detail: '0 current props | Provider has no inventory for this slate',
                status: 'NO INVENTORY',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlateDayRow extends StatelessWidget {
  const _SlateDayRow({required this.day, required this.clock});
  final Map<String, dynamic> day;
  final String Function(Object?) clock;

  @override
  Widget build(BuildContext context) {
    final props = (day['propCount'] as num?)?.toInt() ?? 0;
    final coverage = (day['providerCoveragePercent'] as num?)?.toInt() ?? 0;
    final missingProviders = (day['missingProviders'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final missingMarkets =
        (day['potentialMissingMarketCount'] as num?)?.toInt() ?? 0;
    final status = props == 0
        ? 'WAITING'
        : coverage >= 75
        ? 'READY'
        : 'PARTIAL';
    final color = status == 'READY'
        ? const Color(0xFF55D6A3)
        : status == 'PARTIAL'
        ? AppColors.gold
        : AppColors.silver;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.gunmetalLight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  day['date']?.toString() ?? 'Unknown date',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$coverage% COVERAGE',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${day['eventCount'] ?? 0} games | $props props | ${day['providerCount'] ?? 0} providers | ${day['categoryCount'] ?? 0} markets',
            style: const TextStyle(color: AppColors.silver, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            'Expected lineup window: ${clock(day['expectedLineupsAtUtc'])} | Last sync: ${clock(day['lastSuccessfulSyncAtUtc'])}',
            style: const TextStyle(color: AppColors.silver, fontSize: 9),
          ),
          if (missingProviders.isNotEmpty || missingMarkets > 0) ...[
            const SizedBox(height: 5),
            Text(
              '${missingProviders.isEmpty ? '' : 'Missing providers: ${missingProviders.join(', ')}. '}'
              '${missingMarkets > 0 ? '$missingMarkets potential market gaps.' : ''}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 92),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: .65)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          '$label $count',
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

class _MarketHealthRow extends StatelessWidget {
  const _MarketHealthRow({
    required this.row,
    required this.showSport,
    required this.isLast,
  });

  final Map<String, dynamic> row;
  final bool showSport;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString().toUpperCase() ?? 'RED';
    final color = status == 'GREEN'
        ? const Color(0xFF55D6A3)
        : status == 'YELLOW'
        ? AppColors.gold
        : const Color(0xFFFF8A80);
    final coverage = (row['coveragePercent'] as num?)?.toInt() ?? 0;
    final providers = (row['providerCount'] as num?)?.toInt() ?? 0;
    final expected =
        (row['expectedProviderCount'] as num?)?.toInt() ?? providers;
    final props = (row['propCount'] as num?)?.toInt() ?? 0;
    return Semantics(
      label:
          '${row['sport']} ${row['category']}, $coverage percent provider coverage, $props props',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: AppColors.gunmetalLight),
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${showSport ? '${row['sport']}  |  ' : ''}${row['category']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$providers/$expected providers  |  $props props',
                    style: const TextStyle(
                      color: AppColors.silver,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$coverage%',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  status == 'GREEN'
                      ? 'HEALTHY'
                      : status == 'YELLOW'
                      ? 'WATCH'
                      : 'LIMITED',
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
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
    final failed = normalized.contains('STALE') ||
        normalized == 'OFFLINE' ||
        normalized == 'ERROR';
    final color = failed
        ? const Color(0xFFFF8A80)
        : healthy
        ? const Color(0xFF55D6A3)
        : AppColors.gold;
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
