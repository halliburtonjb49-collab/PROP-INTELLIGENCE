import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../services/recommendation_access.dart';
import '../services/auth_service.dart';
import 'player_analytics_chart.dart';
import 'premium_gate.dart';
import 'context_help.dart';
import 'recommendation_explainability_block.dart';

import '../theme/app_colors.dart' as brand_colors;

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

    return const [];
  }

  String _dataFreshness() {
    final raw =
        widget.propData['last_updated_utc'] ??
        widget.propData['lastUpdatedUtc'] ??
        widget.propData['source_updated_utc'];
    final updated = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (updated == null) return 'Freshness unavailable';
    final age = DateTime.now().difference(updated);
    if (age.isNegative || age.inMinutes < 2) return 'Updated just now';
    if (age.inMinutes < 60) return 'Updated ${age.inMinutes}m ago';
    if (age.inHours < 24) return 'Updated ${age.inHours}h ago';
    return 'Updated ${age.inDays}d ago';
  }

  String _sourceLabel() {
    final source =
        widget.propData['source_provider'] ??
        widget.propData['sourceProvider'] ??
        widget.propData['sportsbook'];
    final value = source?.toString().trim() ?? '';
    return value.isEmpty ? 'Source unavailable' : value;
  }

  String _splitValue(String key) {
    final raw = widget.propData[key];
    if (raw == null) return '—';
    if (raw is num) return '${raw.toStringAsFixed(raw % 1 == 0 ? 0 : 1)}%';
    final value = raw.toString().trim();
    return value.isEmpty ? '—' : value;
  }

  double? _number(Iterable<String> keys) {
    for (final key in keys) {
      final raw = widget.propData[key];
      if (raw is num) return raw.toDouble();
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  String? _text(Iterable<String> keys) {
    for (final key in keys) {
      final value = widget.propData[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'unknown') return value;
    }
    return null;
  }

  String? _resolvedDirection() {
    final raw = _text(const [
      'recommended_side',
      'recommendedSide',
      'pick',
    ])?.toLowerCase();
    if (raw != null) {
      if (raw.contains('under') || raw.contains('less')) return 'under';
      if (raw.contains('over') || raw.contains('more')) return 'over';
    }
    final gap =
        widget.aiProjection.toDouble() - widget.sportsbookLine.toDouble();
    if (gap.abs() < .05) return null;
    return gap > 0 ? 'over' : 'under';
  }

  List<({String text, bool positive})> _decisionSignals(List<double> history) {
    final signals = <({String text, bool positive})>[];
    final direction = _resolvedDirection();
    final recommendsUnder = direction == 'under';
    final projectionGap =
        widget.aiProjection.toDouble() - widget.sportsbookLine.toDouble();
    if (projectionGap.abs() >= .05) {
      signals.add((
        text:
            'Projection is ${projectionGap.abs().toStringAsFixed(1)} ${projectionGap >= 0 ? 'above' : 'below'} the current line.',
        positive: recommendsUnder ? projectionGap < 0 : projectionGap >= 0,
      ));
    }
    final projectionMarketWeight = _number(const [
      'projectionMarketWeight',
      'projection_market_weight',
    ]);
    if (projectionMarketWeight != null && projectionMarketWeight > 0) {
      signals.add((
        text:
            'Projection includes a ${(projectionMarketWeight * 100).round()}% multi-book market adjustment.',
        positive: true,
      ));
    }
    if (widget.edgePercentage.abs() >= .05) {
      signals.add((
        text:
            'Estimated edge is ${widget.edgePercentage >= 0 ? '+' : ''}${widget.edgePercentage.toStringAsFixed(1)}%.',
        positive: widget.edgePercentage > 0,
      ));
    }
    if (history.isNotEmpty) {
      final hits = history.where((value) {
        return recommendsUnder
            ? value <= widget.sportsbookLine
            : value >= widget.sportsbookLine;
      }).length;
      signals.add((
        text:
            'Cleared this line in $hits of ${history.length} verified recent games.',
        positive: hits / history.length > .5,
      ));
    }
    final movement = _number(const ['line_movement', 'lineMovement']);
    if (movement != null && movement.abs() >= .01) {
      signals.add((
        text:
            'The market line moved ${movement > 0 ? 'up' : 'down'} ${movement.abs().toStringAsFixed(1)}.',
        positive: false,
      ));
    }
    final injury = _text(const ['injury_status', 'injuryStatus']);
    if (injury != null && injury.toLowerCase() != 'healthy') {
      signals.add((text: 'Injury designation: $injury.', positive: false));
    }
    final lineup = _text(const ['lineup_status', 'lineupStatus']);
    if (lineup != null && !lineup.toLowerCase().contains('confirmed')) {
      signals.add((text: 'Lineup status: $lineup.', positive: false));
    }
    final fatigue = _number(const ['fatigue_index', 'fatigueIndex']);
    if (fatigue != null) {
      signals.add((
        text: 'Fatigue index: ${fatigue.toStringAsFixed(1)}.',
        positive: fatigue < 50,
      ));
    }
    final matchup = _text(const [
      'matchup_context',
      'matchupContext',
      'matchup_summary',
    ]);
    if (matchup != null) {
      signals.add((text: matchup, positive: true));
    }
    final sentiment = _text(const ['sentimentLabel', 'sentiment_label']);
    final sentimentSample = _number(const [
      'sentimentSampleSize',
      'sentiment_sample_size',
    ]);
    if (sentiment != null && (sentimentSample ?? 0) > 0) {
      signals.add((
        text:
            'Community signal: $sentiment (${sentimentSample!.round()} recent actions).',
        positive: sentiment.toUpperCase() == 'FOLLOW',
      ));
    }
    return signals.take(6).toList(growable: false);
  }

  Widget _buildDecisionSummary(List<double> history) {
    final explainabilityProp = PropData.fromJson(
      Map<String, dynamic>.from(widget.propData),
    );
    final signals = _decisionSignals(history);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecommendationExplainabilityBlock(prop: explainabilityProp),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF09131D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: brand_colors.AppColors.gunmetalLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    color: brand_colors.AppColors.goldHighlight,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SUPPLEMENTAL SIGNALS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                  ContextHelp(
                    title: 'Decision summary',
                    message:
                        'These additional signals provide context beyond the standardized explainability block.',
                  ),
                ],
              ),
              const SizedBox(height: 9),
              if (signals.isEmpty)
                const Text(
                  'More verified context is needed before a supplemental summary can be generated.',
                  style: TextStyle(
                    color: brand_colors.AppColors.textSecondary,
                    fontSize: 11,
                  ),
                )
              else
                ...signals.map(
                  (signal) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          signal.positive
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          size: 15,
                          color: signal.positive
                              ? brand_colors.AppColors.blue
                              : const Color(0xFFFFB74D),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            signal.text,
                            style: const TextStyle(
                              color: Color(0xFFDCE8F4),
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(color: Colors.white10, height: 16),
              const Text(
                'Verify the live line, injury status, and lineup before recording a research selection.',
                style: TextStyle(
                  color: brand_colors.AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<({String book, double? line, int odds})> _bookOffers() {
    final raw = widget.propData['odds_data'] ?? widget.propData['oddsData'];
    if (raw is! List) return const [];
    final direction = _resolvedDirection();
    if (direction == null) return const [];
    final under = direction == 'under';
    final offers = <({String book, double? line, int odds})>[];
    for (final item in raw.whereType<Map>()) {
      final book = (item['bookmaker'] ?? item['sportsbook'] ?? item['book'])
          ?.toString()
          .trim();
      final oddsRaw = under
          ? (item['under_odds'] ?? item['underOdds'])
          : (item['over_odds'] ?? item['overOdds']);
      final odds = oddsRaw is num
          ? oddsRaw.toInt()
          : int.tryParse(oddsRaw?.toString() ?? '');
      if (book == null || book.isEmpty || odds == null) continue;
      final lineRaw = item['line'] ?? item['point'] ?? item['current_line'];
      final line = lineRaw is num
          ? lineRaw.toDouble()
          : double.tryParse(lineRaw?.toString() ?? '');
      offers.add((book: book, line: line, odds: odds));
    }
    offers.sort((a, b) => b.odds.compareTo(a.odds));
    return offers.take(4).toList(growable: false);
  }

  String _formatAmerican(int odds) => odds > 0 ? '+$odds' : '$odds';

  Widget _buildLineShop() {
    final offers = _bookOffers();
    final originLine = _number(const [
      'marketOriginLine',
      'market_origin_line',
      'consensus_line',
    ]);
    final discrepancy = _number(const ['lineDiscrepancy', 'line_discrepancy']);
    final publicBets = _number(const [
      'publicBetPercentage',
      'public_bet_percentage',
    ]);
    final money = _number(const ['moneyPercentage', 'money_percentage']);
    final volumeSource = _text(const ['volumeSource', 'volume_source']);
    if (offers.isEmpty && originLine == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF09131D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: brand_colors.AppColors.gunmetalLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.compare_arrows_rounded,
                color: brand_colors.AppColors.goldHighlight,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LINE SHOP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ),
              ContextHelp(
                title: 'Line shopping',
                message:
                    'Prop sites can offer different prices for the same market. This comparison ranks the available American prices for the recommended side; a larger positive number or a number closer to zero generally represents a better available return. Confirm the current value directly with the named prop site.',
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (originLine != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _marketMetric(
                  'OPENING LINE',
                  originLine.toStringAsFixed(1),
                  brand_colors.AppColors.blue,
                ),
                _marketMetric(
                  'THIS LINE',
                  widget.sportsbookLine.toStringAsFixed(1),
                  Colors.white,
                ),
                if (discrepancy != null && discrepancy.abs() >= .01)
                  _marketMetric(
                    'DISCREPANCY',
                    '${discrepancy > 0 ? '+' : ''}${discrepancy.toStringAsFixed(1)}',
                    const Color(0xFFFFB74D),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < offers.length; index++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: index == 0
                        ? brand_colors.AppColors.blue.withValues(alpha: .10)
                        : Colors.white.withValues(alpha: .03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: index == 0
                          ? brand_colors.AppColors.blue
                          : brand_colors.AppColors.chromeShadow,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        index == 0
                            ? 'BEST • ${offers[index].book}'
                            : offers[index].book,
                        style: TextStyle(
                          color: index == 0
                              ? brand_colors.AppColors.blue
                              : brand_colors.AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${offers[index].line?.toStringAsFixed(1) ?? widget.sportsbookLine}  ${_formatAmerican(offers[index].odds)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${offers.length} book${offers.length == 1 ? '' : 's'} compared • verify before placing',
            style: const TextStyle(
              color: brand_colors.AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
          if (publicBets != null || money != null) ...[
            const SizedBox(height: 12),
            if (publicBets != null)
              _volumeBar(
                'PUBLIC SELECTIONS',
                publicBets,
                brand_colors.AppColors.blue,
              ),
            if (money != null) ...[
              const SizedBox(height: 7),
              _volumeBar('MONEY', money, brand_colors.AppColors.goldHighlight),
            ],
            if (volumeSource != null) ...[
              const SizedBox(height: 6),
              Text(
                'Volume source: $volumeSource',
                style: const TextStyle(color: Color(0xFF738195), fontSize: 9),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _marketMetric(String label, String value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: brand_colors.AppColors.textSecondary,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeBar(String label, double rawValue, Color color) {
    final value = rawValue.clamp(0, 100).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(
              color: brand_colors.AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 7,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: .07),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '${value.round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
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
    const primaryYellow = brand_colors.AppColors.goldHighlight;
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
        ? brand_colors.AppColors.blue
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
              : brand_colors.AppColors.chromeShadow,
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
                        color: brand_colors.AppColors.goldHighlight,
                        size: 20,
                      ),
                      onPressed: _toggleCloudFavorite,
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? .5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: brand_colors.AppColors.textMuted,
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.propType,
                  style: const TextStyle(
                    color: brand_colors.AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF182633),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: brand_colors.AppColors.gunmetalLight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatColumn(
                          label: 'LINE / ODDS',
                          value:
                              '${widget.sportsbookLine}  (${widget.americanOdds})',
                          valueColor: brand_colors.AppColors.silver,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: brand_colors.AppColors.gunmetalLight,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PremiumFeatureGateGuard(
                          isUserPremium: widget.isUserPremium,
                          lockedChild: const _StatColumn(
                            label: 'PROJECTION',
                            value: 'LOCKED',
                            valueColor: Color(0xFF7F8EA2),
                          ),
                          child: _StatColumn(
                            label: 'PROJECTION',
                            value: widget.aiProjection.toStringAsFixed(1),
                            valueColor: brand_colors.AppColors.blue,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: brand_colors.AppColors.gunmetalLight,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PremiumFeatureGateGuard(
                          isUserPremium: widget.isUserPremium,
                          lockedChild: const _StatColumn(
                            label: 'EDGE',
                            value: 'LOCKED',
                            valueColor: Color(0xFF7F8EA2),
                          ),
                          child: _StatColumn(
                            label: 'EDGE',
                            value:
                                '${edgePositive ? '+' : ''}${widget.edgePercentage.toStringAsFixed(1)}%',
                            valueColor: edgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF09131D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: brand_colors.AppColors.chromeShadow,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_outlined,
                        size: 15,
                        color: brand_colors.AppColors.goldHighlight,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${_sourceLabel()}  •  ${_dataFreshness()}  •  ${last10GameStats.length} verified recent games',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: brand_colors.AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const ContextHelp(
                        title: 'Data quality',
                        message:
                            'This row identifies the source, update recency, and number of real recent-game observations available to the card. Missing history is shown as unavailable and is never replaced with sample results.',
                      ),
                    ],
                  ),
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
                            ? brand_colors.AppColors.blue
                            : brand_colors.AppColors.goldHighlight,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
                if (_isExpanded) ...[
                  const Divider(color: Colors.white10, height: 24),
                  if (canShowSystemRecommendation(
                    hasEdgeAccess: widget.isUserPremium,
                  )) ...[
                    if (_bookOffers().isNotEmpty) ...[
                      _buildLineShop(),
                      const SizedBox(height: 14),
                    ],
                    _buildDecisionSummary(last10GameStats),
                    const SizedBox(height: 14),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF09131D),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: brand_colors.AppColors.gunmetalLight,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            color: brand_colors.AppColors.goldHighlight,
                            size: 17,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Core shows the live line and factual research. '
                              'System OVER/UNDER suggestions are Pro only.',
                              style: TextStyle(
                                color: Color(0xFFB9C6D3),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
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
                              last10GameStats.isEmpty
                                  ? 'DATA PENDING'
                                  : '$hitRate% HIT RATE',
                              style: TextStyle(
                                color: last10GameStats.isEmpty
                                    ? brand_colors.AppColors.textSecondary
                                    : brand_colors.AppColors.blue,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (last10GameStats.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .03),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Verified recent-game history is not available for this market yet.',
                              style: TextStyle(
                                color: brand_colors.AppColors.textSecondary,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          PlayerAnalyticsChart(
                            targetLine: widget.sportsbookLine.toDouble(),
                            last10GameStats: last10GameStats,
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _buildMiniSplitChip(
                              'Home Games',
                              _splitValue('home_hit_rate'),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniSplitChip(
                              'vs Top 10 Def',
                              _splitValue('top_10_defense_hit_rate'),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniSplitChip(
                              '0 Days Rest',
                              _splitValue('zero_days_rest_hit_rate'),
                            ),
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
