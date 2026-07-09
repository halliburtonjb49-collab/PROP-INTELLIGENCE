import 'package:flutter/material.dart';

import '../services/api_service.dart';

class PropBuilderPerformanceScreen extends StatefulWidget {
  const PropBuilderPerformanceScreen({super.key});

  @override
  State<PropBuilderPerformanceScreen> createState() =>
      _PropBuilderPerformanceScreenState();
}

class _PropBuilderPerformanceScreenState
    extends State<PropBuilderPerformanceScreen> {
  final ApiService _apiService = ApiService();
  static const Map<String, int?> _dateRanges = {
    '7D': 7,
    '30D': 30,
    '90D': 90,
    'ALL': null,
  };
  static const List<String> _sports = [
    'ALL',
    'WNBA',
    'NBA',
    'MLB',
    'NFL',
    'NHL',
  ];
  static const List<String> _propSites = [
    'ALL',
    'PrizePicks',
    'Underdog',
    'Sleeper',
    'FanDuel',
    'Draft Picks',
  ];
  static const List<String> _markets = [
    'ALL',
    'points',
    'rebounds',
    'assists',
    'pra',
    'three_pointers_made',
    'steals',
    'blocks',
    'turnovers',
    'strikeouts',
    'hits',
    'home_runs',
    'total_bases',
    'rbi',
    'passing_yards',
    'rushing_yards',
    'receiving_yards',
    'receptions',
    'shots_on_goal',
    'saves',
  ];

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _performance;
  String _selectedRange = '30D';
  String _selectedSport = 'ALL';
  String _selectedPropSite = 'ALL';
  String _selectedMarket = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadPerformance();
  }

  Future<void> _loadPerformance() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _apiService.fetchPropBuilderPerformance(
        days: _dateRanges[_selectedRange],
        sport: _selectedSport,
        propSite: _selectedPropSite,
        market: _selectedMarket,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _performance = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int _intValue(String key) {
    return (_performance?[key] as num?)?.toInt() ?? 0;
  }

  double _doubleValue(String key) {
    return (_performance?[key] as num?)?.toDouble() ?? 0;
  }

  String _marketLabel(String value) {
    const labels = {
      'ALL': 'All Markets',
      'points': 'Points',
      'rebounds': 'Rebounds',
      'assists': 'Assists',
      'pra': 'PRA',
      'three_pointers_made': 'Three-Pointers Made',
      'steals': 'Steals',
      'blocks': 'Blocks',
      'turnovers': 'Turnovers',
      'strikeouts': 'Strikeouts',
      'hits': 'Hits',
      'home_runs': 'Home Runs',
      'total_bases': 'Total Bases',
      'rbi': 'RBIs',
      'passing_yards': 'Passing Yards',
      'rushing_yards': 'Rushing Yards',
      'receiving_yards': 'Receiving Yards',
      'receptions': 'Receptions',
      'shots_on_goal': 'Shots on Goal',
      'saves': 'Saves',
    };
    return labels[value] ?? value.replaceAll('_', ' ');
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }

  Widget _breakdownSection({
    required String title,
    required List<dynamic> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Text('No graded performance data yet.')
        else
          ...items.whereType<Map<String, dynamic>>().map((item) {
            final name = item['name']?.toString() ?? 'Unknown';
            final total = (item['total_builds'] as num?)?.toInt() ?? 0;
            final buildRate = (item['build_win_rate'] as num?)?.toDouble() ?? 0;
            final legRate = (item['leg_hit_rate'] as num?)?.toDouble() ?? 0;
            return Card(
              child: ListTile(
                title: Text(name),
                subtitle: Text(
                  '$total builds • Build win rate ${buildRate.toStringAsFixed(1)}%\n'
                  'Leg hit rate ${legRate.toStringAsFixed(1)}%',
                ),
                isThreeLine: true,
                trailing: SizedBox(
                  width: 70,
                  child: LinearProgressIndicator(
                    value: (legRate / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _legPerformanceSection({
    required String title,
    required List<dynamic> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Text('No graded leg data yet.')
        else
          ...items.whereType<Map<String, dynamic>>().map((item) {
            final name = item['name']?.toString() ?? 'Unknown';
            final totalLegs = (item['total_legs'] as num?)?.toInt() ?? 0;
            final won = (item['legs_won'] as num?)?.toInt() ?? 0;
            final lost = (item['legs_lost'] as num?)?.toInt() ?? 0;
            final pushed = (item['legs_pushed'] as num?)?.toInt() ?? 0;
            final pending = (item['legs_pending'] as num?)?.toInt() ?? 0;
            final hitRate = (item['leg_hit_rate'] as num?)?.toDouble() ?? 0;
            final resolved = (item['resolved_legs'] as num?)?.toInt() ?? 0;
            final edge = (item['average_edge'] as num?)?.toDouble() ?? 0;
            final confidence =
                (item['average_confidence'] as num?)?.toDouble() ?? 0;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          resolved < 5
                              ? '${hitRate.toStringAsFixed(1)}%*'
                              : '${hitRate.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    if (resolved < 5) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Small sample size',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (hitRate / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('$totalLegs legs')),
                        Chip(label: Text('W $won')),
                        Chip(label: Text('L $lost')),
                        Chip(label: Text('Push $pushed')),
                        Chip(label: Text('Pending $pending')),
                        Chip(label: Text('Edge ${edge.toStringAsFixed(1)}%')),
                        Chip(
                          label: Text(
                            'Confidence ${confidence.toStringAsFixed(1)}%',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
    String Function(String value)? itemLabel,
  }) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items.map((item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(itemLabel?.call(item) ?? item),
          );
        }).toList(),
        onChanged: (newValue) {
          if (newValue == null) {
            return;
          }
          onChanged(newValue);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadPerformance,
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    final performance = _performance ?? {};
    final sportItems = performance['by_sport'] as List<dynamic>? ?? [];
    final siteItems = performance['by_prop_site'] as List<dynamic>? ?? [];
    final legSportItems =
        performance['leg_performance_by_sport'] as List<dynamic>? ?? [];
    final legSiteItems =
        performance['leg_performance_by_prop_site'] as List<dynamic>? ?? [];
    final legMarketItems =
        performance['leg_performance_by_market'] as List<dynamic>? ?? [];
    final recentItems = performance['recent_builds'] as List<dynamic>? ?? [];

    return RefreshIndicator(
      onRefresh: _loadPerformance,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BUILDER PERFORMANCE',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text('Track how generated props perform over time.'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadPerformance,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Range: $_selectedRange')),
              Chip(label: Text('Sport: $_selectedSport')),
              Chip(label: Text('Site: $_selectedPropSite')),
              Chip(label: Text('Market: ${_marketLabel(_selectedMarket)}')),
            ],
          ),
          const SizedBox(height: 18),
          if (_intValue('total_builds') == 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.filter_alt_off, size: 38),
                  const SizedBox(height: 10),
                  const Text(
                    'No matching performance data',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No builds matched $_selectedSport, $_selectedPropSite, $_selectedMarket, and $_selectedRange.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 4
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: columns == 1 ? 3.2 : 1.5,
                children: [
                  _metricCard(
                    label: 'Total Builds',
                    value: '${_intValue('total_builds')}',
                    icon: Icons.construction,
                  ),
                  _metricCard(
                    label: 'Build Win Rate',
                    value:
                        '${_doubleValue('build_win_rate').toStringAsFixed(1)}%',
                    icon: Icons.emoji_events,
                  ),
                  _metricCard(
                    label: 'Leg Hit Rate',
                    value:
                        '${_doubleValue('leg_hit_rate').toStringAsFixed(1)}%',
                    icon: Icons.track_changes,
                  ),
                  _metricCard(
                    label: 'Pending Builds',
                    value: '${_intValue('pending_builds')}',
                    icon: Icons.schedule,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _filterDropdown(
                label: 'Sport',
                value: _selectedSport,
                items: _sports,
                onChanged: (value) {
                  setState(() {
                    _selectedSport = value;
                  });
                  _loadPerformance();
                },
              ),
              _filterDropdown(
                label: 'Prop Site',
                value: _selectedPropSite,
                items: _propSites,
                onChanged: (value) {
                  setState(() {
                    _selectedPropSite = value;
                  });
                  _loadPerformance();
                },
              ),
              _filterDropdown(
                label: 'Market',
                value: _selectedMarket,
                items: _markets,
                itemLabel: _marketLabel,
                onChanged: (value) {
                  setState(() {
                    _selectedMarket = value;
                  });
                  _loadPerformance();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _selectedRange = '30D';
                _selectedSport = 'ALL';
                _selectedPropSite = 'ALL';
                _selectedMarket = 'ALL';
              });
              _loadPerformance();
            },
            icon: const Icon(Icons.filter_alt_off),
            label: const Text('RESET FILTERS'),
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 26),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Chip(label: Text('Won: ${_intValue('won_builds')}')),
              Chip(label: Text('Lost: ${_intValue('lost_builds')}')),
              Chip(label: Text('Push: ${_intValue('pushed_builds')}')),
              Chip(label: Text('Legs Won: ${_intValue('legs_won')}')),
              Chip(label: Text('Legs Lost: ${_intValue('legs_lost')}')),
            ],
          ),
          const SizedBox(height: 30),
          _legPerformanceSection(
            title: 'INDIVIDUAL LEG PERFORMANCE BY SPORT',
            items: legSportItems,
          ),
          const SizedBox(height: 30),
          _legPerformanceSection(
            title: 'INDIVIDUAL LEG PERFORMANCE BY PROP SITE',
            items: legSiteItems,
          ),
          const SizedBox(height: 30),
          _legPerformanceSection(
            title: 'INDIVIDUAL LEG PERFORMANCE BY MARKET',
            items: legMarketItems,
          ),
          const SizedBox(height: 30),
          _breakdownSection(title: 'BUILD RESULTS BY SPORT', items: sportItems),
          const SizedBox(height: 30),
          _breakdownSection(
            title: 'BUILD RESULTS BY PROP SITE',
            items: siteItems,
          ),
          const SizedBox(height: 30),
          const Text(
            'RECENT BUILDS',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (recentItems.isEmpty)
            const Text('No recent builds available.')
          else
            ...recentItems.whereType<Map<String, dynamic>>().map((build) {
              final status = build['status']?.toString() ?? 'pending';
              final sports = build['sports'] as List<dynamic>? ?? [];
              final hitRate = (build['hit_rate'] as num?)?.toDouble() ?? 0;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      status == 'won'
                          ? Icons.check
                          : status == 'lost'
                          ? Icons.close
                          : status == 'push'
                          ? Icons.horizontal_rule
                          : Icons.schedule,
                    ),
                  ),
                  title: Text(
                    '${build['generated_legs']}-Leg ${status.toUpperCase()}',
                  ),
                  subtitle: Text(
                    '${sports.join(', ')}\n'
                    'Hit rate ${hitRate.toStringAsFixed(1)}% • '
                    'Edge ${(build['average_edge'] as num? ?? 0).toStringAsFixed(1)}%',
                  ),
                  isThreeLine: true,
                ),
              );
            }),
        ],
      ),
    );
  }
}
