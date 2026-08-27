import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class OwnerCommandCenterOverview extends StatelessWidget {
  const OwnerCommandCenterOverview({super.key, required this.data});

  final Map<String, dynamic> data;

  Color _color(String status) => switch (status.toUpperCase()) {
    'HEALTHY' => const Color(0xFF65E6B4),
    'WARNING' || 'PARTIAL' || 'DELAYED' => AppColors.gold,
    'PAUSED' || 'NOT_ENTITLED' => const Color(0xFFB8C3CC),
    _ => const Color(0xFFFF7474),
  };

  String _value(Map metric) {
    final raw = metric['value'];
    if (raw == null) {
      final status = '${metric['status'] ?? ''}'.toUpperCase();
      return status == 'UNAVAILABLE' ? 'NOT CONNECTED' : 'PENDING';
    }
    if (metric['key'] == 'averageConfidence' && raw is num) {
      return '${(raw.toDouble() * 100).toStringAsFixed(1)}%';
    }
    if (metric['key'] == 'mrr' && raw is num) {
      return '\$${raw.toStringAsFixed(2)}';
    }
    return '$raw';
  }

  String _time(Object? raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '');
    if (value == null) return '--';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '${local.month}/${local.day} $hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final metrics = (data['overview'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final services = (data['services'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final recalculations = (data['piRecalculationDetails'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final learning = (data['piRecalculationLearning'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    if (metrics.isEmpty && services.isEmpty) {
      return _empty();
    }
    return KeyedSubtree(
      key: const ValueKey('owner-command-center-overview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 4
                  : constraints.maxWidth >= 700
                  ? 3
                  : constraints.maxWidth >= 300
                  ? 2
                  : 1;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - ((columns - 1) * 10)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: metrics
                    .map(
                      (metric) =>
                          SizedBox(width: width, child: _metric(metric)),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 18),
          if (recalculations.isNotEmpty) ...[
            _recalculationDrilldown(recalculations),
            const SizedBox(height: 18),
          ],
          if (learning.isNotEmpty) ...[
            _recalculationLearning(learning),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              const Icon(
                Icons.monitor_heart_outlined,
                color: AppColors.gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'LIVE SYSTEM MONITOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
              Text(
                'Updated ${_time(data['generatedAt'])}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 760
                ? _serviceTable(services)
                : Column(
                    children: services
                        .map(
                          (service) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _serviceCard(service),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _recalculationDrilldown(List<Map> rows) => ExpansionTile(
    key: const ValueKey('owner-pi-recalculation-drilldown'),
    tilePadding: EdgeInsets.zero,
    title: const Text('PI RECALCULATION DRILL-DOWN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
    subtitle: Text('${rows.length} active improved or weakened props', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
    children: rows.map((row) {
      final weakened = row['status'] == 'WEAKENED';
      final color = weakened ? const Color(0xFFFF8A65) : const Color(0xFF65E6B4);
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('${row['player']} • ${row['side']} ${row['line']} ${row['market']}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        subtitle: Text('${row['sport']} • projection ${row['entryProjection']} → ${row['currentProjection']} • confidence ${row['entryConfidence']} → ${row['currentConfidence']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
        trailing: Text('${row['status']}', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
      );
    }).toList(growable: false),
  );

  Widget _recalculationLearning(List<Map> rows) => ExpansionTile(
    key: const ValueKey('owner-pi-recalculation-learning'),
    tilePadding: EdgeInsets.zero,
    title: const Text('PI RECALCULATION LEARNING', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
    subtitle: const Text('Verified impact by sport and market', style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
    children: rows.map((row) {
      final promoted = row['promoted'] == true;
      final rolledBack = row['reason'] == 'recent-performance-rollback';
      final status = promoted ? 'ACTIVE +${row['rankingInfluence']}' : rolledBack ? 'ROLLED BACK' : 'COLLECTING';
      final statusColor = promoted ? const Color(0xFF65E6B4) : rolledBack ? const Color(0xFFFF7474) : AppColors.gold;
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text('${row['sport']} • ${row['market']}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        subtitle: Text('Accuracy ${row['accuracy']}% • MAE ${row['entryMae']} → ${row['recalculatedMae']} • improvement ${row['maeImprovement']}% • recent ${row['recentAccuracy']}%', style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(status, style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.w900)),
            Text('N=${row['sampleSize']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w800)),
          ],
        ),
      );
    }).toList(growable: false),
  );

  Widget _empty() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gold.withValues(alpha: .3)),
    ),
    child: const Text(
      'The Owner Command Center is warming up. Refresh after the next API check.',
      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
    ),
  );

  Widget _metric(Map metric) {
    final status = '${metric['status'] ?? 'unavailable'}'.toUpperCase();
    final color = _color(status);
    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${metric['label'] ?? '--'}'.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _value(metric),
            style: TextStyle(
              color: color,
              fontSize: status == 'UNAVAILABLE' ? 12 : 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${metric['detail'] ?? ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceTable(List<Map> services) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gold.withValues(alpha: .2)),
    ),
    child: DataTable(
      headingRowHeight: 40,
      dataRowMinHeight: 46,
      dataRowMaxHeight: 58,
      columnSpacing: 18,
      horizontalMargin: 14,
      columns: const [
        DataColumn(label: Text('SERVICE')),
        DataColumn(label: Text('STATUS')),
        DataColumn(label: Text('LAST UPDATE')),
        DataColumn(label: Text('LATENCY')),
        DataColumn(label: Text('RECORDS')),
      ],
      rows: services
          .map((service) {
            final status = '${service['status'] ?? 'UNAVAILABLE'}'
                .toUpperCase();
            final color = _color(status);
            return DataRow(
              cells: [
                DataCell(Text('${service['service'] ?? '--'}')),
                DataCell(
                  Text(
                    status.replaceAll('_', ' '),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                DataCell(Text(_time(service['lastUpdate']))),
                DataCell(
                  Text(
                    service['latencyMs'] == null
                        ? '--'
                        : '${service['latencyMs']} ms',
                  ),
                ),
                DataCell(Text('${service['records'] ?? '--'}')),
              ],
            );
          })
          .toList(growable: false),
    ),
  );

  Widget _serviceCard(Map service) {
    final status = '${service['status'] ?? 'UNAVAILABLE'}'.toUpperCase();
    final color = _color(status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${service['service'] ?? '--'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                status.replaceAll('_', ' '),
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
            'Updated ${_time(service['lastUpdate'])}  |  ${service['latencyMs'] == null ? 'latency --' : '${service['latencyMs']} ms'}  |  ${service['records'] ?? '--'} records',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
          if ('${service['detail'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '${service['detail']}',
              style: TextStyle(color: color, fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }
}

class OwnerPropInventoryPanel extends StatefulWidget {
  const OwnerPropInventoryPanel({
    super.key,
    required this.data,
    this.onPropControl,
    this.onAlertAcknowledgement,
  });

  final Map<String, dynamic> data;
  final Future<void> Function(Map item, bool quarantined)? onPropControl;
  final Future<void> Function(Map alert, bool acknowledged)?
  onAlertAcknowledgement;

  @override
  State<OwnerPropInventoryPanel> createState() =>
      _OwnerPropInventoryPanelState();
}

class _OwnerPropInventoryPanelState extends State<OwnerPropInventoryPanel> {
  String _search = '';
  String _sport = 'ALL';
  String _provider = 'ALL';
  String _quality = 'ALL';

  List<Map> get _items => (widget.data['items'] as List? ?? const [])
      .whereType<Map>()
      .toList(growable: false);

  List<String> _facet(String key) {
    final facets = widget.data['facets'] as Map? ?? const {};
    return (facets[key] as List? ?? const [])
        .map((value) => '$value')
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
  }

  String _valid(String selected, List<String> options) =>
      selected == 'ALL' || options.contains(selected) ? selected : 'ALL';

  List<Map> get _filtered {
    final query = _search.trim().toLowerCase();
    return _items
        .where((item) {
          if (_valid(_sport, _facet('sports')) != 'ALL' &&
              '${item['sport']}' != _sport) {
            return false;
          }
          if (_valid(_provider, _facet('providers')) != 'ALL' &&
              '${item['provider']}' != _provider) {
            return false;
          }
          final warnings = (item['warnings'] as List? ?? const [])
              .map((value) => '$value')
              .toList(growable: false);
          if (_quality == 'HEALTHY' && warnings.isNotEmpty) return false;
          if (_quality == 'FLAGGED' && warnings.isEmpty) return false;
          if (_quality != 'ALL' &&
              _quality != 'HEALTHY' &&
              _quality != 'FLAGGED' &&
              !warnings.contains(_quality)) {
            return false;
          }
          if (query.isEmpty) return true;
          return [
            item['player'],
            item['matchup'],
            item['market'],
            item['provider'],
            item['sport'],
          ].any((value) => '$value'.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  String _label(Object? value) => '${value ?? ''}'
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  String _time(Object? raw) {
    final parsed = DateTime.tryParse('${raw ?? ''}');
    if (parsed == null) return 'Unknown';
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '${local.month}/${local.day} $hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _confidence(Object? raw) {
    if (raw is! num) return '--';
    final value = raw > 1 ? raw.toDouble() : raw.toDouble() * 100;
    return '${value.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const _InventoryEmpty();
    }
    final alerts = (widget.data['alerts'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final providers = (widget.data['providers'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final filtered = _filtered.take(60).toList(growable: false);
    return KeyedSubtree(
      key: const ValueKey('owner-prop-inventory'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summary(),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: alerts
                  .map((alert) => _alertChip(alert))
                  .toList(growable: false),
            ),
          ],
          if ((widget.data['actionHistory'] as List? ?? const [])
              .isNotEmpty) ...[
            const SizedBox(height: 10),
            _actionHistory(),
          ],
          const SizedBox(height: 12),
          _filters(),
          const SizedBox(height: 12),
          Text(
            '${_filtered.length} MATCHING PROPS${widget.data['truncated'] == true ? ' | FIRST ${widget.data['returned']} LOADED' : ''}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const _InventoryEmpty(
              message: 'No props match these owner filters.',
            )
          else
            ...filtered.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _propCard(item),
              ),
            ),
          if (providers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'PROVIDER DRILLDOWNS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 8),
            ...providers.map(_providerCard),
          ],
        ],
      ),
    );
  }

  Widget _summary() => LayoutBuilder(
    builder: (context, constraints) {
      final values = [
        ('TOTAL', widget.data['total'] ?? 0, AppColors.gold),
        ('HEALTHY', widget.data['healthy'] ?? 0, const Color(0xFF65E6B4)),
        ('FLAGGED', widget.data['flagged'] ?? 0, const Color(0xFFFFA970)),
        (
          'PROVIDERS',
          (widget.data['providers'] as List?)?.length ?? 0,
          Colors.white,
        ),
        ('HELD', widget.data['quarantined'] ?? 0, const Color(0xFFFF7474)),
      ];
      final width = constraints.maxWidth >= 620
          ? (constraints.maxWidth - 30) / 4
          : (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: values
            .map(
              (value) => Container(
                width: width,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1823),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: value.$3.withValues(alpha: .28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.$1,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${value.$2}',
                      style: TextStyle(
                        color: value.$3,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      );
    },
  );

  Widget _qualityChip(String label, num count, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .45)),
    ),
    child: Text(
      '${_label(label).toUpperCase()} $count',
      style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900),
    ),
  );

  Widget _alertChip(Map alert) {
    final acknowledged = alert['acknowledged'] == true;
    final color = acknowledged
        ? const Color(0xFF65E6B4)
        : '${alert['severity']}' == 'RED'
        ? const Color(0xFFFF7474)
        : AppColors.gold;
    return ActionChip(
      key: ValueKey('owner-alert-${alert['id']}'),
      backgroundColor: color.withValues(alpha: .08),
      side: BorderSide(color: color.withValues(alpha: .45)),
      avatar: Icon(
        acknowledged ? Icons.check_circle : Icons.warning_amber,
        size: 14,
        color: color,
      ),
      label: Text(
        '${_label(alert['key']).toUpperCase()} ${alert['count']} | ${acknowledged ? 'ACKNOWLEDGED' : 'ACKNOWLEDGE'}',
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
      onPressed: widget.onAlertAcknowledgement == null
          ? null
          : () async => widget.onAlertAcknowledgement!(alert, !acknowledged),
    );
  }

  Widget _actionHistory() {
    final history = (widget.data['actionHistory'] as List? ?? const [])
        .whereType<Map>()
        .take(8)
        .toList(growable: false);
    return ExpansionTile(
      key: const ValueKey('owner-action-history'),
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'OWNER ACTION HISTORY',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        '${history.length} recent reversible actions',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
      ),
      children: history
          .map(
            (entry) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.history,
                size: 16,
                color: AppColors.gold,
              ),
              title: Text(
                _label(entry['action']),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                '${entry['reason']} | ${_time(entry['createdAt'])}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _filters() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gold.withValues(alpha: .22)),
    ),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            key: const ValueKey('owner-inventory-search'),
            onChanged: (value) => setState(() => _search = value),
            style: const TextStyle(color: Colors.white, fontSize: 11),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 17),
              hintText: 'Player, game, market, provider',
            ),
          ),
        ),
        _dropdown(
          'SPORT',
          _valid(_sport, _facet('sports')),
          _facet('sports'),
          (value) => setState(() => _sport = value),
        ),
        _dropdown(
          'PROVIDER',
          _valid(_provider, _facet('providers')),
          _facet('providers'),
          (value) => setState(() => _provider = value),
        ),
        _dropdown('QUALITY', _quality, [
          'HEALTHY',
          'FLAGGED',
          ..._facet('quality'),
        ], (value) => setState(() => _quality = value)),
      ],
    ),
  );

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) => Container(
    width: 150,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.gold.withValues(alpha: .32)),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: const Color(0xFF0C1823),
        style: const TextStyle(color: Colors.white, fontSize: 10),
        items: <String>{'ALL', ...options}
            .map(
              (option) => DropdownMenuItem(
                value: option,
                child: Text(option == 'ALL' ? 'ALL $label' : _label(option)),
              ),
            )
            .toList(growable: false),
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      ),
    ),
  );

  Widget _propCard(Map item) {
    final warnings = (item['warnings'] as List? ?? const [])
        .map((value) => '$value')
        .toList(growable: false);
    final color = warnings.isEmpty ? const Color(0xFF65E6B4) : AppColors.gold;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['player']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item['sport']} | ${item['matchup']}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item['prediction'] ?? 'NO PICK'} ${item['line'] ?? '--'}',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _detail('MARKET', item['market']),
              _detail('CONF', _confidence(item['confidence'])),
              _detail('PROVIDER', item['provider']),
              _detail('MOVE', item['lineMovement'] ?? '--'),
              _detail('UPDATED', _time(item['lastUpdate'])),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: ValueKey('owner-prop-control-${item['id']}'),
              onPressed: widget.onPropControl == null
                  ? null
                  : () async => widget.onPropControl!(
                      item,
                      item['quarantined'] != true,
                    ),
              icon: Icon(
                item['quarantined'] == true
                    ? Icons.restore
                    : Icons.visibility_off,
                size: 14,
              ),
              label: Text(
                item['quarantined'] == true ? 'RESTORE' : 'QUARANTINE',
              ),
            ),
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: warnings
                  .map((warning) => _qualityChip(warning, 1, AppColors.gold))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, Object? value) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label ',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        TextSpan(
          text: '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _providerCard(Map provider) {
    final status = '${provider['status'] ?? 'UNAVAILABLE'}';
    final color = status == 'HEALTHY'
        ? const Color(0xFF65E6B4)
        : AppColors.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF0C1823),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: .25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: ValueKey('owner-provider-${provider['provider']}'),
          iconColor: color,
          collapsedIconColor: AppColors.textMuted,
          title: Text(
            '${provider['provider']}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            '${provider['props']} props | ${(provider['sports'] as List? ?? const []).join(', ')}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
          trailing: Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 7,
              children: [
                _detail('LAST UPDATE', _time(provider['lastUpdate'])),
                _detail('STALE', provider['stale']),
                _detail('SUSPICIOUS', provider['suspicious']),
                _detail('NO PROJECTION', provider['missingProjection']),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryEmpty extends StatelessWidget {
  const _InventoryEmpty({this.message = 'No prop inventory is available yet.'});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gold.withValues(alpha: .25)),
    ),
    child: Text(
      message,
      style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
    ),
  );
}
