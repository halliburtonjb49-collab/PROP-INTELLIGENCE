import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/active_slip_controller.dart';
import '../services/api_service.dart';
import 'context_help.dart';

class PropIntelligenceColors {
  static const Color background = Color(0xFF09141D);
  static const Color deepBackground = Color(0xFF0B151E);
  static const Color surface = Color(0xFF111D27);
  static const Color gold = Color(0xFFFFC400);
  static const Color darkGold = Color(0xFF8B6813);
  static const Color divider = Color(0xFF293946);
  static const Color secondaryText = Color(0xFF96A4B2);
  static const Color win = Color(0xFF59E769);
  static const Color loss = Color(0xFFFF4D5A);
}

class ActiveSlipPanel extends StatefulWidget {
  const ActiveSlipPanel({
    super.key,
    required this.controller,
    this.onViewOrLock,
    this.onClear,
    this.isSaving = false,
    this.message,
  });

  final ActiveSlipController controller;
  final Future<void> Function()? onViewOrLock;
  final Future<void> Function()? onClear;
  final bool isSaving;
  final String? message;

  @override
  State<ActiveSlipPanel> createState() => _ActiveSlipPanelState();
}

class _ActiveSlipPanelState extends State<ActiveSlipPanel> {
  final ApiService _apiService = ApiService();
  final double _underdogEntryAmount = 25;
  final double _sleeperEntryAmount = 25;
  final ScrollController _activeSlipScrollController = ScrollController();
  final TextEditingController _entryController = TextEditingController(
    text: '25.00',
  );
  final TextEditingController _underdogEntryController = TextEditingController(
    text: '25.00',
  );
  final TextEditingController _sleeperEntryController = TextEditingController(
    text: '25.00',
  );
  final TextEditingController _fanDuelWagerController = TextEditingController(
    text: '25.00',
  );
  final TextEditingController _draftKingsWagerController =
      TextEditingController(text: '25.00');
  final Set<String> _prefetchedImageUrls = <String>{};
  String _lastPrefetchKey = '';
  Timer? _liveTicketRefreshTimer;
  Map<String, dynamic>? _activeTicketPayload;
  bool _hideRemoteActiveTicket = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshActiveTicket());
    _liveTicketRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshActiveTicket(),
    );
  }

  @override
  void dispose() {
    _liveTicketRefreshTimer?.cancel();
    _activeSlipScrollController.dispose();
    _entryController.dispose();
    _underdogEntryController.dispose();
    _sleeperEntryController.dispose();
    _fanDuelWagerController.dispose();
    _draftKingsWagerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final legs = _displayLegs(widget.controller.legs);
        _prefetchLegImages(legs);
        if (!widget.controller.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.dragged)) {
                return PropIntelligenceColors.gold;
              }
              return PropIntelligenceColors.gold.withValues(alpha: 0.88);
            }),
            trackColor: WidgetStatePropertyAll(
              PropIntelligenceColors.darkGold.withValues(alpha: 0.18),
            ),
            trackBorderColor: const WidgetStatePropertyAll(
              PropIntelligenceColors.darkGold,
            ),
            radius: const Radius.circular(8),
            thickness: const WidgetStatePropertyAll(8),
          ),
          child: Scrollbar(
            controller: _activeSlipScrollController,
            thumbVisibility: true,
            interactive: true,
            child: SingleChildScrollView(
              controller: _activeSlipScrollController,
              primary: false,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_buildSlipBody(legs)],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _refreshActiveTicket() async {
    try {
      final payload = await _apiService.fetchActiveTicket();
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTicketPayload = payload;
      });
    } catch (_) {
      // Keep the current local ticket rendering if live ticket fetch fails.
    }
  }

  List<Map<String, dynamic>> _activeTicketLegs() {
    final rawLegs = _activeTicketPayload?['legs'];
    if (rawLegs is! List) {
      return const [];
    }

    return rawLegs
        .whereType<Map>()
        .map((raw) {
          final leg = Map<String, dynamic>.from(raw);
          return {
            'prop_id':
                leg['prop_id']?.toString() ?? leg['id']?.toString() ?? '',
            'id': leg['id']?.toString() ?? leg['prop_id']?.toString() ?? '',
            'player': leg['player']?.toString() ?? 'Unknown Player',
            'sport': leg['sport']?.toString() ?? '',
            'matchup':
                leg['matchup']?.toString() ?? leg['game']?.toString() ?? '',
            'sportsbook': leg['sportsbook']?.toString() ?? '',
            'prop_site': leg['sportsbook']?.toString() ?? '',
            'market':
                leg['market']?.toString() ?? leg['prop_type']?.toString() ?? '',
            'line': (leg['line'] as num?)?.toDouble() ?? 0,
            'current_line': (leg['line'] as num?)?.toDouble() ?? 0,
            'side': (leg['side']?.toString() ?? '').toUpperCase(),
            'odds': (leg['odds'] as num?)?.toDouble(),
            'current_odds': (leg['odds'] as num?)?.toDouble(),
            'result_value':
                (leg['result_value'] as num?)?.toDouble() ??
                (leg['current'] as num?)?.toDouble(),
            'result_status':
                leg['result_status']?.toString() ??
                leg['result']?.toString() ??
                'pending',
            'game_status': leg['game_status']?.toString() ?? 'scheduled',
            'player_image': leg['player_image']?.toString() ?? '',
            'image_url': leg['player_image']?.toString() ?? '',
          };
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _displayLegs(
    List<Map<String, dynamic>> controllerLegs,
  ) {
    final remoteLegs = _activeTicketLegs();
    if (remoteLegs.isEmpty) {
      return controllerLegs;
    }
    if (controllerLegs.isEmpty) {
      if (_hideRemoteActiveTicket) {
        return const [];
      }
      return remoteLegs;
    }

    final remoteById = <String, Map<String, dynamic>>{};
    final remoteByPlayerMarket = <String, Map<String, dynamic>>{};
    for (final leg in remoteLegs) {
      final id = _propId(leg);
      if (id.isNotEmpty) {
        remoteById[id] = leg;
      }
      final key =
          '${(leg['player'] ?? '').toString().toLowerCase()}|${(leg['market'] ?? '').toString().toLowerCase()}';
      remoteByPlayerMarket[key] = leg;
    }

    return controllerLegs
        .map((leg) {
          final id = _propId(leg);
          final lookupKey =
              '${(leg['player'] ?? '').toString().toLowerCase()}|${(leg['market'] ?? '').toString().toLowerCase()}';
          final remote = remoteById[id] ?? remoteByPlayerMarket[lookupKey];
          if (remote == null) {
            return leg;
          }
          return {
            ...leg,
            'result_value': remote['result_value'] ?? leg['result_value'],
            'result_status': remote['result_status'] ?? leg['result_status'],
            'game_status': remote['game_status'] ?? leg['game_status'],
            'game_completed':
                (remote['game_status']?.toString().toLowerCase() == 'final') ||
                (leg['game_completed'] as bool? ?? false),
          };
        })
        .toList(growable: false);
  }

  void _prefetchLegImages(List<Map<String, dynamic>> legs) {
    final nextKey = legs
        .take(20)
        .map((leg) => '${_propId(leg)}|${_playerImageUrl(leg)}')
        .join('||');
    if (_lastPrefetchKey == nextKey) {
      return;
    }
    _lastPrefetchKey = nextKey;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final leg in legs.take(20)) {
        final imageValue = _playerImageUrl(leg);
        if (imageValue.isEmpty ||
            imageValue.startsWith('assets/') ||
            _prefetchedImageUrls.contains(imageValue)) {
          continue;
        }
        _prefetchedImageUrls.add(imageValue);
        precacheImage(CachedNetworkImageProvider(imageValue), context);
      }
    });
  }

  Future<void> _viewOrLockSlip() async {
    if (widget.onViewOrLock == null) {
      return;
    }
    await widget.onViewOrLock!();
  }

  Future<void> _clearSlip() async {
    if (mounted) {
      setState(() {
        _hideRemoteActiveTicket = true;
        _activeTicketPayload = null;
      });
    }
    if (widget.onClear != null) {
      await widget.onClear!();
      return;
    }
    await widget.controller.clear();
  }

  Widget _buildSlipBody(List<Map<String, dynamic>> legs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_buildSiteSpecificSlip(legs)],
    );
  }

  String _propId(Map<String, dynamic> leg) {
    return leg['prop_id']?.toString() ?? leg['id']?.toString() ?? '';
  }

  String _normalizeSport(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('UFC') ||
        normalized.contains('MMA') ||
        normalized.contains('ULTIMATEFIGHTING')) {
      return 'UFC';
    }
    if (normalized.contains('WNBA')) {
      return 'WNBA';
    }
    if (normalized.contains('NBA')) {
      return 'NBA';
    }
    if (normalized.contains('NFL') || normalized.contains('FOOTBALL')) {
      return 'NFL';
    }
    if (normalized.contains('MLB') || normalized.contains('BASEBALL')) {
      return 'MLB';
    }
    if (normalized.contains('SOCCER') ||
        normalized.contains('EPL') ||
        normalized.contains('MLS')) {
      return 'SOCCER';
    }
    if (normalized.contains('TENNIS') ||
        normalized.contains('ATP') ||
        normalized.contains('WTA')) {
      return 'TENNIS';
    }
    if (normalized.contains('PGA') || normalized.contains('GOLF')) {
      return 'PGA';
    }
    return normalized;
  }

  String _propMarket(Map<String, dynamic> prop) {
    return (prop['market'] ??
            prop['market_name'] ??
            prop['stat_type'] ??
            prop['category'] ??
            prop['prop_type'] ??
            prop['display_market'] ??
            prop['market_key'] ??
            prop['bet_type'] ??
            '')
        .toString();
  }

  String _resolveImageUrl(String value) {
    if (value.isEmpty) {
      return '';
    }
    if (value.startsWith('assets/')) {
      return value;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final baseUrl = ApiService.baseUrl;
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = value.startsWith('/') ? value : '/$value';
    return '$normalizedBase$normalizedPath';
  }

  String _playerImageUrl(Map<String, dynamic> prop) {
    final value =
        prop['player_image'] ??
        prop['image_url'] ??
        prop['headshot'] ??
        prop['photo_url'] ??
        prop['player_photo'] ??
        prop['avatar'] ??
        prop['image_path'] ??
        prop['imagePath'] ??
        '';
    return _resolveImageUrl(value.toString().trim());
  }

  Widget _playerInitials(String name) {
    final cleaned = name.trim();
    final initials = cleaned.isEmpty
        ? '?'
        : cleaned
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part[0].toUpperCase())
              .join();
    return Container(
      alignment: Alignment.center,
      color: PropIntelligenceColors.surface,
      child: Text(
        initials,
        style: const TextStyle(
          color: PropIntelligenceColors.gold,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _playerPhoto(Map<String, dynamic> prop, {double size = 44}) {
    final imageUrl = _playerImageUrl(prop);
    final playerName = (prop['player'] ?? prop['player_name'] ?? '?')
        .toString();

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: PropIntelligenceColors.gold,
                  width: 1.3,
                ),
              ),
              child: ClipOval(
                child: imageUrl.isEmpty
                    ? _playerInitials(playerName)
                    : imageUrl.startsWith('assets/')
                    ? Image.asset(
                        imageUrl,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stackTrace) {
                          return _playerInitials(playerName);
                        },
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        memCacheWidth: (size * 2).round(),
                        memCacheHeight: (size * 2).round(),
                        useOldImageOnUrlChange: true,
                        placeholder: (context, url) {
                          return _playerInitials(playerName);
                        },
                        errorWidget: (context, url, error) {
                          return _playerInitials(playerName);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sportIcon(String rawSport, {double size = 17}) {
    final sport = _normalizeSport(rawSport);
    switch (sport) {
      case 'NBA':
      case 'WNBA':
        return Icon(
          Icons.sports_basketball,
          size: size,
          color: PropIntelligenceColors.gold,
        );
      case 'NFL':
        return Icon(
          Icons.sports_football,
          size: size,
          color: PropIntelligenceColors.gold,
        );
      case 'MLB':
        return Icon(
          Icons.sports_baseball,
          size: size,
          color: PropIntelligenceColors.gold,
        );
      case 'SOCCER':
        return Icon(
          Icons.sports_soccer,
          size: size,
          color: PropIntelligenceColors.gold,
        );
      case 'TENNIS':
        return Icon(
          Icons.sports_tennis,
          size: size,
          color: PropIntelligenceColors.gold,
        );
      case 'PGA':
        return Icon(
          Icons.sports_golf,
          size: size,
          color: const Color(0xFF9A6338),
        );
      case 'UFC':
        return Icon(
          Icons.sports_mma,
          size: size,
          color: const Color(0xFF9A6338),
        );
      default:
        return Icon(
          Icons.sports,
          size: size,
          color: PropIntelligenceColors.secondaryText,
        );
    }
  }

  String _displayMarket(Map<String, dynamic> leg) {
    final market = _propMarket(leg);
    return market.replaceAll('_', ' ').toUpperCase();
  }

  String _displaySideAndLine(Map<String, dynamic> leg) {
    final pickText =
        leg['pick_text']?.toString().trim() ??
        leg['pickText']?.toString().trim() ??
        '';
    if (pickText.isNotEmpty) {
      return pickText;
    }

    final side = leg['side']?.toString().toUpperCase() ?? '';
    final line = leg['current_line'] ?? leg['line'] ?? '';
    return '$side $line';
  }

  String _prizePicksSide(Map<String, dynamic> leg) {
    final side = leg['side']?.toString().toUpperCase() ?? '';
    if (side == 'OVER') {
      return 'MORE';
    }
    if (side == 'UNDER') {
      return 'LESS';
    }
    return side;
  }

  String _underdogSide(Map<String, dynamic> leg) {
    final side = leg['side']?.toString().toUpperCase() ?? '';
    if (side == 'OVER') {
      return 'HIGHER';
    }
    if (side == 'UNDER') {
      return 'LOWER';
    }
    return side;
  }

  String _sleeperSide(Map<String, dynamic> leg) {
    final side = leg['side']?.toString().toUpperCase() ?? '';
    if (side == 'OVER') {
      return 'MORE';
    }
    if (side == 'UNDER') {
      return 'LESS';
    }
    return side;
  }

  String _formatOdds(dynamic rawOdds) {
    final odds = rawOdds is num
        ? rawOdds.toInt()
        : int.tryParse(rawOdds?.toString() ?? '') ?? 0;
    if (odds == 0) {
      return '--';
    }
    return odds > 0 ? '+$odds' : '$odds';
  }

  double _decimalOddsFromAmerican(int odds) {
    if (odds == 0) {
      return 1;
    }
    if (odds > 0) {
      return 1 + odds / 100;
    }
    return 1 + 100 / odds.abs();
  }

  int _americanOdds(Map<String, dynamic> leg) {
    final raw = leg['current_odds'] ?? leg['odds'] ?? -110;
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw.toString()) ?? -110;
  }

  String _formatAmericanOdds(int odds) {
    return odds > 0 ? '+$odds' : '$odds';
  }

  double _americanToDecimal(int odds) {
    if (odds > 0) {
      return 1 + odds / 100;
    }
    return 1 + 100 / odds.abs();
  }

  double _fanDuelCombinedDecimal(List<Map<String, dynamic>> legs) {
    var total = 1.0;
    for (final leg in legs) {
      total *= _americanToDecimal(_americanOdds(leg));
    }
    return total;
  }

  double _draftKingsCombinedDecimal(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return 1.0;
    }
    var total = 1.0;
    for (final leg in legs) {
      total *= _americanToDecimal(_americanOdds(leg));
    }
    return total;
  }

  int _draftKingsCombinedAmerican(List<Map<String, dynamic>> legs) {
    return _decimalToAmerican(_draftKingsCombinedDecimal(legs));
  }

  String _draftKingsTicketStatus(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return 'EMPTY';
    }
    final statuses = legs.map((leg) {
      return leg['result_status']?.toString().toLowerCase() ?? 'pending';
    }).toList();
    if (statuses.any((status) => status == 'lost')) {
      return 'LOST';
    }
    if (statuses.every((status) => status == 'won' || status == 'push')) {
      return 'WON';
    }
    if (statuses.any((status) => status == 'live' || status == 'in_progress')) {
      return 'LIVE';
    }
    return 'OPEN';
  }

  int _decimalToAmerican(double decimalOdds) {
    if (decimalOdds <= 1) {
      return 0;
    }
    if (decimalOdds >= 2) {
      return ((decimalOdds - 1) * 100).round();
    }
    return (-100 / (decimalOdds - 1)).round();
  }

  bool _isSameGameParlay(List<Map<String, dynamic>> legs) {
    if (legs.length < 2) {
      return false;
    }
    final eventIds = legs
        .map((leg) => leg['event_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    return eventIds.length == 1;
  }

  double _underdogMultiplier(int legCount) {
    switch (legCount) {
      case 2:
        return 3;
      case 3:
        return 6;
      case 4:
        return 10;
      case 5:
        return 20;
      case 6:
        return 40;
      default:
        return 1;
    }
  }

  double _sleeperLegMultiplier(Map<String, dynamic> leg) {
    double? asDouble(dynamic rawValue) {
      if (rawValue is num) {
        return rawValue.toDouble();
      }
      return double.tryParse(rawValue?.toString() ?? '');
    }

    final rawValue =
        leg['multiplier'] ??
        leg['pick_multiplier'] ??
        leg['payout_multiplier'] ??
        leg['decimal_multiplier'];
    if (rawValue is num) {
      return rawValue.toDouble();
    }
    final parsed = double.tryParse(rawValue?.toString() ?? '');
    if (parsed != null && parsed > 0) {
      return parsed;
    }

    final side = leg['side']?.toString().toUpperCase() ?? '';
    final sideOdds = side == 'UNDER'
        ? asDouble(leg['under_odds'] ?? leg['underOdds'])
        : asDouble(leg['over_odds'] ?? leg['overOdds']);
    final fallbackOdds =
        asDouble(leg['current_odds']) ?? asDouble(leg['odds']) ?? sideOdds;

    if (fallbackOdds != null) {
      return _decimalOddsFromAmerican(fallbackOdds.toInt());
    }

    final rawWinProbability =
        asDouble(leg['win_probability']) ?? asDouble(leg['winProbability']);
    if (rawWinProbability != null && rawWinProbability > 0) {
      final normalizedProbability = rawWinProbability > 1
          ? (rawWinProbability / 100).clamp(0.0001, 1.0)
          : rawWinProbability.clamp(0.0001, 1.0);
      return 1 / normalizedProbability;
    }

    return 1.5;
  }

  double _sleeperTotalMultiplier(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return 1;
    }
    var total = 1.0;
    for (final leg in legs) {
      total *= _sleeperLegMultiplier(leg);
    }
    return total;
  }

  double _sleeperPayout(List<Map<String, dynamic>> legs) {
    return _sleeperEntryAmount * _sleeperTotalMultiplier(legs);
  }

  Widget _buildTicketLeg({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final site =
        leg['prop_site']?.toString() ?? leg['sportsbook']?.toString() ?? '';
    final edge = (leg['edge'] as num?)?.toDouble() ?? 0;
    final confidence = (leg['confidence'] as num?)?.toDouble() ?? 0;
    final odds = leg['current_odds'] ?? leg['odds'];

    return Container(
      key: ValueKey(_propId(leg)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF283744))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(top: 9, right: 8),
              child: Icon(
                Icons.drag_indicator,
                color: Color(0xFFBAC4D0),
                size: 20,
              ),
            ),
          ),
          _playerPhoto(leg, size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _displayMarket(leg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFB8C1CC), fontSize: 9),
                ),
                const SizedBox(height: 3),
                Text(
                  _displaySideAndLine(leg),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        site.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFC400),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Edge ${edge.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Color(0xFF62D47A),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Model ${confidence.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Color(0xFFB8C1CC),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatOdds(odds),
                style: const TextStyle(
                  color: Color(0xFFFFC400),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              IconButton(
                tooltip: 'Remove prop',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  widget.controller.removeLeg(_propId(leg));
                },
                icon: const Icon(
                  Icons.close,
                  color: Color(0xFFD6D2DC),
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTicketHeader(List<Map<String, dynamic>> legs) {
    final label = legs.length == 1
        ? 'SINGLE PICK'
        : '${legs.length} LEG PARLAY';
    final sport = legs.isEmpty ? '' : (legs.first['sport'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A3946))),
      ),
      child: Row(
        children: [
          _sportIcon(sport),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: legs.isEmpty ? null : _clearSlip,
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
              color: PropIntelligenceColors.gold,
            ),
            label: const Text('CLEAR SLIP'),
          ),
        ],
      ),
    );
  }

  Widget _buildPrizePicksHeader(List<Map<String, dynamic>> legs) {
    final sport = legs.isEmpty
        ? ''
        : (legs.first['sport'] ?? legs.first['league'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF201A06),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: PropIntelligenceColors.gold),
                ),
                child: _sportIcon(sport, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${legs.length}-PICK ENTRY',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Choose Power/Flex on Lock Slip',
                      style: TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear slip',
                onPressed: legs.isEmpty ? null : _clearSlip,
                color: PropIntelligenceColors.gold,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnderdogHeader(List<Map<String, dynamic>> legs) {
    final multiplier = _underdogMultiplier(legs.length);
    final payout = _underdogEntryAmount * multiplier;
    final sport = legs.isEmpty
        ? ''
        : (legs.first['sport'] ?? legs.first['league'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF201A06),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: PropIntelligenceColors.gold),
            ),
            child: _sportIcon(sport, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${legs.length}-PICK ENTRY',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${multiplier.toStringAsFixed(multiplier % 1 == 0 ? 0 : 2)}x MULTIPLIER',
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'TO WIN',
                style: TextStyle(color: Color(0xFF96A4B2), fontSize: 8),
              ),
              Text(
                '\$${payout.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFFFC400),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(width: 5),
          IconButton(
            tooltip: 'Clear entry',
            onPressed: legs.isEmpty ? null : _clearSlip,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildSleeperHeader(List<Map<String, dynamic>> legs) {
    final totalMultiplier = _sleeperTotalMultiplier(legs);
    final payout = _sleeperPayout(legs);
    final sport = legs.isEmpty
        ? ''
        : (legs.first['sport'] ?? legs.first['league'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF201A06),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: PropIntelligenceColors.gold),
            ),
            child: _sportIcon(sport, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${legs.length}-PICK ENTRY',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${totalMultiplier.toStringAsFixed(2)}x TOTAL MULTIPLIER',
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'PAYOUT',
                style: TextStyle(color: Color(0xFF96A4B2), fontSize: 8),
              ),
              Text(
                '\$${payout.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFFFC400),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(width: 5),
          IconButton(
            tooltip: 'Clear entry',
            onPressed: legs.isEmpty ? null : _clearSlip,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildPrizePicksLeg({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final market = _displayMarket(leg);
    final sport = (leg['sport'] ?? leg['league'] ?? '').toString();
    final lineValue = leg['current_line'] ?? leg['line'] ?? '';
    final lineNumber = lineValue is num
        ? lineValue.toDouble()
        : double.tryParse(lineValue.toString()) ?? 0;
    final resultValue = (leg['result_value'] as num?)?.toDouble();
    final resultStatus =
        leg['result_status']?.toString().toLowerCase() ?? 'pending';
    final progress = resultValue == null || lineNumber == 0
        ? 0.0
        : (resultValue / lineNumber).clamp(0.0, 1.0);

    Color progressColor;
    switch (resultStatus) {
      case 'won':
        progressColor = const Color(0xFF59E769);
        break;
      case 'lost':
        progressColor = const Color(0xFFFF4D5A);
        break;
      default:
        progressColor = const Color(0xFFFFC400);
    }

    return Container(
      key: ValueKey(_propId(leg).isEmpty ? 'leg-$index' : _propId(leg)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 7),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: Color(0xFF8997A5),
                  ),
                ),
              ),
              _playerPhoto(leg, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _sportIcon(sport, size: 10),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            market,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF151D27),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFF354754)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_prizePicksSide(leg)} $lineValue',
                      style: const TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      market,
                      style: const TextStyle(color: Colors.white, fontSize: 8),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              IconButton(
                tooltip: 'Remove pick',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  widget.controller.removeLeg(_propId(leg));
                },
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: const Color(0xFF2B3540),
              valueColor: AlwaysStoppedAnimation(progressColor),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  resultStatus == 'pending'
                      ? 'PENDING'
                      : resultStatus.toUpperCase(),
                  style: TextStyle(
                    color: progressColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                resultValue == null ? '--' : resultValue.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isRivalsPick(Map<String, dynamic> leg) {
    return leg['pick_type']?.toString().toUpperCase() == 'RIVALS' ||
        leg['rival_player'] != null;
  }

  Widget _buildUnderdogLeg({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final market = _displayMarket(leg);
    final lineValue = leg['current_line'] ?? leg['line'] ?? '';
    final sport = (leg['sport'] ?? leg['league'] ?? '').toString();
    final matchup = leg['matchup']?.toString() ?? '';
    final resultValue = (leg['result_value'] as num?)?.toDouble();
    final resultStatus =
        leg['result_status']?.toString().toLowerCase() ?? 'pending';
    final target = lineValue is num
        ? lineValue.toDouble()
        : double.tryParse(lineValue.toString()) ?? 1;
    final progress = resultValue == null
        ? 0.0
        : (resultValue / target).clamp(0.0, 1.0);

    Color statusColor;
    switch (resultStatus) {
      case 'won':
        statusColor = const Color(0xFF59E769);
        break;
      case 'lost':
        statusColor = const Color(0xFFFF4D5A);
        break;
      default:
        statusColor = const Color(0xFFFFC400);
    }

    return Container(
      key: ValueKey(_propId(leg).isEmpty ? 'leg-$index' : _propId(leg)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 7),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: Color(0xFF8997A5),
                  ),
                ),
              ),
              _playerPhoto(leg, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sport • $matchup',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF96A4B2),
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_underdogSide(leg)} $lineValue',
                      style: const TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Row(
                      children: [
                        _sportIcon(sport, size: 10),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            market,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isRivalsPick(leg)) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF211C0B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B6813)),
                        ),
                        child: Text(
                          'RIVALS vs ${leg['rival_player'] ?? ''}',
                          style: const TextStyle(
                            color: Color(0xFFFFC400),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove pick',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  widget.controller.removeLeg(_propId(leg));
                },
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: const Color(0xFF2B3540),
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  resultStatus == 'pending'
                      ? 'LIVE TRACKING'
                      : resultStatus.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                resultValue == null ? '--' : resultValue.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSleeperLeg({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final market = _displayMarket(leg);
    final lineValue = leg['current_line'] ?? leg['line'] ?? '';
    final sport = (leg['sport'] ?? leg['league'] ?? '').toString();
    final matchup = leg['matchup']?.toString() ?? '';
    final multiplier = _sleeperLegMultiplier(leg);
    final resultValue = (leg['result_value'] as num?)?.toDouble();
    final resultStatus =
        leg['result_status']?.toString().toLowerCase() ?? 'pending';
    final winProbability =
        (leg['win_probability'] as num?)?.toDouble() ??
        (leg['confidence'] as num?)?.toDouble() ??
        0;

    Color statusColor;
    switch (resultStatus) {
      case 'won':
        statusColor = const Color(0xFF59E769);
        break;
      case 'lost':
        statusColor = const Color(0xFFFF4D5A);
        break;
      default:
        statusColor = const Color(0xFFFFC400);
    }

    return Container(
      key: ValueKey(_propId(leg).isEmpty ? 'leg-$index' : _propId(leg)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 7),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: Color(0xFF8997A5),
                  ),
                ),
              ),
              _playerPhoto(leg, size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sport • $matchup',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF96A4B2),
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_sleeperSide(leg)} $lineValue',
                      style: const TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Row(
                      children: [
                        _sportIcon(sport, size: 10),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            market,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF211C0B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF8B6813)),
                ),
                child: Column(
                  children: [
                    Text(
                      '${multiplier.toStringAsFixed(2)}x',
                      style: const TextStyle(
                        color: Color(0xFFFFC400),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'MULTIPLIER',
                      style: TextStyle(color: Color(0xFF96A4B2), fontSize: 6.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Remove pick',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  widget.controller.removeLeg(_propId(leg));
                },
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'WIN PROBABILITY',
                  style: TextStyle(color: Color(0xFF96A4B2), fontSize: 8),
                ),
              ),
              Text(
                '${winProbability.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (winProbability / 100).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFF2B3540),
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  resultStatus == 'pending'
                      ? 'LIVE TRACKING'
                      : resultStatus.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                resultValue == null ? '--' : resultValue.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrizePicksFooter(List<Map<String, dynamic>> legs) {
    return _buildLockOnlyFooter(legs, label: 'VIEW / LOCK ENTRY');
  }

  Widget _buildUnderdogFooter(List<Map<String, dynamic>> legs) {
    return _buildLockOnlyFooter(legs, label: 'VIEW / LOCK ENTRY');
  }

  Widget _buildSleeperFooter(List<Map<String, dynamic>> legs) {
    return _buildLockOnlyFooter(legs, label: 'VIEW / LOCK ENTRY');
  }

  Widget _buildFanDuelHeader(List<Map<String, dynamic>> legs) {
    final isSgp = _isSameGameParlay(legs);
    final combinedDecimal = _fanDuelCombinedDecimal(legs);
    final combinedAmerican = _decimalToAmerican(combinedDecimal);
    final sport = legs.isEmpty
        ? ''
        : (legs.first['sport'] ?? legs.first['league'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF201A06),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: PropIntelligenceColors.gold),
            ),
            child: _sportIcon(sport, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  legs.length == 1
                      ? 'STRAIGHT BET'
                      : isSgp
                      ? 'SAME GAME PARLAY'
                      : '${legs.length}-LEG PARLAY',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAmericanOdds(combinedAmerican),
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (isSgp)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF211C0B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF8B6813)),
              ),
              child: const Text(
                'SGP',
                style: TextStyle(
                  color: Color(0xFFFFC400),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Clear bet slip',
            onPressed: legs.isEmpty ? null : _clearSlip,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildFanDuelLeg({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final market = _displayMarket(leg);
    final sport = (leg['sport'] ?? leg['league'] ?? '').toString();
    final side = leg['side']?.toString().toUpperCase() ?? '';
    final line = leg['current_line'] ?? leg['line'] ?? '';
    final matchup = leg['matchup']?.toString() ?? '';
    final odds = _americanOdds(leg);
    final resultStatus =
        leg['result_status']?.toString().toLowerCase() ?? 'pending';
    final resultValue = (leg['result_value'] as num?)?.toDouble();

    Color statusColor;
    switch (resultStatus) {
      case 'won':
        statusColor = const Color(0xFF59E769);
        break;
      case 'lost':
        statusColor = const Color(0xFFFF4D5A);
        break;
      case 'push':
        statusColor = const Color(0xFFFFC400);
        break;
      default:
        statusColor = const Color(0xFF96A4B2);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF293946))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(right: 7, top: 12),
              child: Icon(
                Icons.drag_indicator,
                size: 18,
                color: Color(0xFF8997A5),
              ),
            ),
          ),
          _playerPhoto(leg, size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  matchup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF96A4B2), fontSize: 8),
                ),
                const SizedBox(height: 4),
                Text(
                  '$side $line',
                  style: const TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Row(
                  children: [
                    _sportIcon(sport, size: 10),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        market,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (resultStatus != 'pending') ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        resultStatus == 'won'
                            ? Icons.check_circle
                            : resultStatus == 'lost'
                            ? Icons.cancel
                            : Icons.remove_circle,
                        size: 14,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        resultValue == null
                            ? resultStatus.toUpperCase()
                            : '${resultStatus.toUpperCase()} ${resultValue.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatAmericanOdds(odds),
                style: const TextStyle(
                  color: Color(0xFFFFC400),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              IconButton(
                tooltip: 'Remove leg',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  widget.controller.removeLeg(_propId(leg));
                },
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fanDuelTicketStatus(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return 'PENDING';
    }
    final statuses = legs
        .map(
          (leg) => leg['result_status']?.toString().toLowerCase() ?? 'pending',
        )
        .toList();
    if (statuses.any((status) => status == 'lost')) {
      return 'LOST';
    }
    if (statuses.every((status) => status == 'won' || status == 'push')) {
      return 'WON';
    }
    return 'OPEN';
  }

  Widget _buildFanDuelStatusBanner(List<Map<String, dynamic>> legs) {
    final status = _fanDuelTicketStatus(legs);
    Color backgroundColor;
    Color textColor;
    switch (status) {
      case 'WON':
        backgroundColor = const Color(0xFF3A2E0B);
        textColor = const Color(0xFFF2BC35);
        break;
      case 'LOST':
        backgroundColor = const Color(0xFF16263D);
        textColor = const Color(0xFF63A8FF);
        break;
      default:
        backgroundColor = const Color(0xFF211C0B);
        textColor = const Color(0xFFFFC400);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7),
      color: backgroundColor,
      alignment: Alignment.center,
      child: Text(
        status,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildFanDuelFooter(List<Map<String, dynamic>> legs) {
    return _buildLockOnlyFooter(legs, label: 'VIEW / LOCK BET');
  }

  Widget _buildDraftKingsTabs(List<Map<String, dynamic>> legs) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PropIntelligenceColors.deepBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: PropIntelligenceColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PropIntelligenceColors.gold,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                'BETSLIP',
                style: TextStyle(
                  color: PropIntelligenceColors.deepBackground,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FilledButton(
              onPressed: legs.isEmpty ? null : _clearSlip,
              style: FilledButton.styleFrom(
                backgroundColor: PropIntelligenceColors.gold,
                foregroundColor: PropIntelligenceColors.deepBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'CLEAR',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftKingsHeader(List<Map<String, dynamic>> legs) {
    final combinedOdds = _draftKingsCombinedAmerican(legs);
    final status = _draftKingsTicketStatus(legs);
    final sport = legs.isEmpty
        ? ''
        : (legs.first['sport'] ?? legs.first['league'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: PropIntelligenceColors.divider),
        ),
      ),
      child: Column(
        children: [
          _buildDraftKingsTabs(legs),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF211C0B),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: PropIntelligenceColors.gold),
                ),
                child: _sportIcon(sport, size: 18),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      legs.length == 1
                          ? 'STRAIGHT BET'
                          : '${legs.length}-LEG PARLAY',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatAmericanOdds(combinedOdds),
                      style: const TextStyle(
                        color: PropIntelligenceColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDraftKingsStatusBadge(status),
              const SizedBox(width: 3),
              IconButton(
                tooltip: 'Clear bet slip',
                visualDensity: VisualDensity.compact,
                onPressed: legs.isEmpty ? null : _clearSlip,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDraftKingsStatusBadge(String status) {
    Color foreground;
    Color background;
    switch (status) {
      case 'WON':
        foreground = PropIntelligenceColors.gold;
        background = const Color(0xFF3A2E0B);
        break;
      case 'LOST':
        foreground = const Color(0xFF63A8FF);
        background = const Color(0xFF16263D);
        break;
      case 'LIVE':
        foreground = PropIntelligenceColors.gold;
        background = const Color(0xFF3A2E0B);
        break;
      default:
        foreground = Colors.white;
        background = PropIntelligenceColors.surface;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: foreground.withValues(alpha: 0.55)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildDraftKingsLeg({
    required Map<String, dynamic> leg,
    required int index,
  }) {
    final player = leg['player']?.toString() ?? 'Unknown Player';
    final market = _displayMarket(leg);
    final sport = (leg['sport'] ?? leg['league'] ?? '').toString();
    final side = leg['side']?.toString().toUpperCase() ?? '';
    final line = leg['current_line'] ?? leg['line'] ?? '';
    final matchup =
        leg['matchup']?.toString() ?? leg['event_name']?.toString() ?? '';
    final odds = _americanOdds(leg);
    final resultStatus =
        leg['result_status']?.toString().toLowerCase() ?? 'pending';
    final resultValue = double.tryParse(leg['result_value']?.toString() ?? '');

    Color statusColor;
    switch (resultStatus) {
      case 'won':
        statusColor = PropIntelligenceColors.win;
        break;
      case 'lost':
        statusColor = PropIntelligenceColors.loss;
        break;
      case 'push':
        statusColor = PropIntelligenceColors.gold;
        break;
      default:
        statusColor = PropIntelligenceColors.secondaryText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: PropIntelligenceColors.divider),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(right: 6, top: 12),
              child: Icon(
                Icons.drag_indicator,
                size: 17,
                color: PropIntelligenceColors.secondaryText,
              ),
            ),
          ),
          _playerPhoto(leg, size: 40),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  matchup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PropIntelligenceColors.secondaryText,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$side $line',
                  style: const TextStyle(
                    color: PropIntelligenceColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Row(
                  children: [
                    _sportIcon(sport, size: 10),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        market,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (resultStatus != 'pending') ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        resultStatus == 'won'
                            ? Icons.check_circle
                            : resultStatus == 'lost'
                            ? Icons.cancel
                            : Icons.remove_circle,
                        size: 13,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        resultValue == null
                            ? resultStatus.toUpperCase()
                            : '${resultStatus.toUpperCase()} ${resultValue.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 49,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatAmericanOdds(odds),
                    maxLines: 1,
                    style: const TextStyle(
                      color: PropIntelligenceColors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                IconButton(
                  tooltip: 'Remove leg',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    widget.controller.removeLeg(_propId(leg));
                  },
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double? _draftKingsCashOutOffer(List<Map<String, dynamic>> legs) {
    for (final leg in legs) {
      final raw =
          leg['cash_out_offer'] ??
          leg['cashout_offer'] ??
          leg['cash_out_value'];
      final parsed = double.tryParse(raw?.toString() ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  Widget _buildDraftKingsCashOut(List<Map<String, dynamic>> legs) {
    final offer = _draftKingsCashOutOffer(legs);
    if (offer == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(11, 10, 11, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF112D1D),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: PropIntelligenceColors.win),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            color: PropIntelligenceColors.win,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CASH OUT OFFER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '\$${offer.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: PropIntelligenceColors.win,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              _showCashOutDetails(offer);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: PropIntelligenceColors.win,
              side: const BorderSide(color: PropIntelligenceColors.win),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'VIEW',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  void _showCashOutDetails(double offer) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: PropIntelligenceColors.surface,
          title: const Text(
            'Cash Out Offer',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Current tracked cash-out offer: '
            '\$${offer.toStringAsFixed(2)}.\n\n'
            'Complete the actual cash out '
            'inside DraftKings.',
            style: const TextStyle(color: PropIntelligenceColors.secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDraftKingsFooter(List<Map<String, dynamic>> legs) {
    return _buildLockOnlyFooter(legs, label: 'LOCK ENTRY');
  }

  Widget _buildLockOnlyFooter(
    List<Map<String, dynamic>> legs, {
    required String label,
  }) {
    final site = _activeSlipSite(legs);
    final minimumLegs =
        (site.contains('PRIZEPICKS') ||
            site.contains('UNDERDOG') ||
            site.contains('SLEEPER'))
        ? 2
        : 1;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 42,
        width: double.infinity,
        child: FilledButton(
          onPressed:
              legs.length < minimumLegs ||
                  widget.isSaving ||
                  widget.onViewOrLock == null
              ? null
              : _viewOrLockSlip,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE7A713),
            foregroundColor: const Color(0xFF050A0F),
          ),
          child: widget.isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFanDuelStyleSlip(List<Map<String, dynamic>> legs) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF09141D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFanDuelStatusBanner(legs),
          _buildFanDuelHeader(legs),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: legs.length,
            onReorderItem: widget.controller.reorder,
            itemBuilder: (context, index) {
              final leg = legs[index];
              return RepaintBoundary(
                key: ValueKey(leg['prop_id'] ?? 'leg-$index'),
                child: _buildFanDuelLeg(leg: leg, index: index),
              );
            },
          ),
          _buildFanDuelFooter(legs),
        ],
      ),
    );
  }

  Widget _buildDraftKingsStyleSlip(List<Map<String, dynamic>> legs) {
    return Container(
      decoration: BoxDecoration(
        color: PropIntelligenceColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PropIntelligenceColors.darkGold),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDraftKingsHeader(legs),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: legs.length,
            onReorderItem: widget.controller.reorder,
            itemBuilder: (context, index) {
              final leg = legs[index];
              return RepaintBoundary(
                key: ValueKey(leg['prop_id'] ?? 'draft-kings-$index'),
                child: _buildDraftKingsLeg(leg: leg, index: index),
              );
            },
          ),
          _buildDraftKingsCashOut(legs),
          _buildDraftKingsFooter(legs),
        ],
      ),
    );
  }

  Widget _buildTicketPayout(List<Map<String, dynamic>> legs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _entryController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              labelText: 'ENTRY',
              prefixText: r'$ ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.message!.contains('successfully')
                    ? const Color(0xFFFFC400)
                    : const Color(0xFFFF9EA6),
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              onPressed:
                  legs.isEmpty || widget.isSaving || widget.onViewOrLock == null
                  ? null
                  : widget.onViewOrLock,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE9A713),
                foregroundColor: const Color(0xFF070B10),
              ),
              child: widget.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'VIEW / LOCK SLIP',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyActiveSlip() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF344654)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 44),
            SizedBox(height: 12),
            Text(
              'Your active slip is ready to build',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              '1. Select a prop  •  2. Choose Over or Under  •  3. Review and lock',
              style: TextStyle(
                color: PropIntelligenceColors.secondaryText,
                fontSize: 11,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTicket(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return _buildEmptyActiveSlip();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101A23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PropIntelligenceColors.gold.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF16110A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFF6D5220))),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  color: PropIntelligenceColors.gold,
                  size: 15,
                ),
                SizedBox(width: 8),
                Text(
                  'TICKET SLIP',
                  style: TextStyle(
                    color: PropIntelligenceColors.gold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                Spacer(),
                ContextHelp(
                  title: 'Active slip',
                  message:
                      'Your active slip is a research workspace. Drag legs to reorder them, review edge and model confidence, remove unwanted props, then lock the slip when your selections and live lines are confirmed.',
                ),
              ],
            ),
          ),
          _buildTicketHeader(legs),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: legs.length,
            onReorderItem: widget.controller.reorder,
            itemBuilder: (context, index) {
              final leg = legs[index];
              return RepaintBoundary(
                key: ValueKey(
                  _propId(leg).isEmpty ? 'leg-$index' : _propId(leg),
                ),
                child: _buildTicketLeg(leg: leg, index: index),
              );
            },
          ),
          _buildTicketPayout(legs),
        ],
      ),
    );
  }

  Widget _buildPrizePicksStyleSlip(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return _buildEmptyActiveSlip();
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF09141D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPrizePicksHeader(legs),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: legs.length,
            onReorderItem: widget.controller.reorder,
            itemBuilder: (context, index) {
              final leg = legs[index];
              return RepaintBoundary(
                key: ValueKey(
                  _propId(leg).isEmpty ? 'leg-$index' : _propId(leg),
                ),
                child: _buildPrizePicksLeg(leg: leg, index: index),
              );
            },
          ),
          _buildPrizePicksFooter(legs),
        ],
      ),
    );
  }

  Widget _buildUnderdogStyleSlip(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return _buildEmptyActiveSlip();
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF09141D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildUnderdogHeader(legs),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: legs.length,
            onReorderItem: widget.controller.reorder,
            itemBuilder: (context, index) {
              final leg = legs[index];
              return RepaintBoundary(
                key: ValueKey(
                  _propId(leg).isEmpty ? 'leg-$index' : _propId(leg),
                ),
                child: _buildUnderdogLeg(leg: leg, index: index),
              );
            },
          ),
          _buildUnderdogFooter(legs),
        ],
      ),
    );
  }

  Widget _buildSleeperStyleSlip(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return _buildEmptyActiveSlip();
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF09141D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSleeperHeader(legs),
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: legs.length,
            onReorderItem: widget.controller.reorder,
            itemBuilder: (context, index) {
              final leg = legs[index];
              return RepaintBoundary(
                key: ValueKey(
                  _propId(leg).isEmpty ? 'leg-$index' : _propId(leg),
                ),
                child: _buildSleeperLeg(leg: leg, index: index),
              );
            },
          ),
          _buildSleeperFooter(legs),
        ],
      ),
    );
  }

  String _normalizeSite(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('PRIZEPICKS')) {
      return 'PRIZEPICKS';
    }
    if (normalized.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    if (normalized.contains('SLEEPER')) {
      return 'SLEEPER';
    }
    if (normalized.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (normalized.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    return normalized;
  }

  String _activeSlipSite(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return '';
    }
    final leg = legs.first;
    return _normalizeSite(
      (leg['prop_site'] ?? leg['sportsbook'] ?? leg['site'] ?? '').toString(),
    );
  }

  Widget _buildSiteSpecificSlip(List<Map<String, dynamic>> legs) {
    if (legs.isEmpty) {
      return _buildCurrentSlipSetupCard();
    }

    final site = _activeSlipSite(legs);
    if (site.contains('PRIZEPICKS')) {
      return _buildPrizePicksStyleSlip(legs);
    }
    if (site.contains('UNDERDOG')) {
      return _buildUnderdogStyleSlip(legs);
    }
    if (site.contains('SLEEPER')) {
      return _buildSleeperStyleSlip(legs);
    }
    if (site.contains('FANDUEL')) {
      return _buildFanDuelStyleSlip(legs);
    }
    if (site.contains('DRAFTKINGS')) {
      return _buildDraftKingsStyleSlip(legs);
    }
    return _buildCompactTicket(legs);
  }

  Widget _buildCurrentSlipSetupCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF011224),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF041A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A3B48)),
            ),
            child: const Text(
              'No props selected',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9AB0C3),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
