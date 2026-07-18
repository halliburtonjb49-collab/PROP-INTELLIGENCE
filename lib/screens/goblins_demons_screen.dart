import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../models/slip_selection.dart';
import '../services/api_service.dart';

class GoblinsDemonsScreen extends StatefulWidget {
  const GoblinsDemonsScreen({super.key, required this.onSelect});

  final void Function(PropData prop, PickSide side) onSelect;

  @override
  State<GoblinsDemonsScreen> createState() => _GoblinsDemonsScreenState();
}

enum _SpecialFilter { all, goblin, demon }

enum _SpecialType { none, goblin, demon }

enum _SortMode { hitRate, edge, startTime }

class _GoblinsDemonsScreenState extends State<GoblinsDemonsScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _gridScrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  bool _usingFallbackSpecials = false;
  final Map<String, _SpecialType> _forcedTypes = <String, _SpecialType>{};
  bool _showBuilderTake = false;
  _SpecialFilter _filter = _SpecialFilter.all;
  _SortMode _sortMode = _SortMode.hitRate;
  List<PropData> _specialProps = const [];
  final Map<String, PickSide> _selectedSides = <String, PickSide>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final props = await _apiService.fetchProps(sortBy: 'confidence');
      final taggedPrizePicksSpecials =
          props
              .where(
                (prop) =>
                    _isPrizePicksSpecial(prop) &&
                    _classify(prop) != _SpecialType.none,
              )
              .toList(growable: false)
            ..sort((a, b) => b.confidence.compareTo(a.confidence));

      final specials =
          taggedPrizePicksSpecials.isNotEmpty
                ? taggedPrizePicksSpecials
                : props
                      .where((prop) => _classify(prop) != _SpecialType.none)
                      .toList()
            ..sort((a, b) => b.confidence.compareTo(a.confidence));

      final usingFallback = taggedPrizePicksSpecials.isEmpty;
      final forcedTypes = <String, _SpecialType>{};
      if (specials.isNotEmpty) {
        var goblinCount = 0;
        for (final prop in specials) {
          if (_classifyBase(prop) == _SpecialType.goblin) {
            goblinCount += 1;
          }
        }

        if (goblinCount == 0) {
          final goblinTarget = (specials.length * 0.30).round().clamp(1, 12);
          final promoted = [...specials]
            ..sort((a, b) => b.confidence.compareTo(a.confidence));
          for (final prop in promoted.take(goblinTarget)) {
            forcedTypes[prop.id] = _SpecialType.goblin;
          }
        }
      }

      final nextSides = <String, PickSide>{
        for (final prop in specials)
          prop.id: _selectedSides[prop.id] ?? _preferredSide(prop),
      };

      if (!mounted) {
        return;
      }

      setState(() {
        _specialProps = specials;
        _usingFallbackSpecials = usingFallback;
        _forcedTypes
          ..clear()
          ..addAll(forcedTypes);
        _selectedSides
          ..clear()
          ..addAll(nextSides);
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

  bool _isPrizePicksSpecial(PropData prop) {
    final source = '${prop.sportsbook} ${prop.sourceProvider}'.toLowerCase();
    return source.contains('prizepicks') || source.contains('prize picks');
  }

  _SpecialType _classify(PropData prop) {
    final forced = _forcedTypes[prop.id];
    if (forced != null) {
      return forced;
    }
    return _classifyBase(prop);
  }

  _SpecialType _classifyBase(PropData prop) {
    final corpus = [
      prop.tier,
      prop.pickText,
      prop.category,
      prop.propType,
      prop.displayMarket,
      prop.marketName,
      prop.marketKey,
      prop.customLabel,
      prop.manualNote,
    ].join(' ').toLowerCase();

    if (corpus.contains('goblin') || corpus.contains('green goblin')) {
      return _SpecialType.goblin;
    }
    if (corpus.contains('demon') || corpus.contains('red demon')) {
      return _SpecialType.demon;
    }

    // Fallback classification when feed does not explicitly tag specials.
    if (prop.confidence >= 78 || prop.edge >= 8) {
      return _SpecialType.goblin;
    }
    if (prop.confidence <= 58 || prop.edge <= -4) {
      return _SpecialType.demon;
    }

    return _SpecialType.none;
  }

  PickSide _preferredSide(PropData prop) {
    final basis = '${prop.recommendedSide} ${prop.pick} ${prop.pickText}'
        .toLowerCase();
    if (basis.contains('under') ||
        basis.contains('less') ||
        basis.contains('lower')) {
      return PickSide.under;
    }
    return PickSide.over;
  }

  Widget _playerImage(String imagePath) {
    final normalized = imagePath.trim();
    if (normalized.isEmpty) {
      return const Icon(Icons.person, color: Colors.white70, size: 22);
    }

    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: normalized,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) =>
            const Icon(Icons.person, color: Colors.white70, size: 22),
      );
    }

    return Image.asset(
      normalized,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.person, color: Colors.white70, size: 22),
    );
  }

  Widget _playerAvatar(
    PropData prop, [
    Color outlineColor = const Color(0xFF8B6813),
  ]) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: outlineColor, width: 2),
      ),
      child: ClipOval(
        child: ColoredBox(
          color: const Color(0xFF0A1622),
          child: _playerImage(prop.imagePath),
        ),
      ),
    );
  }

  Widget _specialIcon(_SpecialType type, {double size = 18}) {
    final isGoblin = type == _SpecialType.goblin;
    return Icon(
      isGoblin ? Icons.masks_outlined : Icons.whatshot,
      size: size,
      color: isGoblin ? const Color(0xFF36B9FF) : const Color(0xFFFF5656),
    );
  }

  Widget _specialLabel(_SpecialType type, String text, {double iconSize = 13}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _specialIcon(type, size: iconSize),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }

  Widget _buildBuilderTakeDetails() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xB2071828),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.masks_outlined, size: 20, color: Color(0xFF36B9FF)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GREEN GOBLINS\n'
                    'Green Goblins can be worth it when you are building\n'
                    'a safer slip, especially if the Goblin line is still strong\n'
                    'compared to the player\'s real projection.\n\n'
                    'Example: if a player\'s normal points line is 22.5 and\n'
                    'the Goblin is 17.5, but your stats project him around 24,\n'
                    'that can be useful.\n\n'
                    'The problem is the payout drops, so too many Goblins\n'
                    'can make the slip not worth the risk.',
                    style: TextStyle(color: Color(0xFFD8E2EE), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 16),
          SizedBox(
            height: 56,
            child: VerticalDivider(color: Color(0xFF2D475B), thickness: 1),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.whatshot, size: 20, color: Color(0xFFFF5656)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'RED DEMONS\n'
                    'Red Demons are usually not worth it unless you\n'
                    'have a real reason the player can smash the line.\n\n'
                    'Demons raise the projection and increase payout,\n'
                    'but they are harder to hit.\n\n'
                    'Treat Demons like high-risk boost plays, not\n'
                    'normal safe props.',
                    style: TextStyle(color: Color(0xFFD8E2EE), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PropData> get _visibleProps {
    return _specialProps
        .where((prop) {
          final type = _classify(prop);
          if (_filter == _SpecialFilter.all) {
            return true;
          }
          if (_filter == _SpecialFilter.goblin) {
            return type == _SpecialType.goblin;
          }
          return type == _SpecialType.demon;
        })
        .toList(growable: false);
  }

  List<PropData> get _sortedVisibleProps {
    final items = _visibleProps.toList(growable: false);
    switch (_sortMode) {
      case _SortMode.hitRate:
        items.sort((a, b) => b.confidence.compareTo(a.confidence));
        break;
      case _SortMode.edge:
        items.sort((a, b) => b.edge.compareTo(a.edge));
        break;
      case _SortMode.startTime:
        DateTime parseTime(PropData p) {
          final raw = p.startTimeUtc.isNotEmpty
              ? p.startTimeUtc
              : p.gameStartTime;
          return DateTime.tryParse(raw)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
        }

        items.sort((a, b) => parseTime(a).compareTo(parseTime(b)));
        break;
    }
    return items;
  }

  void _showHowItWorks() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A1824),
        title: const Text('How It Works'),
        content: const Text(
          'This page shows Goblin and Demon style props.\n\n'
          'Green Goblins are safer helper picks with reduced payout.\n'
          'Red Demons are higher-risk picks with higher payout potential.\n\n'
          'Choose OVER or UNDER on each card, then tap ADD TO SLIP to send it to Current Slip.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  String _propGameDayDate(PropData prop) {
    final rawStartTime = prop.startTimeUtc.isNotEmpty
        ? prop.startTimeUtc
        : prop.gameStartTime;
    if (rawStartTime.isEmpty) {
      return '';
    }

    final parsed = DateTime.tryParse(rawStartTime);
    if (parsed == null) {
      return '';
    }

    final local = parsed.toLocal();
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${days[local.weekday - 1]} ${months[local.month - 1]} ${local.day}';
  }

  String _marketLabel(PropData prop) {
    final market = prop.market.trim();
    if (market.isNotEmpty) {
      return market.toUpperCase();
    }
    return 'PROP';
  }

  Widget _buildSpecialPropCard(PropData prop) {
    final type = _classify(prop);
    final cardBorderColor = type == _SpecialType.demon
        ? const Color(0xFFFF5656)
        : const Color(0xFF36B9FF);
    final selectedSide = _selectedSides[prop.id] ?? _preferredSide(prop);
    final side = prop.pick.trim().isEmpty ? 'BEST' : prop.pick.toUpperCase();
    final lineValue = prop.currentLine == 0 ? prop.line : prop.currentLine;
    final lineDisplay = lineValue == lineValue.roundToDouble()
        ? lineValue.toInt().toString()
        : lineValue.toStringAsFixed(1);
    final gameDayDate = _propGameDayDate(prop);
    final confidence = prop.confidence.clamp(0, 100).toDouble();
    final recommendationSide = prop.recommendedSide.trim().toUpperCase();
    final recommendationText = prop.pickText.trim().isEmpty
        ? 'No Pick'
        : prop.pickText.trim();
    final normalizedRecommendationText = recommendationText.toUpperCase();
    final isUnderPick =
        side == 'UNDER' ||
        recommendationSide.startsWith('UNDER') ||
        normalizedRecommendationText.startsWith('UNDER');
    final sideAccentColor = isUnderPick
        ? Colors.white
        : const Color(0xFFFFD76A);
    final sourceLabel = prop.sourceProvider.trim().isEmpty
        ? prop.sportsbook
        : prop.sourceProvider;
    final updatedLabel = prop.lastUpdatedLocalDisplay;
    final hasLineMovement = (prop.openingLine - prop.currentLine).abs() >= 0.01;
    final openingLineText = prop.openingLine == prop.openingLine.roundToDouble()
        ? prop.openingLine.toInt().toString()
        : prop.openingLine.toStringAsFixed(1);
    final currentLineText = prop.currentLine == prop.currentLine.roundToDouble()
        ? prop.currentLine.toInt().toString()
        : prop.currentLine.toStringAsFixed(1);

    return RepaintBoundary(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF081723),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC400).withValues(alpha: 0.08),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_marketLabel(prop)} • ${prop.localGameTimeDisplay.isNotEmpty ? prop.localGameTimeDisplay : '--:--'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.star_border,
                      color: Color(0xFFFFC400),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (gameDayDate.isNotEmpty) ...[
                  Text(
                    gameDayDate,
                    style: const TextStyle(
                      color: Color(0xFFFFC400),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A3B14), Color(0xFF2F2610)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFFFC400)),
                  ),
                  child: Text(
                    '★ BEST PICK: $side',
                    style: TextStyle(
                      color: sideAccentColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pick: $recommendationText',
                  style: const TextStyle(color: Color(0xFFB0B8C4), fontSize: 9),
                ),
                const SizedBox(height: 4),
                Text(
                  'Confidence: ${prop.confidence}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tier: ${prop.tier}',
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Live market model',
                  style: TextStyle(color: Color(0xFF7E8B99), fontSize: 8),
                ),
                const SizedBox(height: 3),
                Text(
                  updatedLabel.isEmpty
                      ? 'Source: $sourceLabel'
                      : 'Updated: $updatedLabel • Source: $sourceLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF7E8B99), fontSize: 8),
                ),
                if (hasLineMovement)
                  Text(
                    'Line: $openingLineText → $currentLineText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9DB0C4),
                      fontSize: 8,
                    ),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      _playerAvatar(prop),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF211C0B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF8B6813)),
                        ),
                        child: Text(
                          prop.sportsbook.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFC400),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        prop.player,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        prop.matchup,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF7E8B99),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recommendationText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUnderPick
                                  ? Colors.white
                                  : const Color(0xFFFFC400),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$lineDisplay ${_marketLabel(prop)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFB0B8C4),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: (confidence / 100).clamp(0, 1),
                    minHeight: 7,
                    backgroundColor: const Color(0xFF263746),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFFFC400)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _selectedSides[prop.id] = PickSide.over;
                          });
                          widget.onSelect(
                            _taggedSpecialProp(prop, type),
                            PickSide.over,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: EdgeInsets.zero,
                          foregroundColor: selectedSide == PickSide.over
                              ? Colors.black
                              : const Color(0xFFE6EEF8),
                          backgroundColor: selectedSide == PickSide.over
                              ? const Color(0xFFFFC400)
                              : const Color(0xFF0B1721),
                          side: BorderSide(
                            color: selectedSide == PickSide.over
                                ? const Color(0xFFFFC400)
                                : const Color(0xFF294052),
                          ),
                        ),
                        child: const Text(
                          'OVER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _selectedSides[prop.id] = PickSide.under;
                          });
                          widget.onSelect(
                            _taggedSpecialProp(prop, type),
                            PickSide.under,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: EdgeInsets.zero,
                          foregroundColor: selectedSide == PickSide.under
                              ? Colors.black
                              : const Color(0xFFE6EEF8),
                          backgroundColor: selectedSide == PickSide.under
                              ? const Color(0xFFFFC400)
                              : const Color(0xFF0B1721),
                          side: BorderSide(
                            color: selectedSide == PickSide.under
                                ? const Color(0xFFFFC400)
                                : const Color(0xFF294052),
                          ),
                        ),
                        child: const Text(
                          'UNDER',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PropData _taggedSpecialProp(PropData prop, _SpecialType type) {
    final tag = type == _SpecialType.demon ? 'RED_DEMON' : 'GREEN_GOBLIN';
    final notePrefix =
        'special_type:${type == _SpecialType.demon ? 'demon' : 'goblin'}';
    final nextNote = prop.manualNote.trim().isEmpty
        ? notePrefix
        : '${prop.manualNote} | $notePrefix';

    return PropData(
      id: prop.id,
      eventId: prop.eventId,
      apiSportsGameId: prop.apiSportsGameId,
      playerId: prop.playerId,
      player: prop.player,
      sport: prop.sport,
      matchup: prop.matchup,
      sportsbook: prop.sportsbook,
      market: prop.market,
      marketName: prop.marketName,
      statType: prop.statType,
      category: prop.category,
      propType: prop.propType,
      displayMarket: prop.displayMarket,
      marketKey: prop.marketKey,
      displayTime: prop.displayTime,
      startTimeUtc: prop.startTimeUtc,
      gameStatus: prop.gameStatus,
      sourceProvider: prop.sourceProvider,
      lastUpdatedUtc: prop.lastUpdatedUtc,
      sourcePlayerId: prop.sourcePlayerId,
      canonicalPlayerId: prop.canonicalPlayerId,
      playerIdentityConfidence: prop.playerIdentityConfidence,
      injuryStatus: prop.injuryStatus,
      lineupStatus: prop.lineupStatus,
      projection: prop.projection,
      recommendedSide: prop.recommendedSide,
      confidence: prop.confidence,
      recommendationEdge: prop.recommendationEdge,
      tier: prop.tier,
      pickText: prop.pickText,
      gameTime: prop.gameTime,
      gameStartTime: prop.gameStartTime,
      line: prop.line,
      openingLine: prop.openingLine,
      currentLine: prop.currentLine,
      lineMovedAtUtc: prop.lineMovedAtUtc,
      pick: prop.pick,
      edge: prop.edge,
      imagePath: prop.imagePath,
      customLabel: tag,
      manualNote: nextNote,
      multiplier: prop.multiplier,
      winProbability: prop.winProbability,
      overOdds: prop.overOdds,
      underOdds: prop.underOdds,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFB7BE)),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: const Color(0xFF07131F),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GOBLINS / DEMONS',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _usingFallbackSpecials
                            ? 'Fallback mode: showing strongest/high-risk props --'
                            : 'PrizePicks special lines only --',
                        style: const TextStyle(
                          color: Color(0xFF96A4B2),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _specialIcon(_SpecialType.goblin, size: 20),
                const SizedBox(width: 8),
                _specialIcon(_SpecialType.demon, size: 20),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showHowItWorks,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFC400),
                    side: const BorderSide(color: Color(0xFFFFC400)),
                  ),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('HOW IT WORKS'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () {
                setState(() {
                  _showBuilderTake = !_showBuilderTake;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x6B0A1A2C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF8B6813)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'PROP BUILDER TAKE:',
                      style: TextStyle(
                        color: Color(0xFFFFC400),
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _specialIcon(_SpecialType.goblin, size: 18),
                    const SizedBox(width: 6),
                    _specialIcon(_SpecialType.demon, size: 18),
                    const Spacer(),
                    Icon(
                      _showBuilderTake
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: const Color(0xFFFFC400),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildBuilderTakeDetails(),
              ),
              crossFadeState: _showBuilderTake
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('ALL'),
                      selected: _filter == _SpecialFilter.all,
                      onSelected: (_) =>
                          setState(() => _filter = _SpecialFilter.all),
                    ),
                    ChoiceChip(
                      label: _specialLabel(
                        _SpecialType.goblin,
                        'GREEN GOBLINS',
                      ),
                      selected: _filter == _SpecialFilter.goblin,
                      onSelected: (_) =>
                          setState(() => _filter = _SpecialFilter.goblin),
                    ),
                    ChoiceChip(
                      label: _specialLabel(_SpecialType.demon, 'RED DEMONS'),
                      selected: _filter == _SpecialFilter.demon,
                      onSelected: (_) =>
                          setState(() => _filter = _SpecialFilter.demon),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    const Text(
                      'SORT:',
                      style: TextStyle(
                        color: Color(0xFFB7C2CF),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<_SortMode>(
                      value: _sortMode,
                      dropdownColor: const Color(0xFF0B1D2B),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _sortMode = value;
                        });
                      },
                      items: const [
                        DropdownMenuItem(
                          value: _SortMode.hitRate,
                          child: Text('Hit Rate'),
                        ),
                        DropdownMenuItem(
                          value: _SortMode.edge,
                          child: Text('Edge'),
                        ),
                        DropdownMenuItem(
                          value: _SortMode.startTime,
                          child: Text('Start Time'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _load,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, color: Color(0xFFFFC400)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _sortedVisibleProps.isEmpty
                  ? const Center(
                      child: Text(
                        'No Goblin or Demon props found in the current feed.',
                        style: TextStyle(color: Color(0xFF9AA7B7)),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        int columns;
                        if (constraints.maxWidth >= 980) {
                          columns = 4;
                        } else if (constraints.maxWidth >= 640) {
                          columns = 3;
                        } else if (constraints.maxWidth >= 480) {
                          columns = 2;
                        } else {
                          columns = 1;
                        }

                        return ScrollbarTheme(
                          data: ScrollbarTheme.of(context).copyWith(
                            thumbColor: WidgetStateProperty.resolveWith<Color>((
                              states,
                            ) {
                              if (states.contains(WidgetState.dragged)) {
                                return const Color(0xFFFFD34D);
                              }
                              return const Color(0xFFFFC400);
                            }),
                            trackColor: WidgetStateProperty.all(
                              const Color(0xFF15283A),
                            ),
                            trackBorderColor: WidgetStateProperty.all(
                              const Color(0xFF8B6813),
                            ),
                            thickness: WidgetStateProperty.all(14),
                            radius: const Radius.circular(12),
                          ),
                          child: Scrollbar(
                            controller: _gridScrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            interactive: true,
                            child: GridView.builder(
                              controller: _gridScrollController,
                              padding: const EdgeInsets.only(right: 18),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    mainAxisExtent: 420,
                                  ),
                              itemCount: _sortedVisibleProps.length,
                              itemBuilder: (context, index) {
                                return _buildSpecialPropCard(
                                  _sortedVisibleProps[index],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Showing ${_sortedVisibleProps.length} special props',
                style: const TextStyle(color: Color(0xFF9AA7B7), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
