import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../models/slip_selection.dart';
import '../navigation/app_navigation.dart';
import '../pages/briefing_page.dart';
import '../pages/injury_impact_page.dart';
import '../pages/intelligence_lab_page.dart';
import '../pages/line_movement_page.dart';
import '../pages/owner_operations_page.dart';
import '../pages/prop_alerts_page.dart';
import '../pages/prop_chat_page.dart';
import '../pages/referee_tracker_page.dart';
import '../pages/search_players_page.dart';
import '../pages/track_record_page.dart';
import '../screens/game_markets_screen.dart';
import '../services/api_service.dart';
import '../services/app_sound_service.dart';
import '../services/prop_chat_service.dart';
import '../services/auth_manager.dart';
import '../services/engagement_tracker.dart';
import '../services/injury_alert_service.dart';
import '../services/live_update_service.dart';
import '../services/prop_board_engine.dart';
import '../services/prop_market_identity.dart';
import '../services/recommendation_access.dart';
import '../theme/app_colors.dart' as app_colors;
import 'active_board_filters.dart';
import 'analytics_admin_workspace.dart';
import 'board_category_chip.dart';
import 'onboarding_dialog.dart';
import 'scoreboard_view.dart';
import 'ev_scanner_card.dart';
import 'prop_grid.dart';
import 'provider_reliability_banner.dart';
import 'verdict_filter_bar.dart';

class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PropChatService.unreadCount,
      builder: (context, unread, _) {
        if (unread <= 0) return const SizedBox.shrink();
        return Semantics(
          label: '$unread unread chat notifications',
          child: Container(
            key: const ValueKey('chat-unread-badge'),
            constraints: const BoxConstraints(minWidth: 21, minHeight: 21),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: app_colors.AppColors.gold,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: app_colors.AppColors.bgBase,
                width: 1.4,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: const TextStyle(
                color: app_colors.AppColors.bgBase,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}

SnackBar buildInjuryImpactSnackBar({
  required Map<String, dynamic> alert,
  required VoidCallback onView,
}) {
  return SnackBar(
    key: const ValueKey('live-injury-alert'),
    backgroundColor: const Color(0xFF0B2A42),
    behavior: SnackBarBehavior.floating,
    showCloseIcon: true,
    closeIconColor: app_colors.AppColors.goldLight,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: app_colors.AppColors.gold),
    ),
    content: InkWell(
      key: const ValueKey('injury-impact-alert-view'),
      onTap: onView,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    '${(alert['title'] ?? 'Injury impact changed').toString().toUpperCase()}: ',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              TextSpan(text: '${alert['message'] ?? ''}'),
            ],
          ),
          style: const TextStyle(
            color: app_colors.AppColors.goldLight,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    ),
    duration: const Duration(seconds: 8),
    action: SnackBarAction(
      label: 'VIEW',
      textColor: app_colors.AppColors.goldHighlight,
      onPressed: onView,
    ),
  );
}

class MainDashboard extends StatefulWidget {
  final List<SlipSelection> selections;
  final void Function(PropData prop, PickSide side) onSelect;
  final Future<int> Function(Map<String, dynamic> leg) onAddGameMarket;
  final Future<void> Function(String propId) onRemoveLabSelection;
  final Future<void> Function() onClearLabSelections;
  final Future<void> Function(List<PropData> props) onPropsRefreshed;
  final String sportFilter;
  final AppPage selectedPage;
  final ValueChanged<AppPage>? onSelectPage;
  final VoidCallback? onFloatChat;
  final VoidCallback? onShowChatBubble;
  final bool isChatBubbleVisible;
  final ValueNotifier<int> propCountNotifier;
  final ValueNotifier<int> refreshRequestNotifier;
  final ValueChanged<String>? onStartupLog;

