import 'package:flutter/material.dart';

import '../models/saved_slip.dart';
import '../services/api_service.dart';
import '../services/evaluation_cohort.dart';
import '../theme/app_colors.dart' as colors;

class EvaluationCohortDashboard extends StatefulWidget {
  const EvaluationCohortDashboard({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<EvaluationCohortDashboard> createState() =>
      _EvaluationCohortDashboardState();
}

class _EvaluationCohortDashboardState extends State<EvaluationCohortDashboard> {
  late final ApiService _api;
  late Future<List<SavedSlip>> _future;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
    _future = _api.fetchSlips();
  }

  void _refresh() => setState(() => _future = _api.fetchSlips());

  String _metric(double? value, {String suffix = ''}) =>
      value == null ? 'PENDING' : '${value.toStringAsFixed(1)}$suffix';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedSlip>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY EVALUATION LOAD'),
            ),
          );
        }
        final cohort = EvaluationCohort.fromSlips(snapshot.data ?? const []);
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
                          'EVALUATION COHORT',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Rules fixed before results: every saved leg with an entry projection is included.',
                          style: TextStyle(
                            color: colors.AppColors.textMuted,
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
              LayoutBuilder(
                builder: (context, constraints) => GridView.count(
                  crossAxisCount: constraints.maxWidth < 620 ? 2 : 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    _Metric('COHORT LEGS', '${cohort.legs}'),
                    _Metric('PENDING', '${cohort.pending}'),
                    _Metric('ACCURACY', _metric(cohort.accuracy, suffix: '%')),
                    _Metric(
                      'PROJECTION MAE',
                      _metric(cohort.meanAbsoluteError),
                    ),
                    _Metric(
                      'AVG CONFIDENCE',
                      _metric(cohort.averageConfidence, suffix: '%'),
                    ),
                    _Metric(
                      'BEAT CLOSE',
                      _metric(cohort.beatCloseRate, suffix: '%'),
                    ),
                    _Metric(
                      'W / L / P',
                      '${cohort.wins} / ${cohort.losses} / ${cohort.pushes}',
                    ),
                    _Metric(
                      'CORRELATED TICKETS',
                      '${cohort.correlatedTickets}',
                    ),
                  ],
                ),
              ),
              if (cohort.correlatedTickets > 0) ...[
                const SizedBox(height: 10),
                const _Notice(
                  icon: Icons.hub_outlined,
                  text:
                      'Correlation warning: multiple legs share an event. Judge leg accuracy separately from full-ticket results.',
                ),
              ],
              const SizedBox(height: 14),
              Text(
                cohort.sourceCounts.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join('  •  '),
                style: const TextStyle(
                  color: colors.AppColors.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (cohort.slips.isEmpty)
                const _Notice(
                  icon: Icons.hourglass_empty,
                  text: 'No projected ticket legs have been saved yet.',
                )
              else
                ...cohort.slips.map((slip) => _CohortTicket(slip: slip)),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: colors.AppColors.bgPanel,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: colors.AppColors.chromeShadow),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: colors.AppColors.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: colors.AppColors.gold.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: colors.AppColors.goldShadow),
    ),
    child: Row(
      children: [
        Icon(icon, color: colors.AppColors.gold, size: 17),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 9))),
      ],
    ),
  );
}

class _CohortTicket extends StatelessWidget {
  const _CohortTicket({required this.slip});
  final SavedSlip slip;
  @override
  Widget build(BuildContext context) {
    final legs = slip.legs.where((leg) => leg.projection != null).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.AppColors.bgPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.AppColors.chromeShadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${legs.length} LEGS  •  ${slip.status.toUpperCase()}',
            style: const TextStyle(
              color: colors.AppColors.gold,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...legs.map(
            (leg) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '${leg.player}  •  ${leg.side} ${leg.line.toStringAsFixed(1)} ${leg.market.toUpperCase()}  •  MODEL ${leg.projection!.toStringAsFixed(2)}  •  ${leg.resultStatus.toUpperCase()}',
                style: const TextStyle(fontSize: 9),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
