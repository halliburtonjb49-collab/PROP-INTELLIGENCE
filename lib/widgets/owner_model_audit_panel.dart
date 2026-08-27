import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class OwnerModelAuditPanel extends StatefulWidget {
  const OwnerModelAuditPanel({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<OwnerModelAuditPanel> createState() => _OwnerModelAuditPanelState();
}

class _OwnerModelAuditPanelState extends State<OwnerModelAuditPanel> {
  String _sport = 'ALL';
  String _market = 'ALL';
  String _side = 'ALL';
  String _confidence = 'ALL';
  String _model = 'ALL';
  String _search = '';

  Map get _dimensions => widget.data['dimensions'] as Map? ?? const {};

  List<String> _options(String key) => (_dimensions[key] as List? ?? const [])
      .map((value) => '$value')
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  String _valid(String value, List<String> options) =>
      value == 'ALL' || options.contains(value) ? value : 'ALL';

  List<Map> get _predictions {
    final query = _search.trim().toLowerCase();
    return (widget.data['predictions'] as List? ?? const [])
        .whereType<Map>()
        .where((row) {
          if (_valid(_sport, _options('sports')) != 'ALL' &&
              '${row['sport']}' != _sport) {
            return false;
          }
          if (_valid(_market, _options('markets')) != 'ALL' &&
              '${row['market']}' != _market) {
            return false;
          }
          if (_valid(_side, _options('sides')) != 'ALL' &&
              '${row['side']}' != _side) {
            return false;
          }
          if (_valid(_model, _options('modelVersions')) != 'ALL' &&
              '${row['modelVersion']}' != _model) {
            return false;
          }
          if (_confidence != 'ALL' &&
              '${row['confidenceTier']}' != _confidence) {
            return false;
          }
          if (query.isEmpty) return true;
          return [
            row['player'],
            row['sport'],
            row['market'],
            row['provider'],
            row['modelVersion'],
          ].any((value) => '$value'.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  String _percent(Object? raw, {int decimals = 1}) {
    if (raw is! num) return '--';
    return '${(raw.toDouble() * 100).toStringAsFixed(decimals)}%';
  }

  String _number(Object? raw, {int decimals = 2}) {
    if (raw is! num) return '--';
    return raw.toDouble().toStringAsFixed(decimals);
  }

  String _time(Object? raw) {
    final value = DateTime.tryParse('${raw ?? ''}');
    if (value == null) return '--';
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '${local.month}/${local.day}/${local.year} $hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data['available'] != true) {
      return _empty(
        widget.data['reason']?.toString() ??
            'The verified prediction ledger is unavailable.',
      );
    }
    final summary = widget.data['summary'] as Map? ?? const {};
    final calibration = (widget.data['calibration'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final sidePerformance =
        (widget.data['sidePerformance'] as List? ?? const [])
            .whereType<Map>()
            .toList(growable: false);
    return KeyedSubtree(
      key: const ValueKey('owner-model-audit'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summary(summary),
          const SizedBox(height: 14),
          _learningScorecard(widget.data['learning'] as Map? ?? const {}),
          const SizedBox(height: 12),
          _filters(),
          if (calibration.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _AuditHeading('CONFIDENCE CALIBRATION'),
            const SizedBox(height: 8),
            ...calibration.map(_calibrationRow),
          ],
          if (sidePerformance.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _AuditHeading('OVER / UNDER PERFORMANCE'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sidePerformance.map(_sideCard).toList(growable: false),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: _AuditHeading('VERIFIED PREDICTION LEDGER'),
              ),
              Text(
                '${_predictions.length} MATCHES',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_predictions.isEmpty)
            _empty('No verified predictions match these audit filters.')
          else
            ..._predictions
                .take(100)
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _predictionCard(row),
                  ),
                ),
          if (widget.data['predictionListTruncated'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Showing the newest ${widget.data['returned'] ?? 0} verified predictions. Summary metrics use ${widget.data['auditedRows'] ?? 0} audited rows.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
              ),
            ),
          if (widget.data['truncated'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'The audit response reached its safe row limit. Narrow the global time window for a complete view.',
                style: TextStyle(color: AppColors.gold, fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(Map summary) => LayoutBuilder(
    builder: (context, constraints) {
      final metrics = [
        ('GRADED', '${summary['graded'] ?? 0}', AppColors.gold),
        ('ACCURACY', _percent(summary['accuracy']), const Color(0xFF65E6B4)),
        ('PUSHES', '${summary['pushes'] ?? 0}', Colors.white),
        (
          'BRIER',
          _number(summary['brierScore'], decimals: 3),
          const Color(0xFF73BFFF),
        ),
        (
          'ROI',
          _percent(summary['simulatedRoi']),
          summary['simulatedRoi'] is num &&
                  (summary['simulatedRoi'] as num) >= 0
              ? const Color(0xFF65E6B4)
              : const Color(0xFFFFA970),
        ),
        (
          'ODDS SAMPLE',
          '${summary['oddsSampleSize'] ?? 0}',
          AppColors.textMuted,
        ),
      ];
      final columns = constraints.maxWidth >= 900
          ? 6
          : constraints.maxWidth >= 560
          ? 3
          : 2;
      final width = (constraints.maxWidth - ((columns - 1) * 8)) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: metrics
            .map(
              (metric) => Container(
                width: width,
                constraints: const BoxConstraints(minHeight: 82),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1823),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: metric.$3.withValues(alpha: .25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.$1,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      metric.$2,
                      style: TextStyle(
                        color: metric.$3,
                        fontSize: 19,
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

  Widget _learningScorecard(Map learning) {
    if (learning['available'] != true) {
      return _empty(
        learning['reason']?.toString() ??
            'PI learning evidence is still accumulating.',
      );
    }
    final summary = learning['summary'] as Map? ?? const {};
    final clv = learning['closingLineQuality'] as Map? ?? const {};
    final findings = (learning['findings'] as List? ?? const [])
        .whereType<Map>()
        .take(8)
        .toList(growable: false);
    final metrics = [
      ('SETTLED', '${learning['settledPredictions'] ?? 0}', AppColors.gold),
      ('PROMOTED', '${summary['promoted'] ?? 0}', const Color(0xFF65E6B4)),
      ('DEVELOPING', '${summary['developing'] ?? 0}', const Color(0xFF73BFFF)),
      ('REJECTED', '${summary['rejected'] ?? 0}', const Color(0xFFFFA970)),
      (
        'CALIBRATION',
        '${summary['calibrationSegmentsPromoted'] ?? 0}',
        const Color(0xFF65E6B4),
      ),
      (
        'BEAT CLOSE',
        _percent(clv['beatCloseRate']),
        clv['beatCloseRate'] is num && (clv['beatCloseRate'] as num) >= .5
            ? const Color(0xFF65E6B4)
            : AppColors.gold,
      ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF08141F),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.gold.withValues(alpha: .38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_rounded, color: AppColors.gold),
              const SizedBox(width: 8),
              const Expanded(child: _AuditHeading('PI LEARNING SCORECARD')),
              Text(
                '${learning['modelVersion'] ?? '--'}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Verified outcomes train guarded market patterns. Only patterns that clear sample, uncertainty, lift, and out-of-sample checks can affect future PI rankings.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 6 : 3;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 7)) / columns;
              return Wrap(
                spacing: 7,
                runSpacing: 7,
                children: metrics
                    .map(
                      (metric) => Container(
                        width: width,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C1823),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: metric.$3.withValues(alpha: .25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metric.$1,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 7,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              metric.$2,
                              style: TextStyle(
                                color: metric.$3,
                                fontSize: 15,
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
          ),
          const SizedBox(height: 9),
          Text(
            'CLV COVERAGE ${clv['measured'] ?? 0} PICKS | ${clv['beatClose'] ?? 0} BEAT THE CLOSE',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (findings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'LEARNED PATTERNS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            ...findings.map(_learningFinding),
          ],
        ],
      ),
    );
  }

  Widget _learningFinding(Map finding) {
    final status = '${finding['status'] ?? 'DEVELOPING'}';
    final color = status == 'PROMOTED'
        ? const Color(0xFF65E6B4)
        : status == 'REJECTED'
        ? const Color(0xFFFFA970)
        : const Color(0xFF73BFFF);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 7,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${finding['sport']} | ${finding['market']} | ${finding['dimension']}: ${finding['label']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${finding['explanation'] ?? ''}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 8,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      spacing: 9,
      runSpacing: 9,
      children: [
        SizedBox(
          width: 230,
          child: TextField(
            key: const ValueKey('owner-model-audit-search'),
            onChanged: (value) => setState(() => _search = value),
            style: const TextStyle(color: Colors.white, fontSize: 10),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 17),
              hintText: 'Player, provider, model',
            ),
          ),
        ),
        _dropdown(
          'SPORT',
          _valid(_sport, _options('sports')),
          _options('sports'),
          (value) => setState(() => _sport = value),
        ),
        _dropdown(
          'MARKET',
          _valid(_market, _options('markets')),
          _options('markets'),
          (value) => setState(() => _market = value),
        ),
        _dropdown(
          'SIDE',
          _valid(_side, _options('sides')),
          _options('sides'),
          (value) => setState(() => _side = value),
        ),
        _dropdown('CONFIDENCE', _confidence, const [
          '80-100%',
          '70-79%',
          '60-69%',
          'BELOW 60%',
          'UNKNOWN',
        ], (value) => setState(() => _confidence = value)),
        _dropdown(
          'MODEL',
          _valid(_model, _options('modelVersions')),
          _options('modelVersions'),
          (value) => setState(() => _model = value),
        ),
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
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.gold.withValues(alpha: .3)),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: const Color(0xFF0C1823),
        style: const TextStyle(color: Colors.white, fontSize: 9),
        items: <String>{'ALL', ...options}
            .map(
              (option) => DropdownMenuItem(
                value: option,
                child: Text(option == 'ALL' ? 'ALL $label' : option),
              ),
            )
            .toList(growable: false),
        onChanged: (selected) {
          if (selected != null) onChanged(selected);
        },
      ),
    ),
  );

  Widget _calibrationRow(Map row) {
    final confidence = (row['averageConfidence'] as num?)?.toDouble() ?? 0;
    final accuracy = (row['accuracy'] as num?)?.toDouble() ?? 0;
    final gap = (row['calibrationGap'] as num?)?.toDouble();
    final healthy = gap != null && gap.abs() <= .05;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: (healthy ? const Color(0xFF65E6B4) : AppColors.gold)
              .withValues(alpha: .24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${row['tier']} | ${row['sampleSize']} PICKS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'GAP ${gap == null ? '--' : '${(gap * 100).toStringAsFixed(1)} PTS'}',
                style: TextStyle(
                  color: healthy ? const Color(0xFF65E6B4) : AppColors.gold,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _bar('CONFIDENCE', confidence, AppColors.gold),
          const SizedBox(height: 5),
          _bar('ACTUAL', accuracy, const Color(0xFF65E6B4)),
        ],
      ),
    );
  }

  Widget _bar(String label, double value, Color color) => Row(
    children: [
      SizedBox(
        width: 72,
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 7,
            backgroundColor: Colors.white10,
            color: color,
          ),
        ),
      ),
      const SizedBox(width: 7),
      SizedBox(
        width: 42,
        child: Text(
          '${(value * 100).toStringAsFixed(1)}%',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );

  Widget _sideCard(Map row) => Container(
    width: 200,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppColors.gold.withValues(alpha: .22)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${row['side']}',
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${row['hits']} wins | ${row['sampleSize']} graded | ${row['pushes']} pushes',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 8),
        ),
        const SizedBox(height: 5),
        Text(
          _percent(row['accuracy']),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _predictionCard(Map row) {
    final push = row['push'] == true;
    final correct = row['correct'] == true;
    final color = push
        ? AppColors.textMuted
        : correct
        ? const Color(0xFF65E6B4)
        : const Color(0xFFFF7474);
    final result = push
        ? 'PUSH'
        : correct
        ? 'CORRECT'
        : 'INCORRECT';
    return Material(
      color: const Color(0xFF0C1823),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: .26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('owner-prediction-${row['id']}'),
        iconColor: color,
        collapsedIconColor: AppColors.textMuted,
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${row['player']} | ${row['side']} ${row['line']}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              result,
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${row['sport']} | ${row['market']} | ${_percent(row['hitProbability'])} | ${row['modelVersion']}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 8),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 7,
            children: [
              _detail('PROJECTION', row['projection']),
              _detail('ACTUAL', row['actualValue']),
              _detail('CLOSING LINE', row['closingLine']),
              _detail('LINE CLV', row['lineClvPoints']),
              _detail('PROVIDER', row['provider']),
              _detail('ENTRY ODDS', row['entryOdds']),
              _detail('GRADED', _time(row['gradedAt'])),
              _detail('EVENT', _time(row['eventTime'])),
            ],
          ),
          const SizedBox(height: 11),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: ValueKey('owner-why-pi-${row['id']}'),
              onPressed: () => _showWhyInspector(context, row),
              icon: const Icon(Icons.manage_search_rounded, size: 15),
              label: const Text('WHY DID PI CHOOSE THIS?'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: BorderSide(color: AppColors.gold.withValues(alpha: .5)),
                textStyle: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWhyInspector(BuildContext context, Map row) async {
    final explanation = row['explanation'] as Map? ?? const {};
    final sections = (explanation['sections'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final warnings = (explanation['warnings'] as List? ?? const [])
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final sources = explanation['sourceVersions'] as Map? ?? const {};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          key: const ValueKey('owner-why-pi-dialog'),
          backgroundColor: const Color(0xFF08141F),
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.gold.withValues(alpha: .5)),
          ),
          child: SizedBox(
            width: screen.width < 820 ? screen.width * .92 : 760,
            height: screen.height < 850 ? screen.height * .88 : 760,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.manage_search_rounded,
                        color: AppColors.gold,
                        size: 22,
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          'WHY DID PI CHOOSE THIS?',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('owner-why-pi-close'),
                        tooltip: 'Close explanation',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: AppColors.gold.withValues(alpha: .25),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['player']} | ${row['side']} ${row['line']} | ${row['market']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${explanation['summary'] ?? 'No explanation was captured.'}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...sections.map(_explanationSection),
                        if (warnings.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFFB84D,
                              ).withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: const Color(
                                  0xFFFFB84D,
                                ).withValues(alpha: .38),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'DATA WARNINGS',
                                  style: TextStyle(
                                    color: Color(0xFFFFC66D),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ...warnings.map(
                                  (warning) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '•  $warning',
                                      style: const TextStyle(
                                        color: Color(0xFFFFD59A),
                                        fontSize: 9,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'MODEL ${explanation['modelVersion'] ?? row['modelVersion'] ?? '--'}'
                          '${sources.isEmpty ? '' : ' | SOURCES ${sources.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ')}'}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'This view uses evidence saved before the event. Missing evidence is labeled; it is not reconstructed from current data.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 8,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _explanationSection(Map section) {
    final status = '${section['status'] ?? 'MISSING'}';
    final color = status == 'AVAILABLE'
        ? const Color(0xFF65E6B4)
        : status == 'PARTIAL'
        ? AppColors.gold
        : const Color(0xFFFF9B86);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .27)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${section['label'] ?? section['key'] ?? 'Evidence'}'
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${section['value'] ?? '--'}',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${section['detail'] ?? ''}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              height: 1.35,
            ),
          ),
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
          text: '${value ?? '--'}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _empty(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: AppColors.gold.withValues(alpha: .25)),
    ),
    child: Text(
      message,
      style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
    ),
  );
}

class _AuditHeading extends StatelessWidget {
  const _AuditHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: AppColors.gold,
      fontSize: 10,
      fontWeight: FontWeight.w900,
      letterSpacing: .5,
    ),
  );
}
