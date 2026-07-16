import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/dashboard_panel.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, required this.selectedSport});

  final String selectedSport;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final ApiService _apiService = ApiService();
  late Future<List<PropData>> _propsFuture;

  @override
  void initState() {
    super.initState();
    _propsFuture = _apiService.fetchProps();
  }

  @override
  void didUpdateWidget(covariant AnalyticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSport != widget.selectedSport) {
      _refresh();
    }
  }

  void _refresh() {
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
        color: const Color(0xFF101D28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: Row(
        children: [
          const Icon(Icons.feed, size: 18, color: Color(0xFFFFC400)),
          const SizedBox(width: 8),
          const Text(
            'SPORTS ALERTS',
            style: TextStyle(
              color: Color(0xFFFFC400),
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
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<List<PropData>>(
        future: _propsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC400)),
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
                        color: Color(0xFF96A4B2),
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
              : props.map((p) => p.edge).reduce((a, b) => a + b) / total;

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

          final topEdges = [...props]..sort((a, b) => b.edge.compareTo(a.edge));
          final alerts = <String>[
            if (topEdges.isNotEmpty)
              'Top edge: ${topEdges.first.player} (${topEdges.first.edge}%)',
            if (topSport != null)
              'Most active sport: ${topSport.key} (${topSport.value})',
            if (topBook != null)
              'Most active book: ${topBook.key} (${topBook.value})',
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _newsTicker(alerts),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                childAspectRatio: 2.8,
                children: [
                  _statCard('TOTAL PROPS', '$total'),
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
              const SizedBox(height: 14),
              Text(
                selectedSport == 'ALL'
                    ? 'All sports prop performance and edge'
                    : '$selectedSport prop performance and edge',
                style: const TextStyle(
                  color: Color(0xFF96A4B2),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'TOP EDGE OPPORTUNITIES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: topEdges.take(12).length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = topEdges[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1F2E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF294052)),
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
                            '${p.edge}%',
                            style: const TextStyle(
                              color: Color(0xFFFFC400),
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
