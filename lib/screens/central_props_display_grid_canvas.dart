import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/affiliate_router.dart';
import '../services/api_service.dart';
import '../services/auth_manager.dart';
import '../services/filter_manager.dart';
import '../services/engagement_tracker.dart';
import '../services/live_update_service.dart';
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
  final LiveUpdateService _liveUpdates = LiveUpdateService();
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
    _channelStream = _liveUpdates.stream;
    _liveUpdates.connect();
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
    return const Color(0xFF36B9FF);
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
            backgroundColor: Color(0xFF36B9FF),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SPORTSBOOK',
              style: TextStyle(
                color: Color(0xFF8EA0AD),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final bookName = books[index];
                  final isSelected = currentFilters.contains(bookName);
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: OutlinedButton(
                      onPressed: () => FilterManager.updateFilter(bookName),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        backgroundColor: isSelected
                            ? const Color(0xFF36B9FF).withValues(alpha: .14)
                            : const Color(0xFF182633),
                        foregroundColor: isSelected
                            ? const Color(0xFF36B9FF)
                            : const Color(0xFFD7DEE5),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFF36B9FF)
                              : const Color(0xFF34495A),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(
                        bookName,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: .25,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _fallbackPollTimer?.cancel();
    unawaited(_liveUpdates.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  _startFallbackPolling();
                });
              });
            }

            if (snapshot.hasData) {
              final decoded = jsonDecode(snapshot.data.toString());
              final incoming =
                  decoded is Map<String, dynamic> &&
                      decoded['type'] == 'props.updated'
                  ? decoded['data']
                  : decoded;
              if (incoming is List) {
                _fetchedProps = incoming;
                _websocketUnavailable = false;
                _fallbackPollTimer?.cancel();
                _fallbackPollTimer = null;
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
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1824),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF263746)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.radar_rounded,
                            color: Color(0xFF36B9FF),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'LIVE PROP BOARD',
                            style: TextStyle(
                              color: Color(0xFFD7DEE5),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .65,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF36B9FF,
                              ).withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${displayedProps.length} RESULTS',
                              style: const TextStyle(
                                color: Color(0xFF36B9FF),
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: triggerManualBackendRefresh,
                            tooltip: 'Refresh live props',
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
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
                        ],
                      ),
                      const SizedBox(height: 12),
                      buildSportsbookFilterBar(),
                    ],
                  ),
                ),
                if (displayedProps.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No live $activeFilterLabel props matching confidence thresholds right now.',
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
                            (prop['odds_data'] as List<dynamic>? ?? const []);
                        final firstOdds = oddsData.isNotEmpty
                            ? oddsData.first as Map<String, dynamic>
                            : const <String, dynamic>{};

                        return GestureDetector(
                          onTap: () {
                            final propId = (prop['id'] ?? prop['prop_id'] ?? '')
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
                              'ai_projection': (prop['ai_projection'] as num?),
                              'sportsbook':
                                  (firstOdds['bookmaker'] ?? 'sportsbook')
                                      .toString(),
                              'odds_data': oddsData,
                            };
                            EngagementTracker.instance.record(propId, 'CLICK');
                            SlipManager.togglePropSelection(selectionPayload);
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
                            playerName: (prop['player_name'] ?? '').toString(),
                            propType: (prop['market_type'] ?? '').toString(),
                            sportsbookLine: (prop['line'] as num?) ?? 0,
                            americanOdds:
                                ((firstOdds['over_odds'] as num?) ?? -110)
                                    .toInt(),
                            aiProjection: (prop['ai_projection'] as num?) ?? 0,
                            edgePercentage:
                                (prop['edge_percentage'] as num?) ?? 0,
                            isUserPremium: isUserPremium,
                            initialIsFavorited: _favoritedPlayerNames.contains(
                              _normalizePlayerName(
                                (prop['player_name'] ?? '').toString(),
                              ),
                            ),
                            onFavoriteChanged: (isFavorited) {
                              if (isFavorited) {
                                EngagementTracker.instance.record(
                                  (prop['id'] ?? prop['prop_id'] ?? '')
                                      .toString(),
                                  'WATCHLIST',
                                );
                              }
                              final normalizedPlayerName = _normalizePlayerName(
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
                                  _favoritedPlayerNames = _favoritedPlayerNames
                                      .where(
                                        (name) => name != normalizedPlayerName,
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
  }
}
