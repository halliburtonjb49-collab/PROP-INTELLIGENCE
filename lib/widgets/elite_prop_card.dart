import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'player_analytics_chart.dart';
import 'premium_gate.dart';

class ElitePropCard extends StatefulWidget {
  final String playerName;
  final String propType;
  final num sportsbookLine;
  final int americanOdds;
  final num aiProjection;
  final num edgePercentage;
  final bool isUserPremium;
  final bool initialIsFavorited;
  final ValueChanged<bool>? onFavoriteChanged;
  final Map<String, dynamic> propData;

  const ElitePropCard({
    super.key,
    required this.playerName,
    required this.propType,
    required this.sportsbookLine,
    required this.americanOdds,
    required this.aiProjection,
    required this.edgePercentage,
    required this.isUserPremium,
    this.initialIsFavorited = false,
    this.onFavoriteChanged,
    this.propData = const {},
  });

  @override
  State<ElitePropCard> createState() => _ElitePropCardState();
}

class _ElitePropCardState extends State<ElitePropCard> {
  bool _isExpanded = false;
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    _isFavorited = widget.initialIsFavorited;
  }

  @override
  void didUpdateWidget(covariant ElitePropCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIsFavorited != widget.initialIsFavorited &&
        _isFavorited != widget.initialIsFavorited) {
      setState(() {
        _isFavorited = widget.initialIsFavorited;
      });
    }
  }

  Future<void> _toggleCloudFavorite() async {
    final authService = SportsAppAuthService();
    final sport = (widget.propData['sport'] ?? 'NBA').toString();

    try {
      if (_isFavorited) {
        await authService.removePlayerFromCloudWatchlist(widget.playerName);
      } else {
        await authService.addPlayerToCloudWatchlist(widget.playerName, sport);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isFavorited = !_isFavorited;
      });
      widget.onFavoriteChanged?.call(_isFavorited);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFavorited
                ? 'Saved ${widget.playerName} to your Cloud Watchlist Profile!'
                : 'Removed ${widget.playerName} from your Cloud Watchlist Profile.',
          ),
          backgroundColor: const Color(0xFF1E222A),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cloud sync failed: $error'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  List<double> _resolveLast10GameStats() {
    final marketKey = widget.propType.trim().toLowerCase();
    final marketMappedRaw = widget.propData['historical_stats_by_market'];

    List<double> parseStats(dynamic raw) {
      if (raw is! List || raw.isEmpty) {
        return const [];
      }
      return raw
          .map((value) {
            if (value is num) {
              return value.toDouble();
            }
            return double.tryParse(value.toString());
          })
          .whereType<double>()
          .take(10)
          .toList(growable: false);
    }

    if (marketMappedRaw is Map) {
      for (final entry in marketMappedRaw.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        if (key == marketKey) {
          final parsed = parseStats(entry.value);
          if (parsed.isNotEmpty) {
            return parsed;
          }
        }
      }
    }

    final candidates = [
      widget.propData['last10_game_stats'],
      widget.propData['last_10_stats'],
      widget.propData['historical_game_stats'],
      widget.propData['recent_game_stats'],
      widget.propData['game_log_stats'],
    ];

    for (final candidate in candidates) {
      final parsed = parseStats(candidate);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    return const [28.0, 31.0, 19.0, 26.0, 22.0, 35.0, 29.0, 27.0, 15.0, 32.0];
  }

  Widget _buildMiniSplitChip(String title, String stat) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(
              stat,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryYellow = Color(0xFFFFD700);
    final last10GameStats = _resolveLast10GameStats();
    final hitRate = last10GameStats.isEmpty
        ? 0
        : ((last10GameStats
                          .where((value) => value >= widget.sportsbookLine)
                          .length /
                      last10GameStats.length) *
                  100)
              .round();

    final bool edgePositive = widget.edgePercentage >= 0;
    final Color edgeColor = edgePositive
        ? const Color(0xFF24C47E)
        : const Color(0xFFF0616B);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1620),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isExpanded
              ? primaryYellow.withValues(alpha: 0.5)
              : const Color(0xFF273445),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.playerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.propData.containsKey('injury_status') &&
                              widget.propData['injury_status'] !=
                                  'Healthy') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: widget.propData['injury_status'] == 'Out'
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      widget.propData['injury_status'] == 'Out'
                                      ? Colors.redAccent
                                      : Colors.amber,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '${widget.propData['injury_status'].toString().toUpperCase()}: ${widget.propData['injury_comment'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      widget.propData['injury_status'] == 'Out'
                                      ? Colors.redAccent
                                      : Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isFavorited ? Icons.star : Icons.star_border,
                        color: const Color(0xFFFFD700),
                        size: 20,
                      ),
                      onPressed: _toggleCloudFavorite,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.propType,
                  style: const TextStyle(
                    color: Color(0xFF98A6B8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatColumn(
                        label: 'Sportsbook',
                        value:
                            '${widget.sportsbookLine}  (${widget.americanOdds})',
                        valueColor: const Color(0xFFDCE8F4),
                      ),
                    ),
                    Expanded(
                      child: PremiumFeatureGateGuard(
                        isUserPremium: widget.isUserPremium,
                        lockedChild: const _StatColumn(
                          label: 'Projection',
                          value: 'LOCKED',
                          valueColor: Color(0xFF7F8EA2),
                        ),
                        child: _StatColumn(
                          label: 'Projection',
                          value: widget.aiProjection.toStringAsFixed(1),
                          valueColor: const Color(0xFF87B7FF),
                        ),
                      ),
                    ),
                    Expanded(
                      child: PremiumFeatureGateGuard(
                        isUserPremium: widget.isUserPremium,
                        lockedChild: const _StatColumn(
                          label: 'Edge',
                          value: 'LOCKED',
                          valueColor: Color(0xFF7F8EA2),
                        ),
                        child: _StatColumn(
                          label: 'Edge',
                          value:
                              '${edgePositive ? '+' : ''}${widget.edgePercentage.toStringAsFixed(1)}%',
                          valueColor: edgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((widget.propData['current_progress_value'] as num?) !=
                        null &&
                    ((widget.propData['current_progress_value'] as num?) ?? 0) >
                        0) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        (widget.propData['game_status'] ?? '')
                            .toString()
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        '${((widget.propData['current_progress_value'] as num?) ?? 0).toStringAsFixed(0)} / ${widget.sportsbookLine.toStringAsFixed(1)} ${widget.propType}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value:
                          (((widget.propData['current_progress_value']
                                          as num?) ??
                                      0) /
                                  (widget.sportsbookLine == 0
                                      ? 1
                                      : widget.sportsbookLine))
                              .clamp(0.0, 1.0),
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        (((widget.propData['current_progress_value'] as num?) ??
                                    0) >=
                                widget.sportsbookLine)
                            ? Colors.greenAccent
                            : const Color(0xFFFFD700),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
                if (_isExpanded) ...[
                  const Divider(color: Colors.white10, height: 24),
                  PremiumFeatureGateGuard(
                    isUserPremium: widget.isUserPremium,
                    lockedChild: const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Premium required: unlock historical splits and situational hit-rate insights.',
                        style: TextStyle(
                          color: Color(0xFF7F8EA2),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'HISTORICAL HIT PERFORMANCE (LAST 10 GAMES)',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$hitRate% HIT RATE',
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PlayerAnalyticsChart(
                          targetLine: widget.sportsbookLine.toDouble(),
                          last10GameStats: last10GameStats,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildMiniSplitChip('Home Games', '80% Hit'),
                            const SizedBox(width: 8),
                            _buildMiniSplitChip('vs Top 10 Def', '60% Hit'),
                            const SizedBox(width: 8),
                            _buildMiniSplitChip('0 Days Rest', '40% Hit'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8A98AA), fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
