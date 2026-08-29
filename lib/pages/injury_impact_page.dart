import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../services/injury_alert_service.dart';
import '../theme/app_colors.dart';
import '../widgets/injury_impact_alert.dart';

class InjuryImpactPage extends StatefulWidget {
  const InjuryImpactPage({
    super.key,
    required this.props,
    this.alerts = const [],
  });

  final List<PropData> props;
  final List<Map<String, dynamic>> alerts;

  @override
  State<InjuryImpactPage> createState() => _InjuryImpactPageState();
}

class _InjuryImpactPageState extends State<InjuryImpactPage> {
  String _sport = 'ALL';
  String _severity = 'ALL';
  InjuryAlertPreferences _preferences = const InjuryAlertPreferences();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await InjuryAlertPreferences.load();
    if (mounted) setState(() => _preferences = preferences);
  }

  Future<void> _setPreferences(InjuryAlertPreferences preferences) async {
    setState(() => _preferences = preferences);
    await preferences.save();
  }

  @override
  Widget build(BuildContext context) {
    final impacts = buildInjuryImpactItems(widget.props);
    final sports =
        impacts.map((item) => item.prop.sport.toUpperCase()).toSet().toList()
          ..sort();
    final activeSport = _sport == 'ALL' || sports.contains(_sport)
        ? _sport
        : 'ALL';
    final filtered = impacts
        .where((item) {
          final sportMatch =
              activeSport == 'ALL' ||
              item.prop.sport.toUpperCase() == activeSport;
          final severityMatch = _severity == 'ALL' || item.level == _severity;
          return sportMatch && severityMatch;
        })
        .toList(growable: false);

    return ListView(
      key: const ValueKey('injury-impact-page'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        const _ImpactHeader(),
        const SizedBox(height: 10),
        _LiveAlertControls(
          preferences: _preferences,
          onChanged: _setPreferences,
        ),
        if (widget.alerts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _RecentInjuryAlerts(alerts: widget.alerts),
        ],
        const SizedBox(height: 14),
        _ImpactSummary(impacts: impacts),
        const SizedBox(height: 12),
        _FilterRail(
          sports: sports,
          selectedSport: activeSport,
          selectedSeverity: _severity,
          onSport: (value) => setState(() => _sport = value),
          onSeverity: (value) => setState(() => _severity = value),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const _EmptyImpactState()
        else
          ...filtered.map((item) => _ImpactCard(item: item)),
      ],
    );
  }
}

class _LiveAlertControls extends StatelessWidget {
  const _LiveAlertControls({
    required this.preferences,
    required this.onChanged,
  });

  final InjuryAlertPreferences preferences;
  final ValueChanged<InjuryAlertPreferences> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('injury-alert-controls'),
    color: AppColors.panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: AppColors.gunmetalLight),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('injury-alert-enabled-control'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'LIVE IN-APP ALERTS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: const Text(
              'Notify when verified availability or a material role factor changes.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5),
            ),
            value: preferences.enabled,
            onChanged: (value) =>
                onChanged(preferences.copyWith(enabled: value)),
          ),
          if (preferences.enabled)
            SwitchListTile.adaptive(
              key: const ValueKey('injury-critical-only-control'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'URGENT ONLY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: const Text(
                'Interrupt only for critical and high-severity changes.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 8.5),
              ),
              value: preferences.criticalOnly,
              onChanged: (value) =>
                  onChanged(preferences.copyWith(criticalOnly: value)),
            ),
        ],
      ),
    ),
  );
}

