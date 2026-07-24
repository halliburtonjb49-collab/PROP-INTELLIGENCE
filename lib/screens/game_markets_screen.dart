import 'dart:async';

import 'package:flutter/material.dart';

import '../models/game_market.dart';
import '../services/api_service.dart';
import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

class GameMarketsScreen extends StatefulWidget {
  final Future<int> Function(Map<String, dynamic> leg) onAddToSlip;

  const GameMarketsScreen({super.key, required this.onAddToSlip});

  @override
  State<GameMarketsScreen> createState() => _GameMarketsScreenState();
}

class _GameMarketsScreenState extends State<GameMarketsScreen> {
  static const _sports = ['MLB', 'WNBA', 'NBA', 'NFL', 'NHL', 'EPL', 'MLS'];
  static const _marketLabels = {
    'h2h': 'MONEYLINE',
    'spreads': 'SPREADS',
    'totals': 'GAME TOTALS',
  };

  final ApiService _api = ApiService();
  String _sport = 'MLB';
  String _market = 'h2h';
  GameMarketFeed? _feed;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh && _feed == null) {
      final cached = await _api.loadCachedGameMarkets(_sport);
      if (!mounted) return;
      if (cached != null && cached.events.isNotEmpty) {
        setState(() {
          _feed = cached;
          _loading = false;
          _error = null;
        });
      }
    }
    if (_feed == null || refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final feed = await _api.fetchGameMarkets(sport: _sport, refresh: refresh);
      if (!mounted) return;
      setState(() => _feed = feed);
    } catch (error) {
      if (!mounted) return;
      if (_feed == null) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _odds(int price) => price > 0 ? '+$price' : '$price';

  String _point(String market, GameMarketOutcome outcome) {
    final point = outcome.point;
    if (point == null) return '';
    if (market == 'totals') return ' ${point.toStringAsFixed(1)}';
    return ' ${point > 0 ? '+' : ''}${point.toStringAsFixed(1)}';
  }

  Future<void> _add(
    GameMarketEvent event,
    SportsbookGameMarkets book,
    GameMarketOutcome outcome,
  ) async {
    final point = outcome.point ?? 0;
    final side = _market == 'totals'
        ? outcome.name.toUpperCase()
        : outcome.name == event.homeTeam
        ? 'HOME'
        : 'AWAY';
    final id = [event.id, book.key, _market, outcome.name, point].join('|');
    final added = await widget.onAddToSlip({
      'prop_id': id,
      'id': id,
      'event_id': event.id,
      'player': outcome.name,
      'sport': event.sport,
      'matchup': '${event.awayTeam} @ ${event.homeTeam}',
      'prop_site': book.title,
      'sportsbook': book.title,
      'market': _marketLabels[_market],
      'market_key': _market,
      'line': point,
      'current_line': point,
      'side': side,
      'pick': side,
      'pick_text': '${outcome.name}${_point(_market, outcome)}',
      'odds': outcome.price,
      'current_odds': outcome.price,
      'game_time': event.commenceTime?.toIso8601String() ?? '',
      'display_time': event.commenceTime?.toLocal().toString() ?? '',
      'selection_type': 'GAME_MARKET',
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: added == 1 ? AppColors.gold : const Color(0xFF253545),
        content: Text(
          added == 1
              ? '${outcome.name} added to Active Slip.'
              : 'This selection is already in the slip, or the slip uses another sportsbook.',
          style: TextStyle(
            color: added == 1 ? const Color(0xFF06111B) : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _feed?.events ?? const <GameMarketEvent>[];
    return Column(
      children: [
        _header(),
        Expanded(
          child: _loading && _feed == null
              ? const _GameMarketSkeleton()
              : _error != null && _feed == null
              ? _errorState()
              : events.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: () => _load(refresh: true),
                  color: AppColors.gold,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1180
                          ? 3
                          : constraints.maxWidth >= 760
                          ? 2
                          : 1;
                      final width =
                          (constraints.maxWidth - 28 - ((columns - 1) * 12)) /
                          columns;
                      return ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final event in events)
                                SizedBox(
                                  width: width,
                                  child: _GameCard(
                                    event: event,
                                    market: _market,
                                    marketLabel: _marketLabels[_market]!,
                                    odds: _odds,
                                    point: _point,
                                    onAdd: _add,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _header() {
    final updated = _feed?.updatedAt?.toLocal();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF08131D),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'GAME MARKETS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF28C881).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF28C881)),
                ),
                child: const Text(
                  'LIVE ODDS',
                  style: TextStyle(
                    color: Color(0xFF28C881),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (updated != null)
                Text(
                  '${_feed!.cached ? 'Cached' : 'Updated'} ${TimeOfDay.fromDateTime(updated).format(context)}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              IconButton(
                tooltip: 'Refresh game markets',
                onPressed: _loading ? null : () => _load(refresh: true),
                icon: const Icon(Icons.refresh_rounded, color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final sport in _sports) ...[
                  ChoiceChip(
                    label: Text(sport),
                    selected: _sport == sport,
                    onSelected: (_) {
                      if (_sport == sport) return;
                      setState(() {
                        _sport = sport;
                        _feed = null;
                      });
                      unawaited(_load());
                    },
                  ),
                  const SizedBox(width: 7),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final entry in _marketLabels.entries)
                ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {_market},
            onSelectionChanged: (value) =>
                setState(() => _market = value.first),
          ),
        ],
      ),
    );
  }

  Widget _errorState() => _CenteredState(
    icon: Icons.cloud_off_rounded,
    title: 'Unable to load game markets',
    message: userFacingLoadError(_error, noun: 'game markets'),
    action: () => _load(refresh: true),
  );

  Widget _emptyState() => _CenteredState(
    icon: Icons.event_busy_rounded,
    title: 'No $_sport game markets available',
    message:
        'The league may be out of season or sportsbooks have not posted lines yet.',
    action: () => _load(refresh: true),
  );
}

class _GameCard extends StatelessWidget {
  final GameMarketEvent event;
  final String market;
  final String marketLabel;
  final String Function(int) odds;
  final String Function(String, GameMarketOutcome) point;
  final Future<void> Function(
    GameMarketEvent,
    SportsbookGameMarkets,
    GameMarketOutcome,
  )
  onAdd;

  const _GameCard({
    required this.event,
    required this.market,
    required this.marketLabel,
    required this.odds,
    required this.point,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final available = event.bookmakers
        .where((book) => book.markets[market]?.isNotEmpty == true)
        .toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${event.awayTeam} @ ${event.homeTeam}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                event.sport,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            event.commenceTime == null
                ? 'Time to be announced'
                : event.commenceTime!.toLocal().toString(),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
          const SizedBox(height: 12),
          Text(
            marketLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (available.isEmpty)
            const Text(
              'Market not posted yet.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10),
            )
          else
            for (final book in available) ...[
              Text(
                book.title.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final outcome in book.markets[market]!)
                    OutlinedButton(
                      onPressed: () => onAdd(event, book, outcome),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        side: const BorderSide(color: AppColors.borderGold),
                      ),
                      child: Text(
                        '${outcome.name}${point(market, outcome)}  ${odds(outcome.price)}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback action;

  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.gold, size: 42),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: action,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('TRY AGAIN'),
          ),
        ],
      ),
    ),
  );
}

class _GameMarketSkeleton extends StatelessWidget {
  const _GameMarketSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(14),
    itemCount: 4,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, _) => Container(
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
      ),
    ),
  );
}