  const MainDashboard({
    super.key,
    required this.selections,
    required this.onSelect,
    required this.onAddGameMarket,
    required this.onRemoveLabSelection,
    required this.onClearLabSelections,
    required this.onPropsRefreshed,
    required this.sportFilter,
    required this.selectedPage,
    this.onSelectPage,
    this.onFloatChat,
    this.onShowChatBubble,
    this.isChatBubbleVisible = true,
    required this.propCountNotifier,
    required this.refreshRequestNotifier,
    this.onStartupLog,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  int _searchFieldGeneration = 0;
  final ScrollController _boardVerticalController = ScrollController();
  final ScrollController _bookHorizontalController = ScrollController();
  final ScrollController _categoryHorizontalController = ScrollController();
  final ScrollController _sportHorizontalController = ScrollController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String _selectedSite = 'ALL';
  String _selectedSiteSport = '';
  String _selectedCategory = 'ALL';
  final String _selectedSide = 'All';
  final String _selectedTier = 'All';
  int _minConfidence = 0;
  String _sortBy = 'trust';
  // Always open on real available inventory. A temporary lack of actionable
  // model verdicts must never make a healthy prop catalog look empty.
  String _verdictFilter = 'ALL';
  DateTime? _lastUpdated;
  List<PropData> _latestProps = const [];
  List<PropData> _siteInventoryProps = const [];
  Map<String, int> _siteSportCounts = const {};
  Map<String, Map<String, int>> _siteSportCategoryCounts = const {};
  Map<String, Map<String, int>> _siteTotalSportCategoryCounts = const {};
  Map<String, Map<String, int>> _sitePlayableSportCategoryCounts = const {};
  Map<String, dynamic> _providerCoverage = const {};
  Map<String, dynamic> _providerReliability = const {};
  Map<String, int> _categoryCounts = const {};
  Map<String, int> _totalCategoryCounts = const {};
  Map<String, int> _playableCategoryCounts = const {};
  Map<String, int> _verdictCounts = const {};
  List<PropData> _evScannerProps = const [];
  final TextEditingController _evSearchController = TextEditingController();
  String _evBook = 'ALL';
  String _evSort = 'EV';
  double _evMinimum = 0;
  PropData? _focusedProp;
  bool _isEvScannerLoading = false;
  String? _evScannerError;
  List<PropAlertData> _propAlerts = const [];
  final LiveUpdateService _injuryAlertUpdates = LiveUpdateService(
    channels: const {'alerts'},
  );
  StreamSubscription<dynamic>? _injuryAlertSubscription;
  Timer? _injuryAlertPollTimer;
  List<Map<String, dynamic>> _injuryAlerts = const [];
  final Set<String> _seenInjuryAlertIds = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadPropAlerts());
    if (AuthManager.instance.sessionState.value.hasEdgeAccess) {
      _injuryAlertSubscription = _injuryAlertUpdates.stream.listen(
        _handleInjuryAlertEvent,
        onError: (_) {},
      );
      _injuryAlertUpdates.connect();
      unawaited(_loadInjuryAlerts());
      _injuryAlertPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_loadInjuryAlerts(notifyNew: true));
      });
    }
    if (widget.selectedPage == AppPage.evScanner) {
      unawaited(_loadEvScannerProps());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    unawaited(_injuryAlertSubscription?.cancel());
    _injuryAlertPollTimer?.cancel();
    unawaited(_injuryAlertUpdates.dispose());
    _boardVerticalController.dispose();
    _bookHorizontalController.dispose();
    _categoryHorizontalController.dispose();
    _sportHorizontalController.dispose();
    _searchController.dispose();
    _evSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sportFilter != widget.sportFilter && mounted) {
      setState(() {
        _selectedCategory = 'ALL';
        _focusedProp = null;
        _latestProps = const [];
        _categoryCounts = const {};
        _totalCategoryCounts = const {};
        _playableCategoryCounts = const {};
        _lastUpdated = null;
      });
      if (widget.selectedPage == AppPage.evScanner) {
        unawaited(_loadEvScannerProps());
      }
    }
    if (oldWidget.selectedPage != widget.selectedPage &&
        widget.selectedPage == AppPage.evScanner) {
      unawaited(_loadEvScannerProps());
    }
  }

  Future<void> _loadEvScannerProps() async {
    if (_isEvScannerLoading) {
      return;
    }

    setState(() {
      _isEvScannerLoading = true;
      _evScannerError = null;
    });

    try {
      final props = await _apiService.fetchPositiveEvProps(
        minEv: 0.0,
        sport: widget.sportFilter,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _evScannerProps = props;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _evScannerError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isEvScannerLoading = false;
        });
      }
    }
  }

  PickSide? _evSide(PropData prop) {
    final side = prop.proSuggestedSide;
    if (side == 'OVER') return PickSide.over;
    if (side == 'UNDER') return PickSide.under;
    if (prop.projection == null || prop.projection == prop.line) return null;
    return prop.projection! > prop.line ? PickSide.over : PickSide.under;
  }

  List<String> get _evBooks {
    final books =
        _evScannerProps
            .map((prop) => prop.sportsbook.trim().toUpperCase())
            .where((book) => book.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['ALL', ...books];
  }

  List<PropData> get _visibleEvProps {
    final query = _evSearchController.text.trim().toLowerCase();
    final props = _evScannerProps.where((prop) {
      final ev = prop.evPercentage ?? 0;
      final matchesBook =
          _evBook == 'ALL' || prop.sportsbook.trim().toUpperCase() == _evBook;
      final matchesQuery =
          query.isEmpty ||
          '${prop.player} ${prop.market} ${prop.sport} ${prop.sportsbook}'
              .toLowerCase()
              .contains(query);
      return _evSide(prop) != null &&
          ev >= _evMinimum &&
          matchesBook &&
          matchesQuery;
    }).toList();
    props.sort(
      (a, b) => switch (_evSort) {
        'PROBABILITY' => (b.fairProbability ?? 0).compareTo(
          a.fairProbability ?? 0,
        ),
        'ODDS' => (b.overOdds ?? -10000).compareTo(a.overOdds ?? -10000),
        _ => (b.evPercentage ?? 0).compareTo(a.evPercentage ?? 0),
      },
    );
    return props;
  }

  void _showEvDetails(PropData prop) {
    final probability = prop.fairProbability ?? 0;
    final fairDecimal =
        prop.fairDecimalOdds ?? (probability > 0 ? 1 / probability : 0);
    final side = _evSide(prop);
    if (side == null) return;
    final availableOdds = side == PickSide.over
        ? prop.overOdds
        : prop.underOdds;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: app_colors.AppColors.panel,
        title: Text('${prop.player} • ${_propMarket(prop)}'),
        content: SizedBox(
          width: 430,
          child: Text(
            'Sportsbook: ${prop.sportsbook}\n'
            'Recommended side: ${side.name.toUpperCase()} ${prop.line.toStringAsFixed(1)}\n'
            'Available odds: ${(availableOdds ?? -110).round()}\n'
            'Model probability: ${((prop.modelProbability ?? probability) * 100).toStringAsFixed(1)}%\n'
            'Shin no-vig probability: ${prop.marketProbability == null ? '--' : '${(prop.marketProbability! * 100).toStringAsFixed(1)}%'}\n'
            'Blended fair probability: ${(probability * 100).toStringAsFixed(1)}%\n'
            'Selection formula: ${prop.selectionMethod}\n'
            'Uncertainty-adjusted probability: ${prop.uncertaintyAdjustedProbability == null ? '--' : '${(prop.uncertaintyAdjustedProbability! * 100).toStringAsFixed(1)}%'}\n'
            'Push probability: ${(prop.pushProbability * 100).toStringAsFixed(1)}%\n'
            'Estimated fair decimal price: ${fairDecimal == 0 ? '--' : fairDecimal.toStringAsFixed(2)}\n'
            'Expected value: ${(prop.evPercentage ?? 0) >= 0 ? '+' : ''}${(prop.evPercentage ?? 0).toStringAsFixed(1)}%\n'
            'Method: ${prop.probabilityMethod.isEmpty ? 'calibrated model' : prop.probabilityMethod}\n'
            'Model version: ${prop.projectionModelVersion.isEmpty ? 'not available' : prop.projectionModelVersion}\n'
            'Sample size: ${prop.projectionSampleSize} games\n'
            'Data freshness: ${prop.freshnessLabel}\n'
            'Source: ${prop.sourceProvider.isEmpty ? prop.sportsbook : prop.sourceProvider}\n'
            'Market blend weight: ${(prop.probabilityMarketWeight * 100).toStringAsFixed(0)}%\n'
            'Out-of-sample calibration: ${prop.probabilityCalibrationSampleSize == 0 ? 'pending' : '${prop.probabilityCalibrationAdjustment >= 0 ? '+' : ''}${(prop.probabilityCalibrationAdjustment * 100).toStringAsFixed(1)}% from ${prop.probabilityCalibrationSampleSize} graded picks'}\n'
            'Probability uncertainty: ${prop.probabilityUncertainty == null ? '--' : '±${(prop.probabilityUncertainty! * 100).toStringAsFixed(1)}%'}\n\n'
            'Positive EV is a long-run estimate, not a guarantee. Confirm the current line and price before adding the prop.',
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onSelect(prop, side);
            },
            child: const Text('ADD TO SLIP'),
          ),
        ],
      ),
    );
  }

  Widget _buildEvScanner() {
    if (_isEvScannerLoading && _evScannerProps.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: app_colors.AppColors.gold),
      );
    }
    if (_evScannerError != null && _evScannerProps.isEmpty) {
      return Center(
        child: OutlinedButton.icon(
          onPressed: _loadEvScannerProps,
          icon: const Icon(Icons.refresh),
          label: const Text('RETRY EV FEED'),
        ),
      );
    }
    final visible = _visibleEvProps;
    return RefreshIndicator(
      color: app_colors.AppColors.gold,
      onRefresh: _loadEvScannerProps,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EV SCANNER',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Find mispriced props, compare fair probability, and move qualified value into Active Tracking Slip.',
                      style: TextStyle(color: app_colors.AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _isEvScannerLoading ? null : _loadEvScannerProps,
                icon: const Icon(Icons.refresh),
                label: const Text('REFRESH ODDS'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _evSearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Player, market, sport, or site',
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _evBooks.contains(_evBook) ? _evBook : 'ALL',
                items: _evBooks
                    .map(
                      (book) =>
                          DropdownMenuItem(value: book, child: Text(book)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _evBook = value ?? 'ALL'),
              ),
              DropdownButton<String>(
                value: _evSort,
                items: const [
                  DropdownMenuItem(value: 'EV', child: Text('Highest EV')),
                  DropdownMenuItem(
                    value: 'PROBABILITY',
                    child: Text('Highest Fair Probability'),
                  ),
                  DropdownMenuItem(value: 'ODDS', child: Text('Best Odds')),
                ],
                onChanged: (value) => setState(() => _evSort = value ?? 'EV'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _evMinimum = 0;
                  _evBook = 'ALL';
                  _evSort = 'EV';
                  _evSearchController.clear();
                }),
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('RESET'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'MINIMUM EV: +${_evMinimum.toStringAsFixed(1)}%  •  ${visible.length} MATCHES',
          ),
          Slider(
            value: _evMinimum,
            min: 0,
            max: 20,
            divisions: 40,
            label: '+${_evMinimum.toStringAsFixed(1)}%',
            onChanged: (value) => setState(() => _evMinimum = value),
          ),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(
                child: Text('No props match the current EV filters.'),
              ),
            )
          else
            ...visible.map((prop) {
              final market = _propMarket(prop);
              final side = _evSide(prop)!;
              return PositiveEvScannerCard(
                player: prop.player,
                propType: market.isEmpty ? prop.market : market,
                lineValue: prop.line,
                slowBookmaker: prop.sportsbook,
                slowBookOdds:
                    ((side == PickSide.over ? prop.overOdds : prop.underOdds) ??
                            -110)
                        .round(),
                evPercentage: prop.evPercentage ?? 0,
                fairProbability: (prop.fairProbability ?? 0) * 100,
                onInspect: () => _showEvDetails(prop),
                onAdd: () => widget.onSelect(prop, side),
              );
            }),
        ],
      ),
    );
  }

  void _handlePropsLoaded(
    List<PropData> props,
    int propCount,
    int facetTotal,
    Map<String, int> categoryCounts,
  ) {
    if (!mounted) {
      return;
    }
    if (props.isNotEmpty) {
      final first = props.first;
      debugPrint(
        'FIRST PROP: id=${first.id}, player=${first.player}, sport=${first.sport}, imagePath=${first.imagePath}',
      );
    }
    setState(() {
      _latestProps = props;
      _categoryCounts = categoryCounts;
      _totalCategoryCounts = _apiService.lastTotalCategoryCounts;
      _playableCategoryCounts = _apiService.lastPlayableCategoryCounts;
      _verdictCounts = _apiService.lastVerdictCounts;
      _providerCoverage = _apiService.lastProviderCoverage;
      _providerReliability = _apiService.lastProviderReliability;
      if (_selectedSite != 'ALL' && _selectedCategory == 'ALL') {
        _siteInventoryProps = props;
        if (_selectedSiteSport.isEmpty) {
          final normalizedSportCounts = <String, int>{};
          for (final entry in _apiService.lastSportCounts.entries) {
            final sport = _normalizeSport(entry.key);
            normalizedSportCounts[sport] =
                (normalizedSportCounts[sport] ?? 0) + entry.value;
          }
          final normalizedCategoryCounts = <String, Map<String, int>>{};
          for (final sportEntry
              in _apiService.lastSportCategoryCounts.entries) {
            final sport = _normalizeSport(sportEntry.key);
            final target = normalizedCategoryCounts.putIfAbsent(
              sport,
              () => <String, int>{},
            );
            for (final categoryEntry in sportEntry.value.entries) {
              target[categoryEntry.key] =
                  (target[categoryEntry.key] ?? 0) + categoryEntry.value;
            }
          }
          _siteSportCounts = normalizedSportCounts;
          _siteSportCategoryCounts = normalizedCategoryCounts;
          _siteTotalSportCategoryCounts =
              _apiService.lastTotalSportCategoryCounts;
          _sitePlayableSportCategoryCounts =
              _apiService.lastPlayableSportCategoryCounts;
        }
        final sports = _availableSiteSports;
        if (sports.isNotEmpty && !sports.contains(_selectedSiteSport)) {
          _selectedSiteSport = sports.first;
        }
      }
      _lastUpdated = DateTime.now();
    });
    widget.propCountNotifier.value = propCount;
    unawaited(widget.onPropsRefreshed(props));
    unawaited(_loadPropAlerts(fallbackProps: props));
  }

  PropAlertData _parsePropAlert(Map<String, dynamic> value) {
    final edgeRaw = value['edge'];
    final edge = edgeRaw is num
        ? edgeRaw.toInt()
        : int.tryParse('$edgeRaw') ?? 0;
    return PropAlertData(
      sport: value['sport']?.toString() ?? 'ALL',
      title: value['title']?.toString() ?? 'Prop Alert',
      message: value['message']?.toString() ?? '',
      edge: edge,
      book: value['book']?.toString() ?? 'All Books',
      time: value['time']?.toString() ?? 'now',
    );
  }

  List<PropAlertData> _fallbackPropAlertsFromProps(List<PropData> props) {
    if (props.isEmpty) {
      return const [
        PropAlertData(
          sport: 'ALL',
          title: 'No Props Loaded',
          message:
              'No props loaded yet. Alerts will appear as soon as data sync completes.',
          edge: 0,
          book: 'All Books',
          time: 'now',
        ),
      ];
    }

    final sortedByEdge = [...props]
      ..sort((a, b) => b.piTrustScore.compareTo(a.piTrustScore));
    final top = sortedByEdge.first;
    final topTrust = top.piTrustScore;
    final bySport = <String, int>{};
    for (final prop in props) {
      final sport = _normalizeSport(prop.sport);
      bySport[sport] = (bySport[sport] ?? 0) + 1;
    }
    final topSport =
        (bySport.entries.toList()..sort((a, b) => b.value - a.value)).first;
    final hot = props.where((p) => p.piTrustScore >= 90).length;

    return [
      PropAlertData(
        sport: _normalizeSport(top.sport),
        title: 'Best Edge Alert',
        message:
            '${top.player} has PI Trust $topTrust/100 on ${_propMarket(top)}.',
        edge: topTrust,
        book: top.sportsbook,
        time: 'now',
      ),
      PropAlertData(
        sport: topSport.key,
        title: 'Most Active Sport',
        message:
            '${topSport.key} has ${topSport.value} props visible right now.',
        edge: topTrust,
        book: 'All Books',
        time: 'now',
      ),
      if (hot > 0)
        PropAlertData(
          sport: 'ALL',
          title: 'High Edge Cluster',
          message: '$hot props have PI Trust of 90+ right now.',
          edge: 90,
          book: 'All Books',
          time: 'now',
        ),
    ];
  }

  Future<void> _loadInjuryAlerts({bool notifyNew = false}) async {
    try {
      final alerts = await _apiService.fetchInjuryAlerts();
      if (!mounted) return;
      final newAlerts = alerts
          .where((alert) {
            final eventId = alert['eventId']?.toString() ?? '';
            return eventId.isNotEmpty && !_seenInjuryAlertIds.contains(eventId);
          })
          .toList(growable: false);
      setState(() {
        _injuryAlerts = alerts;
        _seenInjuryAlertIds.addAll(
          alerts.map((alert) => alert['eventId']?.toString() ?? ''),
        );
      });
      if (notifyNew && newAlerts.isNotEmpty) {
        await _presentInjuryAlert(newAlerts.first);
      }
    } catch (_) {
      // Live alerts remain available even if retained history cannot load.
    }
  }

  Future<void> _handleInjuryAlertEvent(dynamic raw) async {
    final alert = parseInjuryAlertEvent(raw);
    if (!mounted || alert == null) return;
    final eventId = alert['eventId']?.toString() ?? '';
    if (eventId.isEmpty || !_seenInjuryAlertIds.add(eventId)) return;
    setState(() {
      _injuryAlerts = [
        alert,
        ..._injuryAlerts,
      ].take(50).toList(growable: false);
    });
    await _presentInjuryAlert(alert);
  }

  Future<void> _presentInjuryAlert(Map<String, dynamic> alert) async {
    final preferences = await InjuryAlertPreferences.load();
    if (!mounted || !shouldPresentInjuryAlert(alert, preferences)) return;
    unawaited(AppSoundService.instance.play(AppSoundEvent.warning));
    final messenger = ScaffoldMessenger.maybeOf(context);
    void openInjuryImpact() {
      messenger?.hideCurrentSnackBar();
      widget.onSelectPage?.call(AppPage.injuryImpact);
    }

    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        buildInjuryImpactSnackBar(alert: alert, onView: openInjuryImpact),
      );
  }

  Future<void> _loadPropAlerts({
    List<PropData> fallbackProps = const [],
  }) async {
    try {
      final alerts = await _apiService.fetchPropAlerts();
      if (!mounted) {
        return;
      }
      final parsed = alerts
          .map(_parsePropAlert)
          .where((a) => a.message.isNotEmpty)
          .toList();
      setState(() {
        _propAlerts = parsed;
      });
    } catch (_) {
      if (!mounted || _propAlerts.isNotEmpty) {
        return;
      }
      setState(() {
        _propAlerts = _fallbackPropAlertsFromProps(fallbackProps);
      });
    }
  }

  String _formatLocalDate(DateTime value) {
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
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _formatLastUpdated(DateTime? value) {
    if (value == null) {
      return 'Not updated';
    }
    final localValue = value.toLocal();
    final hour = localValue.hour == 0
        ? 12
        : localValue.hour > 12
        ? localValue.hour - 12
        : localValue.hour;
    final minute = localValue.minute.toString().padLeft(2, '0');
    final period = localValue.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _normalizeSite(String value) {
    final normalized = value
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll('-', '');
    if (normalized.contains('PICK6') || normalized.contains('PICK 6')) {
      return 'PICK6';
    }
    if (normalized.contains('PRIZEPICKS')) {
      return 'PRIZEPICKS';
    }
    if (normalized.contains('DRAFTKINGS')) {
      return 'DRAFTKINGS';
    }
    if (normalized.contains('DRAFTPICKS')) {
      return 'DRAFT PICKS';
    }
    if (normalized.contains('FANDUEL')) {
      return 'FANDUEL';
    }
    if (normalized.contains('UNDERDOG')) {
      return 'UNDERDOG';
    }
    if (normalized.contains('BETR')) {
      return 'BETR';
    }
    return normalized;
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
    if (normalized.contains('NCAAB')) {
      return 'NCAAB';
    }
    if (normalized.contains('NBA')) {
      return 'NBA';
    }
    if (normalized.contains('NCAAF')) {
      return 'NCAAF';
    }
    if (normalized.contains('CFL')) {
      return 'CFL';
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

  // ignore: unused_element
  Widget _filterButton(String label, String selectedValue, VoidCallback onTap) {
    final isSelected = label == selectedValue;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? app_colors.AppColors.gold
                : const Color(0xFF07111C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: app_colors.AppColors.gold),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? app_colors.AppColors.bgBase : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _confidenceButton(String label, int value) {
    final isSelected = _minConfidence == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _minConfidence = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? app_colors.AppColors.gold
                : const Color(0xFF07111C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: app_colors.AppColors.gold),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? app_colors.AppColors.bgBase : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _sortButton(String label, String value) {
    final isSelected = _sortBy == value;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _sortBy = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? app_colors.AppColors.gold
                : const Color(0xFF07111C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: app_colors.AppColors.gold),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? app_colors.AppColors.bgBase : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  List<String> get _currentCategories {
    final dynamicCounts =
        _selectedSite != 'ALL' && _selectedSiteSport.isNotEmpty
        ? _selectedSportCategoryCounts
        : _categoryCounts;
    return visibleCategoryFilters(dynamicCounts);
  }

  List<String> get _availableSiteSports {
    if (_selectedSite == 'ALL') return const [];
    final sports =
        (_siteSportCounts.isNotEmpty
                ? _siteSportCounts.entries
                      .where((entry) => entry.value > 0)
                      .map((entry) => _normalizeSport(entry.key))
                : _siteInventoryProps.map(
                    (prop) => _normalizeSport(prop.sport),
                  ))
            .where((sport) => sport.isNotEmpty && sport != 'ALL')
            .toSet()
            .toList();
    // Mirrors the sidebar rail. Sports with no prop source are not ranked
    // here, because a rank implies the board can show them.
    const order = [
      'MLB',
      'NFL',
      'NBA',
      'WNBA',
      'NHL',
      'SOCCER',
      'NCAAF',
      'NCAAB',
      'CFL',
    ];
    sports.sort((left, right) {
      final leftRank = order.indexOf(left);
      final rightRank = order.indexOf(right);
      final normalizedLeft = leftRank < 0 ? order.length : leftRank;
      final normalizedRight = rightRank < 0 ? order.length : rightRank;
      final rank = normalizedLeft.compareTo(normalizedRight);
      return rank != 0 ? rank : left.compareTo(right);
    });
    return sports;
  }

  Map<String, int> get _selectedSportCategoryCounts {
    if (_selectedSite == 'ALL' || _selectedSiteSport.isEmpty) {
      return _categoryCounts;
    }
    final backendCounts = _siteSportCategoryCounts[_selectedSiteSport];
    if (backendCounts != null && backendCounts.isNotEmpty) {
      return backendCounts;
    }
    final counts = <String, int>{};
    for (final prop in _siteInventoryProps) {
      if (_normalizeSport(prop.sport) != _selectedSiteSport) {
        continue;
      }
      final category = _marketCategory(prop);
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get _selectedSportTotalCategoryCounts {
    if (_selectedSite == 'ALL' || _selectedSiteSport.isEmpty) {
      return _totalCategoryCounts.isNotEmpty
          ? _totalCategoryCounts
          : _categoryCounts;
    }
    return _siteTotalSportCategoryCounts[_selectedSiteSport] ??
        _selectedSportCategoryCounts;
  }

  Map<String, int> get _selectedSportPlayableCategoryCounts {
    if (_selectedSite == 'ALL' || _selectedSiteSport.isEmpty) {
      return _playableCategoryCounts.isNotEmpty
          ? _playableCategoryCounts
          : _categoryCounts;
    }
    final backendCounts = _sitePlayableSportCategoryCounts[_selectedSiteSport];
    if (backendCounts != null) return backendCounts;
    final counts = <String, int>{};
    for (final prop in _siteInventoryProps) {
      if (!prop.isSelectable ||
          !prop.verdict.actionable ||
          _normalizeSport(prop.sport) != _selectedSiteSport) {
        continue;
      }
      final category = _marketCategory(prop);
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return counts;
  }

  String get _effectiveSelectedCategory {
    return _currentCategories.contains(_selectedCategory)
        ? _selectedCategory
        : 'ALL';
  }

  String _propMarket(PropData prop) {
    final candidates = [
      prop.market,
      prop.marketName,
      prop.statType,
      prop.category,
      prop.propType,
      prop.displayMarket,
      prop.marketKey,
    ];
    return candidates.firstWhere(
      (value) =>
          value.trim().isNotEmpty &&
          !const {
            'other',
            'unknown',
            'n/a',
            'na',
          }.contains(value.trim().toLowerCase()),
      orElse: () => '',
    );
  }

  String _categoryFromApi(PropData prop) {
    return normalizedApiCategory(prop);
  }

  String _marketCategory(PropData prop) {
    final backendCategory = _categoryFromApi(prop);
    if (backendCategory.isNotEmpty) {
      return backendCategory;
    }
    return marketCategoryFor(_normalizeSport(prop.sport), _propMarket(prop));
  }

  List<PropData> get _propsBeforeCategoryFilter {
    final selectedSport =
        _selectedSite != 'ALL' && _selectedSiteSport.isNotEmpty
        ? _selectedSiteSport
        : _normalizeSport(widget.sportFilter);
    final selectedSite = _normalizeSite(_selectedSite);
    final searchText = _searchQuery;

    return _latestProps.where((prop) {
      final propSport = _normalizeSport(prop.sport);
      final sportMatches = selectedSport == 'ALL' || propSport == selectedSport;
      final propSite = _normalizeSite(
        '${prop.sportsbook} ${prop.sourceProvider}',
      );
      final siteMatches = selectedSite == 'ALL' || propSite == selectedSite;
      final market = _propMarket(prop).toLowerCase();
      final searchMatches =
          searchText.isEmpty ||
          prop.player.toLowerCase().contains(searchText) ||
          market.contains(searchText);
      return sportMatches && siteMatches && searchMatches;
    }).toList();
  }

  List<PropData> get _visibleProps {
    final base = _propsBeforeCategoryFilter;
    if (_effectiveSelectedCategory == 'ALL') {
      return base;
    }
    return base
        .where((prop) => _marketCategory(prop) == _effectiveSelectedCategory)
        .toList();
  }

  Future<void> _showPlayerPropsOverlay(PropData focused) async {
    setState(() => _focusedProp = focused);
    List<PropData> playerProps;
    try {
      final fetched = await _apiService.fetchProps(
        selectedSportsbook: focused.sportsbook,
        selectedSport: focused.sport,
        search: focused.player,
        sortBy: 'time',
        limit: 500,
      );
      final playerKey = focused.player.trim().toLowerCase();
      final siteKey = _normalizeSite(focused.sportsbook);
      playerProps = fetched
          .where(
            (prop) =>
                prop.player.trim().toLowerCase() == playerKey &&
                _normalizeSite('${prop.sportsbook} ${prop.sourceProvider}') ==
                    siteKey,
          )
          .toList(growable: false);
    } catch (_) {
      playerProps = _latestProps
          .where(
            (prop) =>
                prop.player.trim().toLowerCase() ==
                    focused.player.trim().toLowerCase() &&
                _normalizeSite('${prop.sportsbook} ${prop.sourceProvider}') ==
                    _normalizeSite(focused.sportsbook),
          )
          .toList(growable: false);
    }
    if (!mounted) return;
    playerProps = activePropsInChronologicalOrder(playerProps);
    if (playerProps.isEmpty && focused.isSelectable) playerProps = [focused];
    playerProps.sort((a, b) {
      final leftStart = propScheduledStart(a);
      final rightStart = propScheduledStart(b);
      if (leftStart == null && rightStart == null) {
        return _propMarket(a).compareTo(_propMarket(b));
      }
      if (leftStart == null) return 1;
      if (rightStart == null) return -1;
      final time = leftStart.compareTo(rightStart);
      return time != 0 ? time : _propMarket(a).compareTo(_propMarket(b));
    });

    final overlayScrollController = ScrollController();
    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .66),
        builder: (dialogContext) {
          final mobile = MediaQuery.sizeOf(dialogContext).width < 600;
          return SafeArea(
            minimum: EdgeInsets.all(mobile ? 6 : 0),
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: mobile
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                key: const ValueKey('same-player-props-overlay'),
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 680,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF071520).withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: app_colors.AppColors.gold,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: app_colors.AppColors.gold.withValues(alpha: .18),
                      blurRadius: 28,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person_search,
                            color: app_colors.AppColors.gold,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  focused.player,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '${focused.sportsbook.toUpperCase()} • ${playerProps.length} available props',
                                  style: const TextStyle(
                                    color: app_colors.AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(
                              Icons.close,
                              color: app_colors.AppColors.gold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      height: 1,
                      color: app_colors.AppColors.border,
                    ),
                    Expanded(
                      child: ListView.separated(
                        key: const ValueKey('same-player-props-scroll'),
                        controller: overlayScrollController,
                        primary: false,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(14),
                        itemCount: playerProps.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final prop = playerProps[index];
                          final start = DateTime.tryParse(
                            prop.startTimeUtc.isNotEmpty
                                ? prop.startTimeUtc
                                : prop.gameStartTime,
                          )?.toLocal();
                          final time = start == null
                              ? prop.displayTime
                              : '${start.month}/${start.day}/${start.year} '
                                    '${start.hour % 12 == 0 ? 12 : start.hour % 12}:'
                                    '${start.minute.toString().padLeft(2, '0')} '
                                    '${start.hour >= 12 ? 'PM' : 'AM'}';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0B1B27,
                              ).withValues(alpha: .78),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: app_colors.AppColors.border,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _propMarket(prop).toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${prop.matchup} • ${time.isEmpty ? 'Time pending' : time}',
                                            style: const TextStyle(
                                              color: app_colors
                                                  .AppColors
                                                  .textMuted,
                                              fontSize: 10,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            'Over ${prop.overOdds?.round() ?? '--'}  •  Under ${prop.underOdds?.round() ?? '--'}',
                                            style: const TextStyle(
                                              color:
                                                  app_colors.AppColors.silver,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: app_colors.AppColors.gold
                                            .withValues(alpha: .1),
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(
                                          color: app_colors.AppColors.gold,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _overlayModelLineMetric(
                                            'MODEL',
                                            prop.displayModelValue
                                                .toStringAsFixed(2),
                                            baseline: prop
                                                .displayModelIsMarketBaseline,
                                          ),
                                          const SizedBox(width: 10),
                                          _overlayModelLineMetric(
                                            'LINE',
                                            prop.line.toStringAsFixed(1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        key: ValueKey(
                                          'player-overlay-over-${prop.id}',
                                        ),
                                        onPressed: prop.dataStale
                                            ? null
                                            : () {
                                                Navigator.pop(dialogContext);
                                                widget.onSelect(
                                                  prop,
                                                  PickSide.over,
                                                );
                                              },
                                        icon: const Icon(
                                          Icons.arrow_upward_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          'SELECT OVER ${prop.line.toStringAsFixed(1)}',
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF7EE787,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFF4CAF50),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        key: ValueKey(
                                          'player-overlay-under-${prop.id}',
                                        ),
                                        onPressed: prop.dataStale
                                            ? null
                                            : () {
                                                Navigator.pop(dialogContext);
                                                widget.onSelect(
                                                  prop,
                                                  PickSide.under,
                                                );
                                              },
                                        icon: const Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          'SELECT UNDER ${prop.line.toStringAsFixed(1)}',
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFFFF8A93,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFEF5350),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
                      child: Text(
                        'Live lines and prices can move. Confirm the current number on the listed prop site before completing a ticket.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: app_colors.AppColors.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      overlayScrollController.dispose();
    }
  }

  Widget _overlayModelLineMetric(
    String label,
    String value, {
    bool baseline = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: app_colors.AppColors.textMuted,
            fontSize: 8,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: app_colors.AppColors.gold,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (baseline)
          const Text(
            'BASELINE',
            style: TextStyle(
              color: app_colors.AppColors.textMuted,
              fontSize: 6,
            ),
          ),
      ],
    );
  }

  // ignore: unused_element
  Future<void> _showPropAlertsOverlay(List<PropData> visibleProps) async {
    if (_propAlerts.isEmpty) {
      await _loadPropAlerts(fallbackProps: visibleProps);
    }
    if (!mounted) {
      return;
    }

    final alerts = _propAlerts.isNotEmpty
        ? _propAlerts
        : _fallbackPropAlertsFromProps(visibleProps);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: isMobile ? screenWidth * 0.94 : 950,
            height: isMobile ? 620 : 720,
            decoration: BoxDecoration(
              color: app_colors.AppColors.bgBase.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: app_colors.AppColors.gold, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: app_colors.AppColors.gold.withValues(alpha: 0.25),
                  blurRadius: 32,
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        color: app_colors.AppColors.gold,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Prop Alerts',
                          style: TextStyle(
                            color: app_colors.AppColors.gold,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        icon: const Icon(
                          Icons.close,
                          color: app_colors.AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: app_colors.AppColors.gold.withValues(alpha: 0.25),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: alerts.length,
                    itemBuilder: (context, index) {
                      return PropAlertCard(alert: alerts[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoardSearchAndBooks(double availableWidth) {
    const allBooks = [
      'ALL',
      'PRIZEPICKS',
      'UNDERDOG',
      'FANDUEL',
      'PICK6',
      'DRAFTKINGS',
      'BETR',
    ];

    // A prop site with nothing on the board is not worth offering: the
    // filter returns an empty screen and reads as a fault rather than
    // as a quiet book. Counts come from the whole board, before the
    // sportsbook filter narrows it, so choosing one site does not hide
    // all the others.
    final bookCounts = ApiService().lastSportsbookCounts;
    final books = bookCounts.isEmpty
        ? allBooks
        : allBooks
              .where(
                (book) =>
                    book == 'ALL' ||
                    (bookCounts[book] ?? 0) > 0 ||
                    _selectedSite == book,
              )
              .toList(growable: false);
    final compactLayout = useCompactBoardControls(availableWidth);
    final primaryControlWidth = compactLayout
        ? compactBoardControlWidth(availableWidth)
        : 160.0;
    final shortControlLabels = primaryControlWidth < 132;
    final primaryControlPadding = EdgeInsets.symmetric(
      horizontal: shortControlLabels ? 6 : 13,
    );

    Widget playerSearchField({double? width}) {
      final field = TextField(
        controller: _searchController,
        key: ValueKey('player-search-input-$_searchFieldGeneration'),
        textInputAction: TextInputAction.search,
        onChanged: (value) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 250), () {
            if (!mounted) return;
            setState(() {
              _searchQuery = value.trim().toLowerCase();
              _focusedProp = null;
              _latestProps = const [];
              _lastUpdated = null;
            });
          });
        },
        decoration: InputDecoration(
          hintText: 'Search player, team, or market',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear player search',
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _searchFieldGeneration += 1;
                      _focusedProp = null;
                      _latestProps = const [];
                      _lastUpdated = null;
                    });
                  },
                  icon: const Icon(Icons.close, size: 17),
                ),
          filled: true,
          fillColor: app_colors.AppColors.sidebar,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: app_colors.AppColors.gold),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(
              color: app_colors.AppColors.gold,
              width: 1.4,
            ),
          ),
        ),
      );
      if (width == null) {
        return field;
      }
      return SizedBox(width: width, child: field);
    }

    Widget bookMark(String book) {
      if (book == 'ALL') {
        return const Icon(Icons.keyboard_arrow_down, size: 13);
      }
      final (letter, color) = switch (book) {
        'PRIZEPICKS' => ('P', const Color(0xFF9B5CFF)),
        'UNDERDOG' => ('U', app_colors.AppColors.gold),
        'FANDUEL' => ('F', const Color(0xFF1685F8)),
        'PICK6' => ('6', const Color(0xFF53D337)),
        'BETR' => ('B', const Color(0xFF34D399)),
        _ => ('D', const Color(0xFF8D4DFF)),
      };
      return Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          letter,
          style: const TextStyle(
            color: app_colors.AppColors.bgBase,
            fontSize: 7,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    void slideSites(double delta) {
      if (!_bookHorizontalController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) => slideSites(delta));
        return;
      }
      final target = (_bookHorizontalController.offset + delta).clamp(
        0.0,
        _bookHorizontalController.position.maxScrollExtent,
      );
      unawaited(
        _bookHorizontalController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }

    void selectSite(String book) {
      setState(() {
        _selectedSite = book;
        EngagementTracker.instance.recordProduct('SITE_FILTER');
        _selectedSiteSport = '';
        _selectedCategory = 'ALL';
        _siteInventoryProps = const [];
        _siteSportCounts = const {};
        _siteSportCategoryCounts = const {};
        _siteTotalSportCategoryCounts = const {};
        _sitePlayableSportCategoryCounts = const {};
        _providerCoverage = const {};
        _focusedProp = null;
        _latestProps = const [];
        _categoryCounts = const {};
        _totalCategoryCounts = const {};
        _playableCategoryCounts = const {};
        _lastUpdated = null;
      });
    }

    Widget buildAllSitesSelector(bool selected) {
      return PopupMenuButton<String>(
        key: const ValueKey('all-prop-sites-menu'),
        tooltip: 'Choose a prop site',
        onSelected: selectSite,
        color: app_colors.AppColors.sidebar,
        itemBuilder: (context) => [
          for (final option in books)
            PopupMenuItem<String>(
              value: option,
              child: Row(
                children: [
                  bookMark(option),
                  const SizedBox(width: 8),
                  Text(
                    option == 'ALL' ? 'All Prop Sites' : option,
                    style: TextStyle(
                      color: _selectedSite == option
                          ? app_colors.AppColors.gold
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: IgnorePointer(
          child: OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: selected
                  ? app_colors.AppColors.gold
                  : Colors.white,
              backgroundColor: selected
                  ? app_colors.AppColors.gold.withValues(alpha: .10)
                  : app_colors.AppColors.sidebar,
              side: BorderSide(
                color: selected
                    ? app_colors.AppColors.gold
                    : app_colors.AppColors.border,
              ),
              padding: primaryControlPadding,
              fixedSize: Size(primaryControlWidth, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedSite != 'ALL') ...[
                  bookMark(_selectedSite),
                  const SizedBox(width: 6),
                ],
                Text(
                  _selectedSite == 'ALL'
                      ? shortControlLabels
                            ? 'SITES'
                            : 'All Prop Sites'
                      : _selectedSite,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.keyboard_arrow_down, size: 13),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildSiteButton(String book) {
      final selected = _selectedSite == book;
      if (book == 'ALL') {
        return buildAllSitesSelector(selected);
      }
      return OutlinedButton(
        onPressed: () => selectSite(book),
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? app_colors.AppColors.gold : Colors.white,
          backgroundColor: selected
              ? app_colors.AppColors.gold.withValues(alpha: .10)
              : app_colors.AppColors.sidebar,
          side: BorderSide(
            color: selected
                ? app_colors.AppColors.gold
                : app_colors.AppColors.border,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            bookMark(book),
            const SizedBox(width: 6),
            Text(
              book,
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    final siteBarItems = <Widget>[
      if (!compactLayout)
        SizedBox(
          key: const ValueKey('board-player-search'),
          width: 190,
          child: playerSearchField(),
        ),
      if (compactLayout) buildAllSitesSelector(_selectedSite == 'ALL'),
      Tooltip(
        message: 'Open PROP CHAT and join the community.',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('board-prop-chat-button'),
              onPressed: () => widget.onSelectPage?.call(AppPage.propChat),
              icon: Icon(
                Icons.forum_rounded,
                size: shortControlLabels ? 14 : 17,
              ),
              label: Text(
                shortControlLabels ? 'CHAT' : 'PROP CHAT',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: app_colors.AppColors.gold,
                backgroundColor: app_colors.AppColors.gold.withValues(
                  alpha: .08,
                ),
                side: const BorderSide(color: app_colors.AppColors.gold),
                padding: primaryControlPadding,
                fixedSize: Size(primaryControlWidth, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
            const Positioned(right: -7, top: -7, child: ChatUnreadBadge()),
          ],
        ),
      ),
      OutlinedButton.icon(
        key: const ValueKey('board-filter-button'),
        onPressed: _showBoardFilterOptions,
        icon: Icon(
          Icons.filter_alt_outlined,
          size: shortControlLabels ? 12 : 14,
        ),
        label: Text(
          _activeBoardFilterLabels().isEmpty
              ? 'FILTERS'
              : 'FILTERS ${_activeBoardFilterLabels().length}',
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: app_colors.AppColors.gold,
          backgroundColor: app_colors.AppColors.gold.withValues(alpha: .10),
          side: const BorderSide(color: app_colors.AppColors.gold),
          padding: primaryControlPadding,
          fixedSize: Size(primaryControlWidth, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      if (!compactLayout) ...books.map(buildSiteButton),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compactLayout) ...[
          SizedBox(
            key: const ValueKey('board-player-search'),
            child: playerSearchField(),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (!compactLayout)
              IconButton(
                key: const ValueKey('prop-sites-scroll-left'),
                tooltip: 'Previous prop sites',
                onPressed: () => slideSites(-240),
                style: IconButton.styleFrom(
                  backgroundColor: app_colors.AppColors.gold.withValues(
                    alpha: .12,
                  ),
                  side: const BorderSide(color: app_colors.AppColors.gold),
                  minimumSize: const Size(38, 42),
                ),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: app_colors.AppColors.gold,
                  size: 16,
                ),
              ),
            Expanded(
              child: SizedBox(
                height: 48,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    if (!_bookHorizontalController.hasClients) return;
                    final target =
                        (_bookHorizontalController.offset - details.delta.dx)
                            .clamp(
                              0.0,
                              _bookHorizontalController
                                  .position
                                  .maxScrollExtent,
                            );
                    _bookHorizontalController.jumpTo(target);
                  },
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent ||
                          !_bookHorizontalController.hasClients) {
                        return;
                      }
                      final delta =
                          event.scrollDelta.dy.abs() >=
                              event.scrollDelta.dx.abs()
                          ? event.scrollDelta.dy
                          : event.scrollDelta.dx;
                      if (delta == 0) return;
                      final target = (_bookHorizontalController.offset + delta)
                          .clamp(
                            0.0,
                            _bookHorizontalController.position.maxScrollExtent,
                          );
                      unawaited(
                        _bookHorizontalController.animateTo(
                          target,
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOutCubic,
                        ),
                      );
                    },
                    child: Scrollbar(
                      controller: _bookHorizontalController,
                      thumbVisibility: !compactLayout,
                      trackVisibility: !compactLayout,
                      interactive: true,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      thickness: 4,
                      radius: const Radius.circular(99),
                      child: ListView.separated(
                        key: const ValueKey('prop-sites-scroll-list'),
                        controller: _bookHorizontalController,
                        physics: compactLayout
                            ? const NeverScrollableScrollPhysics()
                            : const AlwaysScrollableScrollPhysics(),
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.only(bottom: compactLayout ? 0 : 6),
                        itemCount: siteBarItems.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, index) => siteBarItems[index],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!compactLayout)
              IconButton(
                key: const ValueKey('prop-sites-scroll-right'),
                tooltip: 'More prop sites',
                onPressed: () => slideSites(240),
                style: IconButton.styleFrom(
                  backgroundColor: app_colors.AppColors.gold.withValues(
                    alpha: .12,
                  ),
                  side: const BorderSide(color: app_colors.AppColors.gold),
                  minimumSize: const Size(38, 42),
                ),
                icon: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: app_colors.AppColors.gold,
                  size: 16,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // Retained for reference while the per-prop E+ intelligence panels are
  // validated in production.
  // ignore: unused_element
  Widget _buildBoardIntelligence() {
    if (!AuthManager.instance.sessionState.value.hasEdgeAccess) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: app_colors.AppColors.sidebar,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: app_colors.AppColors.silver),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.view_list_outlined,
                  color: app_colors.AppColors.silver,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CORE MARKET BOARD • ${_visibleProps.length} AVAILABLE PROPS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: app_colors.AppColors.silver,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  const Flexible(
                    child: Text(
                      'PRO unlocks projections, confidence and edge ranking',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: app_colors.AppColors.textMuted,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }
    final focusedProp = _focusedProp;
    final selectedProps = <String, PropData>{
      for (final selection in widget.selections)
        selection.prop.id: selection.prop,
    }.values.toList(growable: false);
    // Once a user adds props, the intelligence row summarizes the active
    // selection instead of remaining pinned to whichever card was last
    // focused. With no active selection, a card tap still opens the focused
    // single-prop view.
    final props = boardIntelligenceScope(
      selections: widget.selections,
      visibleProps: _visibleProps,
      focusedProp: focusedProp,
    );
    final showingFocusedProp = focusedProp != null && selectedProps.isEmpty;
    // Edge requires a real model projection - recommendationEdge/edge default
    // to exactly 0.0 (not "unknown") when no projection was supplied, so a
    // near-zero value here genuinely means "no edge data," not "zero edge."
    final focusedEdgeAvailable =
        focusedProp?.projection != null ||
        (focusedProp?.recommendationEdge ?? 0).abs() > .0001;
    // Confidence/hit rate is computed independently of edge and is populated
    // for virtually every prop, so it shouldn't be hidden just because edge
    // happens to be unavailable - matches the unfocused "HIGHEST HIT RATE"
    // tile below, which already shows confidence unconditionally.
    final focusedConfidenceAvailable =
        focusedProp?.displayConfidenceRating != null;
    final metricScope = selectedProps.isNotEmpty
        ? 'Across ${selectedProps.length} selected'
        : 'Across visible props';
    final modeledProps = props
        .where(
          (prop) =>
              prop.proSuggestionUsesModel ||
              prop.projection != null ||
              prop.recommendationEdge.abs() > .0001,
        )
        .toList(growable: false);
    final top = modeledProps.isEmpty
        ? null
        : ([...modeledProps]..sort(
                (a, b) =>
                    (b.calculatedEdge ?? 0).compareTo(a.calculatedEdge ?? 0),
              ))
              .first;
    final averageEdge = modeledProps.isEmpty
        ? null
        : modeledProps.fold<double>(
                0,
                (sum, prop) => sum + (prop.calculatedEdge ?? 0),
              ) /
              modeledProps.length;
    final confidenceProps = modeledProps
        .where((prop) => prop.displayConfidenceRating != null)
        .toList(growable: false);
    final hitLeader = confidenceProps.isEmpty
        ? null
        : ([...confidenceProps]..sort(
                (a, b) => (b.displayConfidenceRating ?? -1).compareTo(
                  a.displayConfidenceRating ?? -1,
                ),
              ))
              .first;
    final entries = showingFocusedProp
        ? <(String, String, String)>[
            (
              'PLAYER',
              focusedProp.player,
              '${focusedProp.sport} • ${focusedProp.sportsbook}',
            ),
            (
              'EDGE',
              focusedEdgeAvailable
                  ? '${focusedProp.edge >= 0 ? '+' : ''}${focusedProp.edge.toStringAsFixed(2)}%'
                  : '--',
              focusedEdgeAvailable
                  ? 'Model edge for this prop'
                  : 'Awaiting model projection',
            ),
            (
              'HIT RATE',
              focusedConfidenceAvailable
                  ? focusedProp.displayConfidenceLabel
                  : '--',
              focusedConfidenceAvailable
                  ? 'Current model confidence'
                  : 'Awaiting model projection',
            ),
            (
              'PROP',
              _marketCategory(focusedProp),
              '${focusedProp.line.toStringAsFixed(1)} • ${focusedProp.proSuggestedSide ?? 'NO PICK'}',
            ),
            (
              'LAST UPDATED',
              _formatLastUpdated(_lastUpdated),
              _formatLocalDate(DateTime.now()),
            ),
          ]
        : <(String, String, String)>[
            (
              'TOP EDGE',
              top?.player ?? 'Awaiting projection',
              top == null
                  ? '--'
                  : '${top.edge >= 0 ? '+' : ''}${top.edge.toStringAsFixed(2)}%',
            ),
            (
              'AVG EDGE',
              averageEdge == null
                  ? '--'
                  : '${averageEdge >= 0 ? '+' : ''}${averageEdge.toStringAsFixed(2)}%',
              metricScope,
            ),
            (
              'HIGHEST HIT RATE',
              hitLeader?.player ?? '--',
              hitLeader == null ? '--' : hitLeader.displayConfidenceLabel,
            ),
            (
              'PROPS WITH EDGE',
              '${modeledProps.where((p) => p.edge > 0).length}',
              selectedProps.isNotEmpty
                  ? '${selectedProps.length} selected'
                  : '${modeledProps.length} modeled',
            ),
            (
              'LAST UPDATED',
              _formatLastUpdated(_lastUpdated),
              _formatLocalDate(DateTime.now()),
            ),
          ];
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: app_colors.AppColors.sidebar,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            Expanded(
              flex: i == 0 || i == 2 ? 3 : 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entries[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: app_colors.AppColors.textMuted,
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entries[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (i == 0 || i == 2)
                          const SizedBox(
                            width: 40,
                            height: 20,
                            child: CustomPaint(
                              painter: _BoardSparklinePainter(),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entries[i].$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: i < 3
                            ? const Color(0xFF62E34F)
                            : app_colors.AppColors.textMuted,
                        fontSize: 7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < entries.length - 1)
              Container(
                width: 1,
                height: 44,
                color: app_colors.AppColors.border,
              ),
          ],
          OutlinedButton.icon(
            onPressed: _showBoardFilterOptions,
            icon: const Icon(Icons.filter_alt_outlined, size: 14),
            label: const Text('Filter Options', style: TextStyle(fontSize: 8)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: app_colors.AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 9),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  List<String> _activeBoardFilterLabels() {
    final labels = <String>[];
    if (_searchQuery.isNotEmpty) {
      labels.add('SEARCH: ${_searchController.text.trim()}');
    }
    if (_selectedSite != 'ALL') labels.add(_selectedSite);
    if (_selectedSiteSport.isNotEmpty) labels.add(_selectedSiteSport);
    final category = _effectiveSelectedCategory;
    if (category != 'ALL') labels.add(category);
    const verdictLabels = {
      'ACTIONABLE': 'PLAYABLE',
      'PLAY_NOW': 'PLAY NOW',
      'SHOP': 'SHOP',
      'LEAN': 'LEAN',
      'WAIT': 'WAIT',
    };
    // ALL PROPS is the board's normal starting state, so the selected tab is
    // enough feedback; repeating it here makes the default look filtered.
    final verdict = _verdictFilter == 'ALL'
        ? null
        : verdictLabels[_verdictFilter];
    if (verdict != null) labels.add(verdict);
    if (_sortBy != 'time') labels.add('SORT: ${_sortBy.toUpperCase()}');
    if (_minConfidence > 0) labels.add('CONFIDENCE $_minConfidence+');
    return labels;
  }

  void _clearBoardFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchFieldGeneration += 1;
      _selectedSite = 'ALL';
      _selectedSiteSport = '';
      _selectedCategory = 'ALL';
      _minConfidence = 0;
      _sortBy = 'time';
      _verdictFilter = 'ALL';
      _siteInventoryProps = const [];
      _siteSportCounts = const {};
      _siteSportCategoryCounts = const {};
      _providerCoverage = const {};
      _focusedProp = null;
      _latestProps = const [];
      _categoryCounts = const {};
      _lastUpdated = null;
    });
  }

  Widget _buildActiveBoardFilters() => ActiveBoardFilters(
    labels: _activeBoardFilterLabels(),
    onClearAll: _clearBoardFilters,
  );
  Future<void> _showBoardFilterOptions() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: app_colors.AppColors.sidebar,
        title: const Text(
          'Filter Options',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        children: [
          RadioGroup<String>(
            groupValue: _sortBy,
            onChanged: (value) => Navigator.pop(dialogContext, value),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: 'verdict',
                  activeColor: app_colors.AppColors.gold,
                  title: Text(
                    'PI Verdict (plays first)',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                RadioListTile<String>(
                  value: 'source',
                  activeColor: app_colors.AppColors.gold,
                  title: Text(
                    'Board order',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                RadioListTile<String>(
                  value: 'edge',
                  activeColor: app_colors.AppColors.gold,
                  title: Text(
                    'Highest edge',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
                RadioListTile<String>(
                  value: 'trust',
                  activeColor: app_colors.AppColors.gold,
                  title: Text(
                    'Highest PI Trust',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      setState(() => _sortBy = selected);
    }
  }

  /// The row that turns two thousand props into the ones worth acting on.
  ///
  /// PLAYABLE is deliberately first and deliberately broad: it is every
  /// verdict the model would actually stand behind -- plays, prices worth
  /// shopping, and leans -- rather than PLAY NOW alone. A reader who only
  /// ever taps this one chip should still see everything actionable.
  Widget _buildVerdictFilter() {
    return VerdictFilterBar(
      selected: _verdictFilter,
      countFor: (value) => resolveVerdictFilterCount(_verdictCounts, value),
      shouldWrap: shouldWrapVerdictFilters,
      onSelected: (value) {
        EngagementTracker.instance.recordProduct('VERDICT_FILTER');
        setState(() => _verdictFilter = value);
      },
      onShowGuide: () => ProductOnboarding.showDecisionGuide(context),
    );
  }

  String get _boardSortLabel => switch (_sortBy) {
    'edge' => 'Highest edge',
    'trust' => 'Best PI score',
    _ => 'Starting soon',
  };

  String get _boardUpdatedLabel {
    final updated = _lastUpdated;
    if (updated == null) return 'Updating results';
    final elapsed = DateTime.now().difference(updated);
    if (elapsed.inMinutes < 1) return 'Updated just now';
    if (elapsed.inMinutes < 60) {
      return 'Updated ${elapsed.inMinutes}m ago';
    }
    return 'Updated ${elapsed.inHours}h ago';
  }

  Widget _buildBoardResultsSummary() {
    final resultCount = _latestProps.length;
    return Semantics(
      liveRegion: true,
      label:
          '$resultCount results. Sorted by $_boardSortLabel. $_boardUpdatedLabel.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: app_colors.AppColors.sidebar,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: app_colors.AppColors.border),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$resultCount RESULTS',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              '•',
              style: TextStyle(color: app_colors.AppColors.textMuted),
            ),
            Text(
              'SORTED BY $_boardSortLabel'.toUpperCase(),
              style: const TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              '•',
              style: TextStyle(color: app_colors.AppColors.textMuted),
            ),
            Text(
              _boardUpdatedLabel.toUpperCase(),
              style: const TextStyle(
                color: app_colors.AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProviderReliabilityDetails() {
    if (_providerReliability.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: app_colors.AppColors.background,
      isScrollControlled: true,
      builder: (_) =>
          ProviderReliabilitySheet(reliability: _providerReliability),
    );
  }

  Widget _buildProviderReliabilityBanner() {
    final issue = _selectedSite == 'ALL'
        ? null
        : providerCoverageIssueForSport(
            _providerCoverage,
            _selectedSiteSport,
            _effectiveSelectedCategory,
          );
    return ProviderReliabilityBanner(
      reliability: _providerReliability,
      selectedSite: _selectedSite,
      coverageIssue: issue,
      onDetails: _providerReliability.isEmpty
          ? null
          : _showProviderReliabilityDetails,
    );
  }

  Widget _buildBoardCategories() {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final railHeight = boardFilterRailHeight(viewportWidth);
    final categories = _currentCategories;
    IconData categoryIcon(String category) => switch (category) {
      'ALL' => Icons.grid_view_rounded,
      'POINTS' => Icons.control_point_rounded,
      'REBOUNDS' => Icons.sports_basketball,
      'ASSISTS' => Icons.hub_outlined,
      'PRA' => Icons.person_pin_circle_outlined,
      'PTS+REBS+ASTS' => Icons.account_tree_outlined,
      'BLOCKS+STEALS' => Icons.swap_calls_rounded,
      '3PT MADE' => Icons.adjust_rounded,
      _ => Icons.apps,
    };
    final totalCounts = _selectedSportTotalCategoryCounts;
    final playableCounts = _selectedSportPlayableCategoryCounts;
    int totalCount(String category) => category == 'ALL'
        ? totalCounts.values.fold<int>(0, (sum, count) => sum + count)
        : totalCounts[category] ?? 0;
    int playableCount(String category) => category == 'ALL'
        ? playableCounts.values.fold<int>(0, (sum, count) => sum + count)
        : playableCounts[category] ?? 0;
    return SizedBox(
      height: railHeight,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              controller: _categoryHorizontalController,
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = _effectiveSelectedCategory == category;
                return BoardCategoryChip(
                  category: category,
                  count: totalCount(category),
                  playableCount: playableCount(category),
                  icon: categoryIcon(category),
                  selected: selected,
                  onPressed: () => setState(() {
                    _selectedCategory = category;
                    // Category chips represent the complete market inventory.
                    // Do not carry the board's default PLAYABLE filter into a
                    // category such as STRIKEOUTS, otherwise valid Lean, Wait,
                    // and No Pick props disappear even though the chip count
                    // correctly includes them.
                    _verdictFilter = 'ALL';
                    _focusedProp = null;
                    _latestProps = const [];
                    _lastUpdated = null;
                  }),
                );
              },
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: boardRailArrowWidth(viewportWidth),
            height: railHeight,
            child: OutlinedButton(
              onPressed: () {
                if (!_categoryHorizontalController.hasClients) return;
                final target = (_categoryHorizontalController.offset + 220)
                    .clamp(
                      0.0,
                      _categoryHorizontalController.position.maxScrollExtent,
                    )
                    .toDouble();
                _categoryHorizontalController.animateTo(
                  target,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              },
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: const BorderSide(color: app_colors.AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              child: const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardSports() {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final sports = _availableSiteSports;
    if (sports.isEmpty) {
      return const SizedBox.shrink();
    }
    int sportCount(String sport) =>
        _siteSportCounts[sport] ??
        _siteInventoryProps
            .where(
              (prop) =>
                  prop.isSelectable && _normalizeSport(prop.sport) == sport,
            )
            .length;
    IconData sportIcon(String sport) => switch (sport) {
      'NFL' => Icons.sports_football,
      'NBA' || 'WNBA' => Icons.sports_basketball,
      'MLB' => Icons.sports_baseball,
      'NHL' => Icons.sports_hockey,
      'PGA' => Icons.sports_golf,
      'UFC' => Icons.sports_mma,
      'TENNIS' => Icons.sports_tennis,
      'SOCCER' => Icons.sports_soccer,
      _ => Icons.emoji_events_outlined,
    };
    return SizedBox(
      height: boardFilterRailHeight(viewportWidth),
      child: ListView.separated(
        key: const ValueKey('prop-site-sport-tabs'),
        controller: _sportHorizontalController,
        scrollDirection: Axis.horizontal,
        itemCount: sports.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final sport = sports[index];
          final selected = sport == _selectedSiteSport;
          return OutlinedButton.icon(
            key: ValueKey('prop-site-sport-$sport'),
            onPressed: () => setState(() {
              _selectedSiteSport = sport;
              _selectedCategory = 'ALL';
              _focusedProp = null;
            }),
            icon: Icon(sportIcon(sport), size: 14),
            label: Text('$sport  ${sportCount(sport)}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: selected
                  ? app_colors.AppColors.sidebar
                  : Colors.white,
              backgroundColor: selected
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.sidebar,
              side: BorderSide(
                color: selected
                    ? app_colors.AppColors.gold
                    : app_colors.AppColors.border,
                width: selected ? 1.4 : 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              textStyle: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardViewportWidth = MediaQuery.sizeOf(context).width;
    final sectionGap = boardSectionGap(boardViewportWidth);
    final alertsForPage = _propAlerts.isNotEmpty
        ? _propAlerts
        : _fallbackPropAlertsFromProps(_latestProps);
    return Container(
      color: app_colors.AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: widget.selectedPage == AppPage.searchPlayers
                ? SearchPlayersPage(props: _latestProps)
                : widget.selectedPage == AppPage.gameMarkets
                ? GameMarketsScreen(onAddToSlip: widget.onAddGameMarket)
                : widget.selectedPage == AppPage.evScanner
                ? _buildEvScanner()
                : widget.selectedPage == AppPage.scoreboard
                ? const LiveScoreboardTickerGridWidget()
                : widget.selectedPage == AppPage.scoreboardWatchlist
                ? const LiveScoreboardTickerGridWidget(watchedOnly: true)
                : widget.selectedPage == AppPage.propAlerts
                ? PropAlertsPage(alerts: alertsForPage)
                : widget.selectedPage == AppPage.briefing
                ? const BriefingPage()
                : widget.selectedPage == AppPage.trackRecord
                ? const TrackRecordPage()
                : widget.selectedPage == AppPage.analytics
                ? AnalyticsAdminWorkspace(selectedSport: widget.sportFilter)
                : widget.selectedPage == AppPage.lineMovement
                ? LineMovementPage(
                    selectedSport: widget.sportFilter,
                    hasProAccess:
                        AuthManager.instance.sessionState.value.hasEdgeAccess,
                  )
                : widget.selectedPage == AppPage.injuryImpact
                ? InjuryImpactPage(props: _latestProps, alerts: _injuryAlerts)
                : widget.selectedPage == AppPage.dataAdmin
                ? AnalyticsAdminWorkspace(
                    selectedSport: widget.sportFilter,
                    startInDataAdmin: true,
                  )
                : widget.selectedPage == AppPage.ownerOperations
                ? const OwnerOperationsPage()
                : widget.selectedPage == AppPage.intelligenceLab
                ? IntelligenceLabPage(
                    selections: widget.selections,
                    onRemove: widget.onRemoveLabSelection,
                    onClear: widget.onClearLabSelections,
                  )
                : widget.selectedPage == AppPage.refereeTracker
                ? const RefereeTrackerPage()
                : widget.selectedPage == AppPage.propChat
                ? PropChatPage(
                    onPopOut: widget.onFloatChat,
                    onShowBubble: widget.onShowChatBubble,
                    isBubbleVisible: widget.isChatBubbleVisible,
                    sharedAnalysis: {
                      'kind': widget.selections.length == 1 ? 'prop' : 'slip',
                      'title': widget.selections.length == 1
                          ? 'Prop analysis'
                          : '${widget.selections.length}-leg slip',
                      'legs': widget.selections
                          .map(
                            (selection) => {
                              'player': selection.prop.player,
                              'market': selection.prop.propType,
                              'side': selection.sideLabel,
                              'line': selection.prop.line,
                              'odds': selection.odds,
                            },
                          )
                          .toList(growable: false),
                    },
                  )
                : Scrollbar(
                    controller: _boardVerticalController,
                    thumbVisibility: usePersistentBoardScrollbar(
                      boardViewportWidth,
                    ),
                    trackVisibility: usePersistentBoardScrollbar(
                      boardViewportWidth,
                    ),
                    interactive: usePersistentBoardScrollbar(
                      boardViewportWidth,
                    ),
                    thickness: boardScrollbarThickness(boardViewportWidth),
                    radius: const Radius.circular(8),
                    scrollbarOrientation: ScrollbarOrientation.right,
                    child: SingleChildScrollView(
                      controller: _boardVerticalController,
                      primary: false,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: boardContentPadding(boardViewportWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) =>
                                _buildBoardSearchAndBooks(constraints.maxWidth),
                          ),
                          SizedBox(height: sectionGap),
                          _buildProviderReliabilityBanner(),
                          SizedBox(height: sectionGap),
                          if (_selectedSite != 'ALL') ...[
                            _buildBoardSports(),
                            SizedBox(height: sectionGap),
                          ],
                          _buildBoardCategories(),
                          SizedBox(height: sectionGap),
                          /*Text(
                            '${visibleProps.length} visible props • $_propCount total loaded',
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),*/
                          if (canShowSystemRecommendation(
                            hasEdgeAccess: AuthManager
                                .instance
                                .sessionState
                                .value
                                .hasEdgeAccess,
                          )) ...[
                            _buildVerdictFilter(),
                            SizedBox(height: sectionGap),
                          ],
                          if (_activeBoardFilterLabels().isNotEmpty) ...[
                            _buildActiveBoardFilters(),
                            SizedBox(height: sectionGap),
                          ],
                          _buildBoardResultsSummary(),
                          SizedBox(height: sectionGap),
                          PropGrid(
                            selections: widget.selections,
                            onSelect: (prop, side) {
                              setState(() => _focusedProp = prop);
                              widget.onSelect(prop, side);
                            },
                            onPropFocused: _showPlayerPropsOverlay,
                            refreshListenable: widget.refreshRequestNotifier,
                            onStartupLog: widget.onStartupLog,
                            sportFilter: _selectedSite == 'ALL'
                                ? widget.sportFilter
                                : _selectedSiteSport.isEmpty
                                ? 'ALL'
                                : _selectedSiteSport,
                            displaySportFilter: _selectedSite == 'ALL'
                                ? widget.sportFilter
                                : _selectedSiteSport,
                            searchQuery: _searchQuery,
                            selectedSite: _selectedSite,
                            selectedCategory: _effectiveSelectedCategory,
                            selectedSide: _selectedSide,
                            selectedTier: _selectedTier,
                            minConfidence: _minConfidence,
                            sortBy: _sortBy,
                            verdictFilter: _verdictFilter,
                            onPropsLoaded: _handlePropsLoaded,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BoardSparklinePainter extends CustomPainter {
  const _BoardSparklinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = app_colors.AppColors.blue
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(0, size.height * .82)
      ..lineTo(size.width * .12, size.height * .58)
      ..lineTo(size.width * .25, size.height * .70)
      ..lineTo(size.width * .42, size.height * .25)
      ..lineTo(size.width * .57, size.height * .47)
      ..lineTo(size.width * .72, size.height * .18)
      ..lineTo(size.width * .86, size.height * .28)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Finds the most important live-feed coverage issue for the active sport.
@visibleForTesting
Map<String, dynamic>? providerCoverageIssueForSport(
  Map<String, dynamic> coverage,
  String sport, [
  String category = 'ALL',
]) {
  if (coverage['limited'] != true) return null;
  final normalizedSport = sport.trim().toUpperCase();
  final normalizedCategory = category.trim().toUpperCase();
  final issues = coverage['issues'];
  if (issues is! List) return null;
  Map<String, dynamic>? sportFallback;
  for (final rawIssue in issues) {
    if (rawIssue is! Map) continue;
    final issue = Map<String, dynamic>.from(rawIssue);
    if (issue['sport']?.toString().trim().toUpperCase() == normalizedSport) {
      sportFallback ??= issue;
      if (normalizedCategory != 'ALL' &&
          issue['category']?.toString().trim().toUpperCase() ==
              normalizedCategory) {
        return issue;
      }
    }
  }
  return normalizedCategory == 'ALL' ? sportFallback : null;
}

/// Builds the category rail from positive facets already scoped by site/sport.
@visibleForTesting
List<String> visibleCategoryFilters(Map<String, int> counts) {
  final available = counts.entries.where((entry) => entry.value > 0).toList()
    ..sort((left, right) {
      final countOrder = right.value.compareTo(left.value);
      return countOrder != 0 ? countOrder : left.key.compareTo(right.key);
    });
  return ['ALL', ...available.map((entry) => entry.key)];
}

@visibleForTesting
bool shouldWrapVerdictFilters(double availableWidth) {
  return availableWidth < 600;
}

/// Keeps the primary board controls focused until there is enough room for
/// search, utilities, provider shortcuts, and scroll affordances together.
@visibleForTesting
bool useCompactBoardControls(double availableWidth) {
  return availableWidth < 900;
}

/// Keeps the three primary compact controls equal-width and fully visible.
@visibleForTesting
double compactBoardControlWidth(double availableWidth) {
  return ((availableWidth - 12) / 3).clamp(84.0, 160.0).toDouble();
}

/// Reduces framing on phones and tablets without crowding card content.
@visibleForTesting
EdgeInsets boardContentPadding(double viewportWidth) {
  if (viewportWidth < 600) {
    return const EdgeInsets.fromLTRB(8, 8, 8, 16);
  }
  if (viewportWidth < 1000) {
    return const EdgeInsets.fromLTRB(10, 9, 10, 18);
  }
  return const EdgeInsets.fromLTRB(14, 12, 14, 22);
}

@visibleForTesting
double boardSectionGap(double viewportWidth) {
  if (viewportWidth < 600) return 6;
  if (viewportWidth < 1000) return 8;
  return 10;
}

@visibleForTesting
bool usePersistentBoardScrollbar(double viewportWidth) => viewportWidth >= 1000;

@visibleForTesting
double boardScrollbarThickness(double viewportWidth) {
  if (viewportWidth < 600) return 4;
  if (viewportWidth < 1000) return 5;
  return 9;
}

@visibleForTesting
double boardFilterRailHeight(double viewportWidth) =>
    viewportWidth < 600 ? 44 : 49;

@visibleForTesting
double boardRailArrowWidth(double viewportWidth) =>
    viewportWidth < 600 ? 38 : 42;

@visibleForTesting
int? resolveVerdictFilterCount(Map<String, int> counts, String value) {
  if (counts.isEmpty) {
    return null;
  }
  return counts[value] ?? 0;
}

@visibleForTesting
List<PropData> boardIntelligenceScope({
  required List<SlipSelection> selections,
  required List<PropData> visibleProps,
  PropData? focusedProp,
}) {
  final selectedProps = <String, PropData>{
    for (final selection in selections) selection.prop.id: selection.prop,
  }.values.toList(growable: false);
  if (selectedProps.isNotEmpty) return selectedProps;
  if (focusedProp != null) return <PropData>[focusedProp];
  return visibleProps;
}