class _RecentInjuryAlerts extends StatelessWidget {
  const _RecentInjuryAlerts({required this.alerts});
  final List<Map<String, dynamic>> alerts;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('recent-injury-alerts'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.gold.withValues(alpha: .55)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECENT VERIFIED CHANGES',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        for (final alert in alerts.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  alert['level']?.toString() == 'CLEARED'
                      ? Icons.check_circle_outline_rounded
                      : Icons.notification_important_outlined,
                  size: 14,
                  color: alert['level']?.toString() == 'CLEARED'
                      ? AppColors.success
                      : AppColors.gold,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${alert['title'] ?? 'Injury impact changed'} — '
                    '${alert['message'] ?? ''}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      height: 1.3,
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

class InjuryImpactItem {
  const InjuryImpactItem({
    required this.prop,
    required this.sites,
    required this.summary,
  });

  final PropData prop;
  final Set<String> sites;
  final InjuryImpactSummary summary;

  String get level => summary.level;
}

List<InjuryImpactItem> buildInjuryImpactItems(List<PropData> props) {
  const rank = {'CRITICAL': 0, 'HIGH': 1, 'WATCH': 2};
  final grouped = <String, List<PropData>>{};
  for (final prop in props) {
    final summary = buildInjuryImpactSummary(prop);
    if (!summary.isPresent) continue;
    final playerKey = prop.canonicalPlayerId.trim().isNotEmpty
        ? prop.canonicalPlayerId.trim().toLowerCase()
        : prop.player.trim().toLowerCase();
    final marketKey = prop.marketKey.trim().isNotEmpty
        ? prop.marketKey.trim().toLowerCase()
        : prop.displayMarket.trim().toLowerCase();
    final eventKey = prop.eventId.trim().isNotEmpty
        ? prop.eventId
        : prop.matchup;
    grouped.putIfAbsent('$eventKey|$playerKey|$marketKey', () => []).add(prop);
  }
  final result = grouped.values.map((group) {
    group.sort((a, b) {
      final severity = (rank[buildInjuryImpactSummary(a).level] ?? 3).compareTo(
        rank[buildInjuryImpactSummary(b).level] ?? 3,
      );
      if (severity != 0) return severity;
      final trust = b.piTrustScore.compareTo(a.piTrustScore);
      if (trust != 0) return trust;
      return b.lastUpdatedUtc.compareTo(a.lastUpdatedUtc);
    });
    final representative = group.first;
    return InjuryImpactItem(
      prop: representative,
      sites: group
          .map((prop) => prop.sportsbook.toUpperCase())
          .where((site) => site.isNotEmpty)
          .toSet(),
      summary: buildInjuryImpactSummary(representative),
    );
  }).toList();
  result.sort((a, b) {
    final severity = (rank[a.level] ?? 3).compareTo(rank[b.level] ?? 3);
    if (severity != 0) return severity;
    return b.prop.piTrustScore.compareTo(a.prop.piTrustScore);
  });
  return result;
}

class _ImpactHeader extends StatelessWidget {
  const _ImpactHeader();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gold.withValues(alpha: .65)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.health_and_safety_outlined, color: AppColors.gold, size: 22),
        SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INJURY IMPACT CENTER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Availability blocks and verified role, usage, opportunity, or with/without changes across the live board.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'SPORT COVERAGE: Filters appear only for sports with current injury-affected props. An absent sport means there is no matched live injury impact right now, not that the sport is excluded.',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 9,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ImpactSummary extends StatelessWidget {
  const _ImpactSummary({required this.impacts});
  final List<InjuryImpactItem> impacts;

  @override
  Widget build(BuildContext context) {
    final blocked = impacts.where((item) => item.level == 'CRITICAL').length;
    final high = impacts.where((item) => item.level == 'HIGH').length;
    final watch = impacts.where((item) => item.level == 'WATCH').length;
    return Wrap(
      key: const ValueKey('injury-impact-summary'),
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryTile(
          label: 'BLOCKED',
          value: blocked,
          color: const Color(0xFFFF806B),
        ),
        _SummaryTile(
          label: 'HIGH',
          value: high,
          color: const Color(0xFFFFB36B),
        ),
        _SummaryTile(label: 'WATCH', value: watch, color: AppColors.gold),
        _SummaryTile(
          label: 'AFFECTED',
          value: impacts.length,
          color: const Color(0xFF75CFFF),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 94),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: .55)),
    ),
    child: Text(
      '$label  $value',
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}

class _FilterRail extends StatelessWidget {
  const _FilterRail({
    required this.sports,
    required this.selectedSport,
    required this.selectedSeverity,
    required this.onSport,
    required this.onSeverity,
  });
  final List<String> sports;
  final String selectedSport;
  final String selectedSeverity;
  final ValueChanged<String> onSport;
  final ValueChanged<String> onSeverity;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['ALL', ...sports]
              .map(
                (sport) => _FilterChip(
                  label: sport,
                  selected: sport == selectedSport,
                  onTap: () => onSport(sport),
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 7),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: const ['ALL', 'CRITICAL', 'HIGH', 'WATCH']
              .map(
                (level) => _FilterChip(
                  label: level,
                  selected: level == selectedSeverity,
                  onTap: () => onSeverity(level),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ChoiceChip(
      key: ValueKey('injury-filter-$label'),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.gold,
      backgroundColor: AppColors.panel,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? Colors.black : Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w900,
      ),
      side: const BorderSide(color: AppColors.gunmetalLight),
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({required this.item});
  final InjuryImpactItem item;

  @override
  Widget build(BuildContext context) {
    final prop = item.prop;
    final color = item.level == 'CRITICAL'
        ? const Color(0xFFFF806B)
        : item.level == 'HIGH'
        ? const Color(0xFFFFB36B)
        : AppColors.gold;
    final updated = DateTime.tryParse(prop.lastUpdatedUtc)?.toLocal();
    final freshness = updated == null
        ? 'FRESHNESS UNKNOWN'
        : 'UPDATED ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}';
    return Container(
      key: ValueKey('injury-impact-${prop.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prop.player,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                item.level,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${prop.sport.toUpperCase()}  |  ${prop.matchup}  |  ${prop.displayMarket.isEmpty ? prop.market : prop.displayMarket}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final detail in item.summary.details)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $detail',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  height: 1.3,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaChip(
                '${item.sites.length} SITE${item.sites.length == 1 ? '' : 'S'}',
              ),
              _MetaChip('TRUST ${prop.piTrustScore}'),
              _MetaChip(freshness),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'PI reports only verified status and model factors. It does not name or estimate an absent teammate when that identity is missing from the feed.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 8,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.gunmetalLight),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 8,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _EmptyImpactState extends StatelessWidget {
  const _EmptyImpactState();
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('injury-impact-empty'),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gunmetalLight),
    ),
    child: const Column(
      children: [
        Icon(Icons.verified_user_outlined, color: Color(0xFF55D6A3), size: 28),
        SizedBox(height: 9),
        Text(
          'NO VERIFIED IMPACTS MATCH',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 5),
        Text(
          'No live props currently carry an availability block or material role, usage, opportunity, or with/without change for these filters.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            height: 1.35,
          ),
        ),
      ],
    ),
  );
}
