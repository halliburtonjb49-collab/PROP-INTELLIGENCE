import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'dashboard_panel.dart';

class ModelResultsAuditDashboard extends StatefulWidget {
  const ModelResultsAuditDashboard({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<ModelResultsAuditDashboard> createState() =>
      _ModelResultsAuditDashboardState();
}

class _ModelResultsAuditDashboardState
    extends State<ModelResultsAuditDashboard> {
  late final ApiService _api = widget.apiService ?? ApiService();
  late Future<Map<String, dynamic>> _future = _api.fetchIntelligence(
    'performance',
  );
  String _window = '30d';
  String _dimension = 'sport';

  void _refresh() =>
      setState(() => _future = _api.fetchIntelligence('performance'));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY MODEL AUDIT'),
            ),
          );
        }
        final audit = snapshot.data?['rollingAudit'] as Map? ?? const {};
        final windows = (audit['windows'] as List? ?? const [])
            .whereType<Map>()
            .toList();
        final selected = windows.cast<Map?>().firstWhere(
          (item) => item?['key'] == _window,
          orElse: () => windows.isEmpty ? null : windows.first,
        );
        final dimensions = selected?['dimensions'] as Map? ?? const {};
        final rows = (dimensions[_dimension] as List? ?? const [])
            .whereType<Map>()
            .toList();
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AUTOMATED MODEL-RESULTS AUDIT',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Rolling verified results compared with the confidence shown when each pick was saved.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: windows
                    .map(
                      (item) => ChoiceChip(
                        label: Text('${item['label']}'),
                        selected: item['key'] == _window,
                        onSelected: (_) =>
                            setState(() => _window = '${item['key']}'),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _summary(selected ?? const {}),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    const {
                          'sport': 'SPORT',
                          'propType': 'PROP TYPE',
                          'confidenceTier': 'CONFIDENCE',
                          'pickGrade': 'PICK GRADE',
                          'side': 'OVER / UNDER',
                          'opportunityRole': 'OPPORTUNITY ROLE',
                        }.entries
                        .map((item) => _dimensionChoice(item.key, item.value))
                        .toList(),
              ),
              const SizedBox(height: 10),
              if (rows.isEmpty)
                const DashboardPanel(
                  child: Text('No graded picks are available for this period.'),
                )
              else
                ...rows.map(_row),
              const SizedBox(height: 10),
              const Text(
                'HEALTHY is within calibration guardrails. MONITOR flags a confidence gap. RECALIBRATE reduces confidence only after enough verified results exist.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dimensionChoice(String key, String label) => ChoiceChip(
    label: Text(label),
    selected: _dimension == key,
    onSelected: (_) => setState(() => _dimension = key),
  );

  Widget _summary(Map data) => LayoutBuilder(
    builder: (context, constraints) {
      final width =
          (constraints.maxWidth - (constraints.maxWidth < 620 ? 8 : 24)) /
          (constraints.maxWidth < 620 ? 2 : 4);
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _metric('GRADED PICKS', '${data['sampleSize'] ?? 0}', width),
          _metric('ACCURACY', _percent(data['accuracy']), width),
          _metric('MONITOR', '${data['monitor'] ?? 0}', width),
          _metric('RECALIBRATE', '${data['recalibrate'] ?? 0}', width),
        ],
      );
    },
  );

  Widget _metric(String label, String value, double width) => SizedBox(
    width: width,
    height: 78,
    child: DashboardPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );

  Widget _row(Map row) {
    final status = '${row['status'] ?? 'COLLECTING'}';
    final color = status == 'RECALIBRATE'
        ? Colors.redAccent
        : status == 'MONITOR'
        ? Colors.orangeAccent
        : status == 'HEALTHY'
        ? Colors.greenAccent
        : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DashboardPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['value']}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${row['sampleSize']} graded • ${row['reason']}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _value('ACCURACY', _percent(row['accuracy']))),
            Expanded(
              child: _value('AVG CONF.', _percent(row['averageConfidence'])),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: color),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _value(String label, String value) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 8),
      ),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
  String _percent(Object? value) =>
      value is num ? '${(value * 100).toStringAsFixed(1)}%' : '—';
}
