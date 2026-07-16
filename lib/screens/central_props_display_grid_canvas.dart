import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/affiliate_router.dart';
import '../services/api_service.dart';
import '../services/auth_manager.dart';
import '../services/filter_manager.dart';
import '../services/goblin_manager.dart';
import '../services/prop_watchlist_service.dart';
import '../services/slip_manager.dart';
import '../widgets/elite_prop_card.dart';

class CentralPropsDisplayGridCanvas extends StatefulWidget {
  const CentralPropsDisplayGridCanvas({super.key});

  @override
  State<CentralPropsDisplayGridCanvas> createState() =>
      _CentralPropsDisplayGridCanvasState();
}

class _CentralPropsDisplayGridCanvasState
    extends State<CentralPropsDisplayGridCanvas> {
  final ApiService _apiService = ApiService();
  final PropWatchlistService _watchlistService = PropWatchlistService();
  Stream<dynamic>? _channelStream;
  bool _websocketUnavailable = false;
  Timer? _fallbackPollTimer;

  List<dynamic> _fetchedProps = [];
  Set<String> _favoritedPlayerNames = <String>{};

  String _normalizePlayerName(String value) => value.trim().toLowerCase();

  Set<String> _extractFavoritePlayerNames(List<Map<String, dynamic>> rows) {
    return rows
        .map(
          (row) =>
              (row['player_name']?.toString() ??
              row['player']?.toString() ??
              ''),
        )
        .map(_normalizePlayerName)
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<void> _primeFavoritePlayerNames() async {
    try {
      // Fast path: hydrate from local cache first for immediate icon state.
      final localRows = await _watchlistService.loadWatchlist(
        includeCloudSync: false,
      );
      if (mounted) {
        setState(() {
          _favoritedPlayerNames = _extractFavoritePlayerNames(localRows);
        });
      }

      // Confirmation path: merge with cloud and refresh star state.
      final mergedRows = await _watchlistService.syncLocalAndCloudWatchlist();
      if (mounted) {
        setState(() {
          _favoritedPlayerNames = _extractFavoritePlayerNames(mergedRows);
        });
      }
    } catch (_) {
      // Keep UI responsive even if local/cloud sync fails.
    }
  }

  @override
  void initState() {
    super.initState();
    _primeFavoritePlayerNames();
    _websocketUnavailable = true;
    _startFallbackPolling();
  }

  Future<void> _fetchFallbackProps() async {
    try {
      final incoming = await _apiService.fetchRawPropsFeed();
      if (!mounted) {
        return;
      }
      setState(() {
        _fetchedProps = incoming;
      });
    } catch (_) {
      // Keep fallback polling quiet to avoid UI noise while backend warms up.
    }
  }

  void _startFallbackPolling() {
    if (_fallbackPollTimer != null) {
      return;
    }
    _fetchFallbackProps();
    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchFallbackProps();
    });
  }

  String _formatStatus(BackendRefreshStatus status) {
    if (status.lastRefreshAt == null || status.sourceUrl.isEmpty) {
      return status.message;
    }
    final value = status.lastRefreshAt!.toLocal();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return 'Last refresh $hour:$minute:$second via ${status.sourceUrl}';
  }

  Color _statusColor(BackendRefreshStatus status) {
    if (status.lastRefreshAt == null || status.sourceUrl.isEmpty) {
      return const Color(0xFFFFC72C);
    }
    return const Color(0xFF56D38A);
  }

  Future<void> triggerManualBackendRefresh() async {
    try {
      await _apiService.wakeBackend();
      final incoming = await _apiService.fetchRawPropsFeed();

      if (mounted) {
        setState(() {
          _fetchedProps = incoming;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Props database updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (error) {
      debugPrint(
        'Could not contact your local server engine executable: $error',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not contact local backend server.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget buildSportsbookFilterBar() {
    const books = [
      'ALL',
      'FANDUEL',
      'DRAFTKINGS',
      'PRIZEPICKS',
      'UNDERDOG',
      'SLEEPER',
    ];

    return ValueListenableBuilder<Set<String>>(
      valueListenable: FilterManager.activeBookFilter,
      builder: (context, currentFilters, child) {
        return SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            itemBuilder: (context, index) {
              final bookName = books[index];
              final isSelected = currentFilters.contains(bookName);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  onPressed: () => FilterManager.updateFilter(bookName),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isSelected
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF1E222A),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : Colors.white10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Text(
                    bookName,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GoblinManager.showGoblinsOnly,
      builder: (context, goblinsOnly, child) {
        return ValueListenableBuilder<Set<String>>(
          valueListenable: FilterManager.activeBookFilter,
          builder: (context, activeFilters, child) {
            return StreamBuilder(
              stream: _channelStream,
              builder: (context, snapshot) {
                final isUserPremium =
                    AuthManager.instance.sessionState.value.isPremium;

                if (snapshot.hasError && !_websocketUnavailable) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _websocketUnavailable = true;
                    });
                  });
                }

                if (snapshot.hasData) {
                  final decoded = jsonDecode(snapshot.data.toString());
                  if (decoded is List) {
                    _fetchedProps = decoded;
                  }
                }

                if (_fetchedProps.isEmpty) {
                  return Center(
                    child: Text(
                      _websocketUnavailable
                          ? 'Live websocket unavailable. Polling API every 10s.'
                          : 'Connecting to Python Server Engine...',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final displayedProps = _fetchedProps
                    .where((entry) {
                      if (entry is! Map<String, dynamic>) {
                        return false;
                      }
                      final isGoblin = entry['is_goblin_line'] == true;
                      final matchesGoblinState = isGoblin == goblinsOnly;
                      if (!matchesGoblinState) {
                        return false;
                      }

                      if (activeFilters.contains('ALL')) {
                        return true;
                      }
                      final oddsData =
                          (entry['odds_data'] as List<dynamic>? ?? const []);
                      final firstOdds = oddsData.isNotEmpty
                          ? oddsData.first as Map<String, dynamic>
                          : const <String, dynamic>{};
                      final currentPropBook = (firstOdds['bookmaker'] ?? '')
                          .toString()
                          .toUpperCase();
                      return activeFilters.contains(currentPropBook);
                    })
                    .toList(growable: false);

                final activeFilterLabel = activeFilters.contains('ALL')
                    ? 'ALL'
                    : activeFilters.join(', ');
                final modeLabel = goblinsOnly ? 'GOBLINS' : 'STANDARD';

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: ValueListenableBuilder<BackendRefreshStatus>(
                              valueListenable: ApiService.refreshStatusNotifier,
                              builder: (context, status, _) {
                                return Text(
                                  _formatStatus(status),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _statusColor(status),
                                    fontSize: 10,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: triggerManualBackendRefresh,
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.refresh,
                                    color: Color(0xFFFFD700),
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'REFRESH',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: buildSportsbookFilterBar(),
                    ),
                    if (displayedProps.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            'No live $modeLabel / $activeFilterLabel props matching confidence thresholds right now.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: displayedProps.length,
                          itemBuilder: (context, index) {
                            final prop =
                                displayedProps[index] as Map<String, dynamic>;
                            final oddsData =
                                (prop['odds_data'] as List<dynamic>? ??
                                const []);
                            final firstOdds = oddsData.isNotEmpty
                                ? oddsData.first as Map<String, dynamic>
                                : const <String, dynamic>{};

                            return GestureDetector(
                              onTap: () {
                                final propId =
                                    (prop['id'] ?? prop['prop_id'] ?? '')
                                        .toString();
                                final selectionPayload = {
                                  'id': propId,
                                  'prop_id': propId,
                                  'player_name': (prop['player_name'] ?? '')
                                      .toString(),
                                  'market_type': (prop['market_type'] ?? '')
                                      .toString(),
                                  'line': (prop['line'] as num?) ?? 0,
                                  'sport': (prop['sport'] ?? '').toString(),
                                  'edge_percentage':
                                      (prop['edge_percentage'] as num?) ?? 0,
                                  'ai_projection':
                                      (prop['ai_projection'] as num?),
                                  'is_goblin_line':
                                      prop['is_goblin_line'] == true,
                                  'sportsbook':
                                      (firstOdds['bookmaker'] ?? 'sportsbook')
                                          .toString(),
                                  'odds_data': oddsData,
                                };
                                SlipManager.togglePropSelection(
                                  selectionPayload,
                                );
                              },
                              onLongPress: () {
                                SportsbookAffiliateRouter.routeUserToWagerSlip(
                                  sportsbook:
                                      (firstOdds['bookmaker'] ?? 'sportsbook')
                                          .toString(),
                                  playerName: (prop['player_name'] ?? '')
                                      .toString(),
                                  marketType: (prop['market_type'] ?? '')
                                      .toString(),
                                );
                              },
                              child: ElitePropCard(
                                playerName: (prop['player_name'] ?? '')
                                    .toString(),
                                propType: (prop['market_type'] ?? '')
                                    .toString(),
                                sportsbookLine: (prop['line'] as num?) ?? 0,
                                americanOdds:
                                    ((firstOdds['over_odds'] as num?) ?? -110)
                                        .toInt(),
                                aiProjection:
                                    (prop['ai_projection'] as num?) ?? 0,
                                edgePercentage:
                                    (prop['edge_percentage'] as num?) ?? 0,
                                isUserPremium: isUserPremium,
                                initialIsFavorited: _favoritedPlayerNames
                                    .contains(
                                      _normalizePlayerName(
                                        (prop['player_name'] ?? '').toString(),
                                      ),
                                    ),
                                onFavoriteChanged: (isFavorited) {
                                  final normalizedPlayerName =
                                      _normalizePlayerName(
                                        (prop['player_name'] ?? '').toString(),
                                      );
                                  if (normalizedPlayerName.isEmpty) {
                                    return;
                                  }

                                  setState(() {
                                    if (isFavorited) {
                                      _favoritedPlayerNames = {
                                        ..._favoritedPlayerNames,
                                        normalizedPlayerName,
                                      };
                                    } else {
                                      _favoritedPlayerNames =
                                          _favoritedPlayerNames
                                              .where(
                                                (name) =>
                                                    name !=
                                                    normalizedPlayerName,
                                              )
                                              .toSet();
                                    }
                                  });
                                },
                                propData: prop,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
