import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../services/board_filter_memory.dart';
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
import '../theme/app_spacing.dart';
import 'active_board_filters.dart';
import 'analytics_admin_workspace.dart';
import 'onboarding_dialog.dart';
import 'scoreboard_view.dart';
import 'ev_scanner_card.dart';
import 'prop_grid.dart';
import 'provider_reliability_banner.dart';
import 'prop_board_loading.dart';
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

/// Whether the board should carry its own sport tabs at this width.
///
/// Above the shell's 1000px breakpoint the sidebar rail is rendered inline
/// and already selects the sport, so a second control there costs a row of
/// vertical space to duplicate something already visible. Below it the rail
/// is a drawer behind the menu button, which leaves the board showing one
/// sport's categories as its primary cut with no way to change sport in
/// sight. One sport is not a choice, and a row that cannot change anything
/// is just a row.
bool wholeBoardSportsBelong({
  required double viewportWidth,
  required bool canSelectSport,
  required int sportsWithInventory,
}) {
  if (!canSelectSport) {
    return false;
  }
  if (viewportWidth >= 1000) {
    return false;
  }
  return sportsWithInventory >= 2;
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

  /// Changes the board's sport. Wired to the same handler the sidebar rail
  /// uses, so the two controls cannot disagree about what is selected.
  final ValueChanged<String>? onSelectSport;

  const MainDashboard({
    super.key,
    required this.selections,
    required this.onSelect,
    required this.onAddGameMarket,
    required this.onRemoveLabSelection,
    required this.onClearLabSelections,
    required this.onPropsRefreshed,
    required this.sportFilter,
    this.onSelectSport,
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
  final ScrollController _boardVerticalController = ScrollController();
  final ScrollController _bookHorizontalController = ScrollController();
  final ScrollController _categoryHorizontalController = ScrollController();
  final ScrollController _sportHorizontalController = ScrollController();
  Timer? _searchDebounce;
  String _searchQuery = '';
  String _selectedSite = 'PRIZEPICKS';
  String _selectedSiteSport = '';
  String _selectedCategory = 'ALL';
  bool _siteDiscoveryExpanded = false;
  String _selectedSide = 'All';
  final String _selectedTier = 'All';
  int _minConfidence = 0;
  String _sortBy = 'trust';
  // Inventory comes first: show every current site line and let PI rate it.
  // PLAYABLE remains an optional one-tap filter rather than silently hiding
  // WAIT/PASS props that users still expect to find on the board.
  String _verdictFilter = 'ALL';
  String _marketQuickFilter = 'TOP PI PICKS';
  DateTime? _lastUpdated;
  List<PropData> _latestProps = const [];
  List<PropData> _siteInventoryProps = const [];
  Map<String, Map<String, int>> _siteSportCategoryCounts = const {};
  Map<String, Map<String, int>> _siteTotalSportCategoryCounts = const {};
  Map<String, dynamic> _providerCoverage = const {};
  // The board is served from the durable snapshot: real lines, but
  // possibly hours old and otherwise indistinguishable from current ones.
  bool _feedIsRecovery = false;
  Map<String, dynamic> _providerReliability = const {};
  Map<String, int> _categoryCounts = const {};
  Map<String, int> _totalCategoryCounts = const {};
  Map<String, int> _verdictCounts = const {};
  List<PropData> _evScannerProps = const [];
  final TextEditingController _evSearchController = TextEditingController();
  String _evBook = 'ALL';
  String _evSort = 'EV';
  double _evMinimum = 0;
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

  Set<String> get _providersUnavailableForBoard {
    final rows = (_providerReliability['providers'] as List? ?? const [])
        .whereType<Map>();
    const unavailableStates = {'MISSING', 'STALE', 'OFFLINE', 'ERROR'};
    return {
      for (final row in rows)
        if (unavailableStates.contains(
          row['status']?.toString().trim().toUpperCase() ?? '',
        ))
          row['provider']?.toString().trim().toUpperCase() ?? '',
    }..remove('');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restorePreferredPropSite());
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

  Future<void> _restorePreferredPropSite() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences
        .getString('pi_market_board_preferred_site')
        ?.trim()
        .toUpperCase();
    if (!mounted || saved == null || saved.isEmpty) return;
    setState(() {
      _selectedSite = saved;
      _selectedSiteSport = '';
      _selectedCategory = 'ALL';
    });
  }

  Future<void> _rememberPreferredPropSite(String site) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('pi_market_board_preferred_site', site);
  }

  Future<void> _loadSelectedSiteSportCategoryCatalog(String sport) async {
    final site = _selectedSite;
    if (site == 'ALL' || sport.isEmpty) return;
    try {
      final counts = await _apiService.fetchSportCategoryCatalog(
        selectedSportsbook: site,
        selectedSport: sport,
      );
      if (!mounted || _selectedSite != site || _selectedSiteSport != sport) {
        return;
      }
      setState(() {
        _siteTotalSportCategoryCounts = {
          ..._siteTotalSportCategoryCounts,
          sport: counts,
        };
      });
    } catch (_) {
      // Keep the currently loaded categories available if a facet refresh fails.
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
        _selectedSiteSport = _selectedSite == 'ALL' ||
                widget.sportFilter.trim().toUpperCase() == 'ALL'
            ? ''
            : _normalizeSport(widget.sportFilter);
        _selectedCategory = 'ALL';
        _selectedSide = 'All';
        _verdictFilter = 'ALL';
        _marketQuickFilter = 'ALL';
        _latestProps = const [];
        _categoryCounts = const {};
        _totalCategoryCounts = const {};
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
            'Prop site: ${prop.sportsbook}\n'
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
      return const Padding(
        padding: EdgeInsets.all(18),
        child: PropLoadingSkeleton(),
      );
    }
    if (_evScannerError != null && _evScannerProps.isEmpty) {
      return PropLoadError(
        title: 'EV feed unavailable',
        message: _evScannerError!,
        onRetry: _loadEvScannerProps,
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
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
              decoration: BoxDecoration(
                color: app_colors.AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: app_colors.AppColors.border),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.filter_alt_off_outlined,
                      color: app_colors.AppColors.gold,
                      size: 34,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No props match these filters',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Broaden the EV threshold, prop site, or search to see more opportunities.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: app_colors.AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _evMinimum = 0;
                        _evBook = 'ALL';
                        _evSort = 'EV';
                        _evSearchController.clear();
                      }),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('RESET FILTERS'),
                    ),
                  ],
                ),
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
      _verdictCounts = _apiService.lastVerdictCounts;
      _providerCoverage = _apiService.lastProviderCoverage;
      _providerReliability = _apiService.lastProviderReliability;
      _feedIsRecovery = _apiService.lastFeedIsRecovery;
      // Cached counts can outlive a provider's freshness window. Do not keep
      // a stale provider selected or visible as if its inventory were live;
      // reliability polling continues and restores it automatically later.
      if (_selectedSite != 'ALL' &&
          _providersUnavailableForBoard.contains(_selectedSite)) {
        _selectedSite = 'ALL';
        _selectedSiteSport = '';
        _selectedCategory = 'ALL';
        _siteInventoryProps = const [];
        _siteSportCategoryCounts = const {};
        _siteTotalSportCategoryCounts = const {};
      }
      if (_selectedSite != 'ALL' && _selectedCategory == 'ALL') {
        _siteInventoryProps = props;
        if (_selectedSiteSport.isEmpty) {
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
          _siteSportCategoryCounts = normalizedCategoryCounts;
          _siteTotalSportCategoryCounts =
              _apiService.lastTotalSportCategoryCounts;
        }
      }
      _lastUpdated = DateTime.now();
    });
    final catalogTotal = _apiService.lastCatalogCount;
    widget.propCountNotifier.value = catalogTotal > 0
        ? catalogTotal
        : facetTotal > 0
        ? facetTotal
        : propCount;
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

  Future<void> _showPlayerPropsOverlay(PropData focused) async {
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

  // Retained for reference while the per-prop E+ intelligence panels are
  // validated in production.
  // ignore: unused_element
  Widget _buildSiteFirstMarketBoard(double availableWidth) {
    final compact = availableWidth < 720;
    final counts = ApiService().lastSportsbookCounts;
    const preferredOrder = [
      'PRIZEPICKS',
      'UNDERDOG',
      'PICK6',
      'FANDUEL',
      'HARDROCKBET',
      'DRAFTKINGS',
      'BETR',
    ];
    final availableSites = preferredOrder
        .where(
          (site) =>
              counts.isEmpty ||
              (counts[site] ?? 0) > 0 ||
              _selectedSite == site,
        )
        .toList(growable: false);
    final primarySites = availableSites.take(5).toList(growable: false);
    final moreSites = availableSites.skip(5).toList(growable: false);

    void selectSite(String site) {
      setState(() {
        _selectedSite = site;
        _siteDiscoveryExpanded = true;
        _selectedSiteSport = '';
        _selectedCategory = 'ALL';
        _verdictFilter = 'ALL';
        _siteInventoryProps = const [];
        _siteSportCategoryCounts = const {};
        _siteTotalSportCategoryCounts = const {};
        _latestProps = const [];
        _categoryCounts = const {};
        _totalCategoryCounts = const {};
        _lastUpdated = null;
      });
      EngagementTracker.instance.recordProduct('SITE_FILTER');
      unawaited(_rememberPreferredPropSite(site));
    }

    IconData siteIcon(String site) => switch (site) {
      'PRIZEPICKS' => Icons.emoji_events_outlined,
      'UNDERDOG' => Icons.shield_outlined,
      'PICK6' => Icons.workspace_premium_outlined,
      'FANDUEL' => Icons.security_outlined,
      'HARDROCKBET' => Icons.diamond_outlined,
      _ => Icons.storefront_outlined,
    };

    String siteLabel(String site) => switch (site) {
      'PICK6' => 'DRAFTKINGS PICK6',
      'HARDROCKBET' => 'HARD ROCK BET',
      _ => site,
    };

    Widget siteCard(String site) {
      final selected = _selectedSite == site;
      final count = counts[site] ?? 0;
      return SizedBox(
        width: compact ? 174 : 202,
        child: Material(
          color: selected
              ? app_colors.AppColors.gold.withValues(alpha: .18)
              : const Color(0xFF091722),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('site-first-$site'),
            onTap: () => selectSite(site),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? app_colors.AppColors.gold.withValues(alpha: .14)
                          : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? app_colors.AppColors.gold
                            : app_colors.AppColors.gunmetalLight,
                      ),
                    ),
                    child: Icon(
                      siteIcon(site),
                      color: selected
                          ? app_colors.AppColors.gold
                          : app_colors.AppColors.silver,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          siteLabel(site),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? app_colors.AppColors.gold
                                : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          count > 0 ? '$count props' : 'Live inventory',
                          style: const TextStyle(
                            color: app_colors.AppColors.textMuted,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: app_colors.AppColors.gold,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final categoryCounts = _selectedSportTotalCategoryCounts;
    final rankedCategories = categoryCounts.entries
        .where((entry) => entry.key != 'ALL' && entry.value > 0)
        .toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final topCategories = rankedCategories.take(5).toList(growable: false);
    final highestCount = topCategories.isEmpty ? 1 : topCategories.first.value;

    IconData categoryIcon(String category) => switch (category) {
      'POINTS' => Icons.control_point_rounded,
      'REBOUNDS' => Icons.sports_basketball_rounded,
      'ASSISTS' => Icons.hub_outlined,
      'PRA' => Icons.person_pin_circle_outlined,
      '3PT MADE' => Icons.grid_view_rounded,
      _ => Icons.apps_rounded,
    };

    Widget categoryCard(MapEntry<String, int> entry) {
      final selected = _effectiveSelectedCategory == entry.key;
      final popularity = ((entry.value / highestCount) * 100).round();
      return SizedBox(
        width: compact ? 152 : 174,
        child: Material(
          color: selected
              ? app_colors.AppColors.gold.withValues(alpha: .14)
              : const Color(0xFF081620),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('site-first-category-${entry.key}'),
            onTap: () => setState(() {
              _selectedCategory = entry.key;
              _siteDiscoveryExpanded = false;
              _verdictFilter = 'ALL';
              _latestProps = const [];
              _lastUpdated = null;
            }),
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        categoryIcon(entry.key),
                        color: selected
                            ? app_colors.AppColors.gold
                            : app_colors.AppColors.silver,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${entry.value} props',
                    style: const TextStyle(
                      color: app_colors.AppColors.textMuted,
                      fontSize: 8.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: popularity / 100,
                            backgroundColor: app_colors.AppColors.gunmetal,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              app_colors.AppColors.gold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '$popularity%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
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

    Future<void> showAllCategories() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: app_colors.AppColors.panel,
      builder: (sheetContext) {
        final groupedCategories = <String, Map<String, int>>{};
        for (final sportEntry in _siteTotalSportCategoryCounts.entries) {
          final markets = Map<String, int>.from(sportEntry.value)
            ..removeWhere((market, count) => market == 'ALL' || count <= 0);
          if (markets.isNotEmpty) {
            groupedCategories[sportEntry.key] = markets;
          }
        }
        if (groupedCategories.isEmpty && _selectedSiteSport.isNotEmpty) {
          groupedCategories[_selectedSiteSport] = Map<String, int>.from(
            categoryCounts,
          )..remove('ALL');
        }
        final sports = groupedCategories.keys.toList()
          ..sort((left, right) => left.compareTo(right));

        return SafeArea(
        child: FractionallySizedBox(
          heightFactor: .82,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${siteLabel(_selectedSite)} CATEGORIES BY SPORT',
                        style: const TextStyle(
                          color: app_colors.AppColors.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.grid_view_rounded,
                        color: app_colors.AppColors.gold,
                      ),
                      title: const Text('ALL PROPS'),
                      trailing: Text(
                        '${counts[_selectedSite] ?? 0}',
                      ),
                      onTap: () {
                        setState(() {
                          _selectedSiteSport = '';
                          _selectedCategory = 'ALL';
                          _siteDiscoveryExpanded = false;
                          _latestProps = const [];
                          _lastUpdated = null;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                    for (final sport in sports)
                      ExpansionTile(
                        initiallyExpanded: sport == _selectedSiteSport ||
                            (sports.length == 1),
                        leading: const Icon(
                          Icons.sports_rounded,
                          color: app_colors.AppColors.gold,
                        ),
                        title: Text(
                          sport,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${groupedCategories[sport]!.values.fold<int>(0, (sum, value) => sum + value)} available props',
                        ),
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.only(left: 38, right: 16),
                            leading: const Icon(Icons.grid_view_rounded),
                            title: Text('ALL $sport PROPS'),
                            onTap: () {
                              setState(() {
                                _selectedSiteSport = sport;
                                _selectedCategory = 'ALL';
                                _siteDiscoveryExpanded = false;
                                _verdictFilter = 'ALL';
                                _latestProps = const [];
                                _lastUpdated = null;
                              });
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                          for (final entry in (groupedCategories[sport]!.entries.toList()
                                ..sort((left, right) => right.value.compareTo(left.value))))
                            ListTile(
                              contentPadding: const EdgeInsets.only(left: 38, right: 16),
                              leading: Icon(categoryIcon(entry.key)),
                              title: Text(entry.key),
                              trailing: Text('${entry.value}'),
                              selected: _selectedSiteSport == sport &&
                                  _effectiveSelectedCategory == entry.key,
                              onTap: () {
                                setState(() {
                                  _selectedSiteSport = sport;
                                  _selectedCategory = entry.key;
                                  _siteDiscoveryExpanded = false;
                                  _verdictFilter = 'ALL';
                                  _latestProps = const [];
                                  _lastUpdated = null;
                                });
                                Navigator.of(sheetContext).pop();
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      },
    );

    Widget step(int number, String label, bool active) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? app_colors.AppColors.gold : Colors.transparent,
            border: Border.all(
              color: active
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.gunmetalLight,
            ),
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: active
                  ? app_colors.AppColors.bgBase
                  : app_colors.AppColors.silver,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: active
                ? app_colors.AppColors.gold
                : app_colors.AppColors.textMuted,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );

    return Container(
      key: const ValueKey('site-first-market-board'),
      padding: EdgeInsets.all(compact ? 13 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF06131D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: app_colors.AppColors.borderGold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: const Color(0xFF091722),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
              side: const BorderSide(color: app_colors.AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(
                () => _siteDiscoveryExpanded = !_siteDiscoveryExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      color: app_colors.AppColors.gold,
                      size: 20,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            siteLabel(_selectedSite),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _siteDiscoveryExpanded
                                ? 'Choose a prop site, sport, and market category'
                                : 'Tap to change site or browse categories',
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 8.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _siteDiscoveryExpanded = !_siteDiscoveryExpanded,
                      ),
                      child: Text(_siteDiscoveryExpanded ? 'COLLAPSE' : 'CHANGE'),
                    ),
                    Icon(
                      _siteDiscoveryExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: app_colors.AppColors.gold,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_siteDiscoveryExpanded) ...[
          const SizedBox(height: 15),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.sportFilter.toUpperCase()}  /  ${siteLabel(_selectedSite)}  /  MOST POPULAR',
                    style: const TextStyle(
                      color: app_colors.AppColors.gold,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CHOOSE YOUR PROP SITE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Start with the board you use. PI ranks the most popular markets first.',
                    style: TextStyle(
                      color: app_colors.AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 7,
                children: [
                  step(1, 'SELECT SITE', true),
                  step(2, 'SELECT SPORT', _selectedSiteSport.isNotEmpty),
                  step(3, 'SELECT CATEGORY', _selectedCategory != 'ALL'),
                  step(4, 'COMPARE PI PICKS', _latestProps.isNotEmpty),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: primarySites.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                if (index < primarySites.length) {
                  return siteCard(primarySites[index]);
                }
                return SizedBox(
                  width: compact ? 150 : 168,
                  child: PopupMenuButton<String>(
                    tooltip: 'View all prop sites',
                    onSelected: selectSite,
                    color: app_colors.AppColors.sidebar,
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'ALL', child: Text('ALL PROP SITES')),
                      for (final site in moreSites)
                        PopupMenuItem(value: site, child: Text(siteLabel(site))),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF091722),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: app_colors.AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.more_horiz_rounded, color: app_colors.AppColors.silver),
                          SizedBox(width: 9),
                          Expanded(child: Text('MORE SITES', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'CHOOSE YOUR SPORT',
            style: TextStyle(
              color: app_colors.AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final sport in const [
                  'MLB',
                  'NFL',
                  'NBA',
                  'WNBA',
                  'NHL',
                  'SOCCER',
                  'NCAAF',
                  'NCAAB',
                  'CFL',
                ]) ...[
                  ChoiceChip(
                    key: ValueKey('site-sport-$sport'),
                    selected: _selectedSiteSport == sport,
                    avatar: const Icon(Icons.sports_rounded, size: 15),
                    label: Text(sport),
                    onSelected: (_) {
                      setState(() {
                        _selectedSiteSport = sport;
                        _selectedCategory = 'ALL';
                        _selectedSide = 'All';
                        _verdictFilter = 'ALL';
                        _marketQuickFilter = 'ALL';
                        _latestProps = const [];
                        _lastUpdated = null;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        unawaited(
                          _loadSelectedSiteSportCategoryCatalog(sport),
                        );
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (_selectedSiteSport.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'MOST POPULAR ${_selectedSiteSport.toUpperCase()} CATEGORIES ON ${siteLabel(_selectedSite)}',
            style: const TextStyle(
              color: app_colors.AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: topCategories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                if (index < topCategories.length) {
                  return categoryCard(topCategories[index]);
                }
                return SizedBox(
                  width: compact ? 152 : 174,
                  child: OutlinedButton.icon(
                    onPressed: showAllCategories,
                    icon: const Icon(Icons.apps_rounded),
                    label: const Text('VIEW ALL\nCATEGORIES', textAlign: TextAlign.center),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: app_colors.AppColors.gold,
                      side: const BorderSide(color: app_colors.AppColors.gold),
                      textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                );
              },
            ),
          ),
          ],
          ],
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in const [
                  'TOP PI PICKS',
                  'TRENDING',
                  'NEW LINES',
                  'OVER',
                  'UNDER',
                  'ALL',
                ]) ...[
                  ChoiceChip(
                    key: ValueKey('market-quick-filter-$label'),
                    selected: _marketQuickFilter == label,
                    avatar: Icon(
                      switch (label) {
                        'TOP PI PICKS' => Icons.star_outline_rounded,
                        'TRENDING' => Icons.trending_up_rounded,
                        'NEW LINES' => Icons.fiber_new_rounded,
                        'OVER' => Icons.arrow_circle_up_outlined,
                        'UNDER' => Icons.arrow_circle_down_outlined,
                        _ => Icons.grid_view_rounded,
                      },
                      size: 15,
                    ),
                    label: Text(label),
                    onSelected: (_) => setState(() {
                      _marketQuickFilter = label;
                      _selectedSide = switch (label) {
                        'OVER' => 'Over',
                        'UNDER' => 'Under',
                        _ => 'All',
                      };
                      if ((label == 'OVER' || label == 'UNDER') &&
                          _selectedSite != 'ALL' &&
                          _selectedSiteSport.isEmpty) {
                        _siteDiscoveryExpanded = true;
                      }
                      _verdictFilter = label == 'TOP PI PICKS'
                          ? 'ACTIONABLE'
                          : 'ALL';
                      _sortBy = switch (label) {
                        'TRENDING' => 'edge',
                        'NEW LINES' => 'latest',
                        _ => 'trust',
                      };
                      _latestProps = const [];
                      _lastUpdated = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                      if (!mounted) return;
                      setState(() {
                        _searchQuery = value.trim().toLowerCase();
                        _latestProps = const [];
                        _lastUpdated = null;
                      });
                    });
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Search this site',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              OutlinedButton.icon(
                onPressed: _showBoardFilterOptions,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('FILTERS'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: app_colors.AppColors.gold,
                  side: const BorderSide(color: app_colors.AppColors.gold),
                  minimumSize: const Size(108, 48),
                ),
              ),
            ],
          ),
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
    final verdict = verdictLabels[_verdictFilter];
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
      _selectedSite = 'ALL';
      _selectedSiteSport = '';
      _selectedCategory = BoardFilters.defaults.category;
      _minConfidence = BoardFilters.defaults.minConfidence;
      // Reset to complete inventory ranked by PI Trust. Low-rated props stay
      // visible and clearly labelled instead of disappearing from the board.
      _sortBy = BoardFilters.defaults.sortBy;
      _verdictFilter = BoardFilters.defaults.verdict;
      _siteInventoryProps = const [];
      _siteSportCategoryCounts = const {};
      _providerCoverage = const {};
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

  /// Optional rating filters for narrowing the complete prop inventory.
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
      trailing: _buildCategoryPickerButton(),
    );
  }

  Widget _buildCategoryPickerButton() => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: OutlinedButton.icon(
      key: const ValueKey('category-site-picker-button'),
      onPressed: _showCategoryAndSitePicker,
      icon: const Icon(Icons.tune_rounded, size: 14),
      label: const Text(
        'CATEGORIES',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        foregroundColor: app_colors.AppColors.gold,
        backgroundColor: app_colors.AppColors.gold.withValues(alpha: .10),
        side: const BorderSide(color: app_colors.AppColors.gold),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        shape: const StadiumBorder(),
      ),
    ),
  );

  Future<void> _showCategoryAndSitePicker() async {
    const sites = <String>[
      'ALL',
      'PRIZEPICKS',
      'UNDERDOG',
      'FANDUEL',
      'PICK6',
      'DRAFTKINGS',
      'BETR',
    ];
    final categories = _currentCategories.isEmpty
        ? const <String>['ALL']
        : _currentCategories;
    var pendingSite = sites.contains(_selectedSite) ? _selectedSite : 'ALL';
    var pendingCategory = categories.contains(_effectiveSelectedCategory)
        ? _effectiveSelectedCategory
        : 'ALL';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: app_colors.AppColors.sidebar,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'PROP CATEGORY & SITE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose a source and category to load every matching prop.',
                  style: TextStyle(
                    color: app_colors.AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: pendingSite,
                  dropdownColor: app_colors.AppColors.sidebar,
                  decoration: const InputDecoration(labelText: 'PROP SITE'),
                  items: [
                    for (final site in sites)
                      DropdownMenuItem(
                        value: site,
                        child: Text(site == 'ALL' ? 'ALL PROP SITES' : site),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => pendingSite = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: pendingCategory,
                  dropdownColor: app_colors.AppColors.sidebar,
                  decoration: const InputDecoration(labelText: 'CATEGORY'),
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category,
                        child: Text(
                          category == 'ALL' ? 'ALL CATEGORIES' : category,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => pendingCategory = value);
                    }
                  },
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedSite = pendingSite;
                      _selectedSiteSport = pendingSite == 'ALL' ||
                              widget.sportFilter.trim().toUpperCase() == 'ALL'
                          ? ''
                          : _normalizeSport(widget.sportFilter);
                      _selectedCategory = pendingCategory;
                      _verdictFilter = 'ALL';
                      _latestProps = const [];
                      _lastUpdated = null;
                    });
                    Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('SHOW ALL MATCHING PROPS'),
                  style: FilledButton.styleFrom(
                    backgroundColor: app_colors.AppColors.gold,
                    foregroundColor: app_colors.AppColors.bgBase,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final loadedCount = _latestProps.length;
    final matchingCount =
        resolveVerdictFilterCount(_verdictCounts, _verdictFilter) ??
        loadedCount;
    return Semantics(
      liveRegion: true,
      label:
          '$matchingCount matching results. $loadedCount currently loaded. '
          'Sorted by $_boardSortLabel. $_boardUpdatedLabel.',
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
              '$matchingCount MATCHING',
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
              '$loadedCount LOADED',
              style: const TextStyle(
                color: app_colors.AppColors.blue,
                fontSize: 9,
                fontWeight: FontWeight.w800,
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

  Widget _buildDecisionAndSummary({required bool showVerdict}) {
    if (!showVerdict) return _buildBoardResultsSummary();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildVerdictFilter(),
        const SizedBox(height: PiDesign.spacing8),
        _buildBoardResultsSummary(),
      ],
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
    if (AuthManager.instance.sessionState.value.isOwner) {
      return const SizedBox.shrink();
    }
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
      feedIsRecovery: _feedIsRecovery,
      onDetails: _providerReliability.isEmpty
          ? null
          : _showProviderReliabilityDetails,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              reverseDuration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.012, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(widget.selectedPage),
                child: Semantics(
                  key: const ValueKey('secondary-page-workspace'),
                  container: true,
                  label: '${appPageTitle(widget.selectedPage)} workspace',
                  child: FocusTraversalGroup(
                    child: ClipRect(
                      child: widget.selectedPage == AppPage.searchPlayers
                          ? SearchPlayersPage(props: _latestProps)
                          : widget.selectedPage == AppPage.gameMarkets
                          ? GameMarketsScreen(
                              onAddToSlip: widget.onAddGameMarket,
                            )
                          : widget.selectedPage == AppPage.evScanner
                          ? _buildEvScanner()
                          : widget.selectedPage == AppPage.scoreboard
                          ? const LiveScoreboardTickerGridWidget()
                          : widget.selectedPage == AppPage.scoreboardWatchlist
                          ? const LiveScoreboardTickerGridWidget(
                              watchedOnly: true,
                            )
                          : widget.selectedPage == AppPage.propAlerts
                          ? PropAlertsPage(alerts: alertsForPage)
                          : widget.selectedPage == AppPage.briefing
                          ? const BriefingPage()
                          : widget.selectedPage == AppPage.trackRecord
                          ? const TrackRecordPage()
                          : widget.selectedPage == AppPage.analytics
                          ? AnalyticsAdminWorkspace(
                              selectedSport: widget.sportFilter,
                            )
                          : widget.selectedPage == AppPage.lineMovement
                          ? LineMovementPage(
                              selectedSport: widget.sportFilter,
                              hasProAccess: AuthManager
                                  .instance
                                  .sessionState
                                  .value
                                  .hasEdgeAccess,
                            )
                          : widget.selectedPage == AppPage.injuryImpact
                          ? InjuryImpactPage(
                              props: _latestProps,
                              alerts: _injuryAlerts,
                            )
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
                                'kind': widget.selections.length == 1
                                    ? 'prop'
                                    : 'slip',
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
                              thumbVisibility: false,
                              trackVisibility: false,
                              interactive: false,
                              thickness: boardScrollbarThickness(
                                boardViewportWidth,
                              ),
                              radius: const Radius.circular(8),
                              scrollbarOrientation: ScrollbarOrientation.right,
                              child: SingleChildScrollView(
                                controller: _boardVerticalController,
                                primary: false,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: boardContentPadding(
                                  boardViewportWidth,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, constraints) =>
                                          _buildSiteFirstMarketBoard(
                                            constraints.maxWidth,
                                          ),
                                    ),
                                    SizedBox(height: sectionGap),
                                    _buildProviderReliabilityBanner(),
                                    SizedBox(height: sectionGap),
                                    /*Text(
                            '${visibleProps.length} visible props • $_propCount total loaded',
                            style: const TextStyle(
                              color: app_colors.AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),*/
                                    _buildDecisionAndSummary(
                                      showVerdict: canShowSystemRecommendation(
                                        hasEdgeAccess: AuthManager
                                            .instance
                                            .sessionState
                                            .value
                                            .hasEdgeAccess,
                                      ),
                                    ),
                                    SizedBox(height: sectionGap),
                                    if (_activeBoardFilterLabels()
                                        .isNotEmpty) ...[
                                      _buildActiveBoardFilters(),
                                      SizedBox(height: sectionGap),
                                    ],
                                    if (_selectedSite != 'ALL' &&
                                        _selectedSiteSport.isEmpty &&
                                        (_selectedSide == 'Over' ||
                                            _selectedSide == 'Under'))
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 28,
                                        ),
                                        decoration: BoxDecoration(
                                          color: app_colors.AppColors.panel,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: app_colors.AppColors.gold
                                                .withValues(alpha: .65),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            const Icon(
                                              Icons.sports_rounded,
                                              color: app_colors.AppColors.gold,
                                              size: 30,
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'CHOOSE A SPORT FOR ${_selectedSide.toUpperCase()} PROPS',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            const Text(
                                              'Over and Under markets are organized by sport so results stay focused and easy to compare.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: app_colors.AppColors.textMuted,
                                                fontSize: 10,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                    PropGrid(
                                      selections: widget.selections,
                                      onSelect: (prop, side) {
                                        widget.onSelect(prop, side);
                                      },
                                      onPropFocused: _showPlayerPropsOverlay,
                                      refreshListenable:
                                          widget.refreshRequestNotifier,
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
                                      selectedCategory:
                                          _effectiveSelectedCategory,
                                      selectedSide: _selectedSide,
                                      selectedTier: _selectedTier,
                                      minConfidence: _minConfidence,
                                      sortBy: _sortBy,
                                      verdictFilter: _verdictFilter,
                                      siteFirstLayout: true,
                                      onPropsLoaded: _handlePropsLoaded,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
