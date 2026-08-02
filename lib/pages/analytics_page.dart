import 'dart:async';

import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/dashboard_panel.dart';
import '../widgets/context_help.dart';
import '../widgets/evaluation_cohort_dashboard.dart';
import '../widgets/model_results_audit_dashboard.dart';

import '../theme/app_colors.dart' as brand_colors;

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({
    super.key,
    required this.selectedSport,
    required this.hasProAccess,
  });

  final String selectedSport;
  final bool hasProAccess;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final ApiService _apiService = ApiService();
  late Future<List<PropData>> _propsFuture;
  Timer? _refreshTimer;
  bool _showEvaluation = false;
  bool _showModelAudit = false;

  @override
  void initState() {
    super.initState();
    _propsFuture = _apiService.fetchProps();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSport != widget.selectedSport) {
      _refresh();
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _propsFuture = _apiService.fetchProps();
    });
  }

  Widget _statCard(String label, String value) {
    return DashboardPanel(
      padding: const EdgeInsets.all(12),
      radius: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _newsTicker(List<String> alerts) {
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: brand_colors.AppColors.bgPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: brand_colors.AppColors.goldShadow),
      ),
      child: Row(
        children: [
          const Icon(Icons.feed, size: 18, color: brand_colors.AppColors.gold),
          const SizedBox(width: 8),
          const Text(
            'SPORTS ALERTS',
            style: TextStyle(
              color: brand_colors.AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: alerts
                    .map(
                      (alert) => Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Text(
                          alert,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showModelAudit) {
      return Container(
        color: AppColors.background,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showModelAudit = false),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('MARKET ANALYTICS'),
              ),
            ),
            const SizedBox(height: 6),
            const Expanded(child: ModelResultsAuditDashboard()),
          ],
        ),
      );
    }
    if (_showEvaluation) {
      return Container(
        color: AppColors.background,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showEvaluation = false),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('MARKET ANALYTICS'),
              ),
            ),
            const SizedBox(height: 6),
            const Expanded(child: EvaluationCohortDashboard()),
          ],
        ),
      );
    }
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<List<PropData>>(
        future: _propsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.blue),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ANALYTICS FAILED TO LOAD',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: brand_colors.AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('TRY AGAIN'),
                    ),
                  ],
                ),
              ),
            );
          }

          final allProps = snapshot.data ?? const <PropData>[];
          final selectedSport = widget.selectedSport.trim().toUpperCase();
          final props = selectedSport.isEmpty || selectedSport == 'ALL'
              ? allProps
              : allProps
                    .where(
                      (prop) =>
                          prop.sport.trim().toUpperCase() == selectedSport,
                    )
                    .toList();
          final total = props.length;
          final avgEdge = total == 0
              ? 0
              : props
                        .map((p) => p.calculatedEdge ?? 0)
                        .reduce((a, b) => a + b) /
                    total;

          final bySport = <String, int>{};
          final byBook = <String, int>{};
          for (final prop in props) {
            bySport[prop.sport] = (bySport[prop.sport] ?? 0) + 1;
            byBook[prop.sportsbook] = (byBook[prop.sportsbook] ?? 0) + 1;
          }
          final MapEntry<String, int>? topSport = bySport.entries.isEmpty
              ? null
              : (bySport.entries.toList()..sort((a, b) => b.value - a.value))
                    .first;
          final MapEntry<String, int>? topBook = byBook.entries.isEmpty
              ? null
              : (byBook.entries.toList()..sort((a, b) => b.value - a.value))
                    .first;

          final rankedProps = [...props]
            ..sort(
              widget.hasProAccess
                  ? (a, b) =>
                        (b.calculatedEdge ?? 0).compareTo(a.calculatedEdge ?? 0)
                  : (a, b) => a.player.compareTo(b.player),
            );
          final alerts = <String>[
            if (rankedProps.isNotEmpty)
              'Top edge: ${rankedProps.first.player} (${(rankedProps.first.calculatedEdge ?? 0).toStringAsFixed(2)})',
            if (topSport != null)
              'Most active sport: ${topSport.key} (${topSport.value})',
            if (topBook != null)
              'Most active book: ${topBook.key} (${topBook.value})',
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ANALYTICS',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Player and market coverage, with advanced model intelligence for Pro.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ContextHelp(
                    title: 'Analytics',
                    message:
                        'Core shows player, sport, market, and sportsbook coverage. Pro adds projections, confidence, and edge metrics.',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _showModelAudit = true),
                      icon: const Icon(Icons.query_stats, size: 15),
                      label: const Text('MODEL RESULTS AUDIT'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _showEvaluation = true),
                      icon: const Icon(Icons.fact_check_outlined, size: 15),
                      label: const Text('EVALUATION COHORT'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (widget.hasProAccess) ...[
                _newsTicker(alerts),
                const SizedBox(height: 14),
              ],
              LayoutBuilder(
                builder: (context, constraints) => GridView.count(
                  crossAxisCount: constraints.maxWidth < 620 ? 2 : 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: constraints.maxWidth < 620 ? 2.4 : 2.8,
                  children: [
                    _statCard('TOTAL PROPS', '$total'),
                    if (widget.hasProAccess)
                      _statCard('AVG EDGE', '${avgEdge.toStringAsFixed(1)}%'),
                    _statCard(
                      'TOP SPORT',
                      topSport == null
                          ? 'N/A'
                          : '${topSport.key} (${topSport.value})',
                    ),
                    _statCard(
                      'TOP BOOK',
                      topBook == null
                          ? 'N/A'
                          : '${topBook.key} (${topBook.value})',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.hasProAccess
                    ? selectedSport == 'ALL'
                          ? 'All sports prop performance and edge'
                          : '$selectedSport prop performance and edge'
                    : selectedSport == 'ALL'
                    ? 'Basic player and market coverage'
                    : '$selectedSport player and market coverage',
                style: const TextStyle(
                  color: brand_colors.AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.hasProAccess
                    ? 'TOP EDGE OPPORTUNITIES'
                    : 'AVAILABLE PLAYER MARKETS',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: rankedProps.isEmpty
                    ? const Center(
                        child: Text(
                          'No analytics are available for this sport yet.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: rankedProps.take(12).length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final p = rankedProps[index];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1F2E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: brand_colors.AppColors.chromeShadow,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${p.player} • ${p.market} • ${p.sport}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Text(
                                  widget.hasProAccess
                                      ? '${p.edge}%'
                                      : p.sportsbook.toUpperCase(),
                                  style: TextStyle(
                                    color: widget.hasProAccess
                                        ? brand_colors.AppColors.gold
                                        : brand_colors.AppColors.silver,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
