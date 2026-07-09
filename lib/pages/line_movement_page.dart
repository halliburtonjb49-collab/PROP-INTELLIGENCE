import 'package:flutter/material.dart';

import '../services/api_service.dart';

class LineMovementPage extends StatefulWidget {
  const LineMovementPage({super.key, required this.selectedSport});

  final String selectedSport;

  @override
  State<LineMovementPage> createState() => _LineMovementPageState();
}

class _LineMovementPageState extends State<LineMovementPage> {
  final ApiService _apiService = ApiService();
  late Future<_LineMovementViewData> _movementFuture;

  @override
  void initState() {
    super.initState();
    _movementFuture = _loadMovementData(refresh: false);
  }

  @override
  void didUpdateWidget(covariant LineMovementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSport != widget.selectedSport) {
      _refresh();
    }
  }

  void _refresh() {
    setState(() {
      _movementFuture = _loadMovementData(refresh: true);
    });
  }

  Future<_LineMovementViewData> _loadMovementData({
    required bool refresh,
  }) async {
    final selectedSport = widget.selectedSport.trim().toUpperCase();
    final props = (await _apiService.fetchProps()).where((prop) {
      if (selectedSport.isEmpty || selectedSport == 'ALL') {
        return true;
      }
      return prop.sport.trim().toUpperCase() == selectedSport;
    }).toList();
    if (props.isEmpty) {
      return const _LineMovementViewData(items: []);
    }

    final legs = props
        .take(25)
        .map(
          (p) => {
            'prop_id': p.id.isNotEmpty
                ? p.id
                : '${p.player}-${p.market}-${p.sport}',
            'id': p.id.isNotEmpty ? p.id : '${p.player}-${p.market}-${p.sport}',
            'event_id': p.eventId.isNotEmpty ? p.eventId : p.apiSportsGameId,
            'api_sports_game_id': p.apiSportsGameId,
            'player_id': p.playerId.isNotEmpty ? p.playerId : p.player,
            'custom_label': p.customLabel,
            'manual_note': p.manualNote,
            'player': p.player,
            'sport': p.sport,
            'matchup': p.matchup,
            'prop_site': p.sportsbook,
            'sportsbook': p.sportsbook,
            'market': p.market,
            'line': p.line,
            'current_line': p.line,
            'side': p.pick.isEmpty ? 'OVER' : p.pick,
            'pick': p.pick.isEmpty ? 'OVER' : p.pick,
            'odds': p.overOdds ?? p.multiplier ?? 0.0,
            'current_odds': p.overOdds ?? p.multiplier ?? 0.0,
            'over_odds': p.overOdds,
            'under_odds': p.underOdds,
            'multiplier': p.multiplier,
            'win_probability': p.winProbability,
            'edge': p.edge,
            'confidence': (p.winProbability ?? p.edge.toDouble()).round(),
          },
        )
        .toList();

    final response = await _apiService.checkPropLineMovement(
      legs: legs,
      refresh: refresh,
    );
    final rawLegs = response['legs'] as List<dynamic>? ?? [];
    final items = rawLegs
        .whereType<Map<String, dynamic>>()
        .map(_LineMovementItem.fromJson)
        .toList();
    items.sort((a, b) => b.movementMagnitude.compareTo(a.movementMagnitude));
    return _LineMovementViewData(items: items);
  }

  Widget _alertsTicker(List<String> alerts) {
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
            'LINE ALERTS',
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

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'BETTER':
        return const Color(0xFF2ECC71);
      case 'WORSE':
        return const Color(0xFFE74C3C);
      case 'MOVED':
        return const Color(0xFFFFC400);
      case 'UNAVAILABLE':
        return const Color(0xFF94A3B8);
      default:
        return const Color(0xFF5C6B78);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF050B11),
      padding: const EdgeInsets.all(18),
      child: FutureBuilder<_LineMovementViewData>(
        future: _movementFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC400)),
            );
          }
          const defaultAlerts = <String>[
            'Line movement monitor online',
            'Gold alerts update as data refreshes',
            'Interval set to 4 minutes',
          ];
          if (snapshot.hasError) {
            final message = snapshot.error.toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _alertsTicker(defaultAlerts),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111B26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF8B6813)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LINE MOVEMENT FAILED TO LOAD',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message.length > 220
                            ? '${message.substring(0, 220)}...'
                            : message,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF96A4B2),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('TRY AGAIN'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final data = snapshot.data ?? const _LineMovementViewData(items: []);
          final top = data.items.take(15).toList();
          final changed = data.items
              .where((item) => item.status != 'UNCHANGED')
              .length;
          final alerts = <String>[
            if (top.isNotEmpty)
              'Largest movement signal: ${top.first.player} (${top.first.movementMagnitude.toStringAsFixed(2)})',
            'Changed lines detected: $changed',
            widget.selectedSport == 'ALL'
                ? 'Tracking all sports'
                : 'Tracking ${widget.selectedSport.toUpperCase()}',
            'Data source: prop-builder line check',
            'Interval set to 4 minutes',
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _alertsTicker(alerts),
              const SizedBox(height: 14),
              const Text(
                'LINE MOVEMENT INTEL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: top.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = top[index];
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${p.player} • ${p.market} • ${p.sport}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Line ${p.previousLine?.toStringAsFixed(2) ?? '-'} -> ${p.currentLine?.toStringAsFixed(2) ?? '-'}',
                                  style: const TextStyle(
                                    color: Color(0xFF96A4B2),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                p.status,
                              ).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _statusColor(p.status)),
                            ),
                            child: Text(
                              p.status,
                              style: TextStyle(
                                color: _statusColor(p.status),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
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

class _LineMovementViewData {
  final List<_LineMovementItem> items;

  const _LineMovementViewData({required this.items});
}

class _LineMovementItem {
  final String player;
  final String sport;
  final String market;
  final String status;
  final double? previousLine;
  final double? currentLine;

  const _LineMovementItem({
    required this.player,
    required this.sport,
    required this.market,
    required this.status,
    required this.previousLine,
    required this.currentLine,
  });

  double get movementMagnitude {
    if (previousLine == null || currentLine == null) {
      return 0;
    }
    return (currentLine! - previousLine!).abs();
  }

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  factory _LineMovementItem.fromJson(Map<String, dynamic> json) {
    return _LineMovementItem(
      player: json['player']?.toString() ?? 'Unknown',
      sport: json['sport']?.toString() ?? '',
      market: json['market']?.toString() ?? '',
      status: (json['movement_status']?.toString() ?? 'UNCHANGED')
          .toUpperCase(),
      previousLine: _asDouble(json['previous_line'] ?? json['line_before']),
      currentLine: _asDouble(
        json['line'] ?? json['current_line'] ?? json['line_after'],
      ),
    );
  }
}
