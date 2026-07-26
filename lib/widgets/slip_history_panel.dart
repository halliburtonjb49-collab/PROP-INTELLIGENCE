import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/active_slip_controller.dart';
import '../models/saved_slip.dart';
import '../services/api_service.dart';
import '../services/live_update_service.dart';
import '../services/player_image_resolver.dart';
import 'context_help.dart';

class _LegPhoto extends StatelessWidget {
  final SavedSlipLeg leg;
  final double size;

  const _LegPhoto({required this.leg, this.size = 40});

  Widget _placeholder() {
    final initial = leg.player.trim().isEmpty
        ? '?'
        : leg.player.trim().substring(0, 1).toUpperCase();
    return Container(
      color: const Color(0xFF0C1824),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFFF2BC35),
          fontSize: size * 0.36,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = resolvePlayerImagePath(leg.imagePath);
    if (imagePath.isEmpty) {
      return _placeholder();
    }
    final isNetwork =
        imagePath.startsWith('http://') || imagePath.startsWith('https://');
    if (!isNetwork) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return CachedNetworkImage(
      imageUrl: imagePath,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }
}

/// [active] is the Slip Watcher page - unresolved slips only, with
/// MARK WON/LOST/unlock actions. [history] is the Past Slip History page -
/// resolved (won/lost) slips only, read-only.
enum SlipHistoryMode { active, history }

@visibleForTesting
bool supportsEnhancedSlipWatcher({
  required SlipHistoryMode mode,
  required bool hasProAccess,
}) {
  return mode == SlipHistoryMode.active && hasProAccess;
}

@visibleForTesting
List<SavedSlip> limitHistoryForCore(
  Iterable<SavedSlip> slips, {
  required bool hasProAccess,
  DateTime? now,
}) {
  if (hasProAccess) return slips.toList();
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 14));
  return slips
      .where(
        (slip) => slip.createdAt != null && !slip.createdAt!.isBefore(cutoff),
      )
      .toList();
}

class SlipHistoryPanel extends StatefulWidget {
  const SlipHistoryPanel({
    super.key,
    required this.activeSlipController,
    this.mode = SlipHistoryMode.active,
    this.hasProAccess = true,
  });

  final ActiveSlipController activeSlipController;
  final SlipHistoryMode mode;
  final bool hasProAccess;

  @override
  State<SlipHistoryPanel> createState() => _SlipHistoryPanelState();
}

class _SlipHistoryPanelState extends State<SlipHistoryPanel> {
  final ApiService _apiService = ApiService();
  final LiveUpdateService _liveUpdates = LiveUpdateService(
    channels: const {'tickets'},
  );
  StreamSubscription<dynamic>? _liveSubscription;
  late String _selectedTab;
  late Future<List<SavedSlip>> _slipsFuture;
  Timer? _refreshTimer;
  Timer? _liveStatsTimer;
  bool _isRefreshingGames = false;
  bool _showInsights = false;
  String? _refreshError;
  DateTime? _lastUpdated;
  Map<String, Map<String, dynamic>> _liveStats = const {};

  bool get _isHistory => widget.mode == SlipHistoryMode.history;
  bool get _hasEnhancedLiveTracking => supportsEnhancedSlipWatcher(
    mode: widget.mode,
    hasProAccess: widget.hasProAccess,
  );

  /// Fetches slips for a given tab, respecting the panel's mode. The
  /// backend only supports filtering by one status at a time, so history
  /// mode's "ALL" tab (all resolved slips) is built by fetching everything
  /// and dropping active ones client-side.
  Future<List<SavedSlip>> _fetchForTab(String tab) async {
    if (!_isHistory) {
      final slips = await _apiService.fetchSlips(status: 'active');
      return widget.activeSlipController.mergeWithRecentLockedSlips(slips);
    }
    if (tab == 'all') {
      final all = await _apiService.fetchSlips();
      final resolved = all
          .where((slip) => slip.status.toLowerCase() != 'active')
          .toList();
      return limitHistoryForCore(resolved, hasProAccess: widget.hasProAccess);
    }
    final slips = await _apiService.fetchSlips(status: tab);
    return limitHistoryForCore(slips, hasProAccess: widget.hasProAccess);
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = _isHistory ? 'all' : 'active';
    final recent = widget.activeSlipController.recentLockedSlips;
    _slipsFuture = !_isHistory && recent.isNotEmpty
        ? Future.value(recent)
        : _fetchForTab(_selectedTab);
    widget.activeSlipController.addListener(_handleLockedSlipChange);
    unawaited(_refreshLockedSlipCount());
    _liveSubscription = _liveUpdates.stream.listen(
      (_) => _reloadFromTicketEvent(),
      onError: (_) {},
    );
    _liveUpdates.connect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reloadSlipsOnly());
    });
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshGameStatuses(),
    );
    if (_hasEnhancedLiveTracking) _startLiveStatsTracking();
  }

  void _startLiveStatsTracking() {
    unawaited(_refreshLiveStats());
    _liveStatsTimer?.cancel();
    _liveStatsTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshLiveStats(),
    );
  }

  void _stopLiveStatsTracking() {
    _liveStatsTimer?.cancel();
    _liveStatsTimer = null;
    _liveStats = const {};
  }

  @override
  void didUpdateWidget(covariant SlipHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previouslyEnhanced = supportsEnhancedSlipWatcher(
      mode: oldWidget.mode,
      hasProAccess: oldWidget.hasProAccess,
    );
    if (previouslyEnhanced == _hasEnhancedLiveTracking) return;
    if (_hasEnhancedLiveTracking) {
      _startLiveStatsTracking();
    } else {
      _stopLiveStatsTracking();
    }
  }

  /// Live progress-bar values for active slips only - Past Slip History
  /// shows already-resolved legs with permanent result values, so it has
  /// no need to poll this.
  Future<void> _refreshLiveStats() async {
    try {
      final stats = await _apiService.fetchLiveSlipStats();
      if (!mounted) return;
      setState(() {
        _liveStats = stats;
      });
    } catch (_) {
      // Keep the last known live stats on a transient failure.
    }
  }

  /// The sidebar's SLIP WATCHER badge always reflects the active/unresolved
  /// count regardless of which tab is selected here, so it needs its own
  /// fetch independent of the (possibly won/lost-filtered) _slipsFuture.
  Future<void> _refreshLockedSlipCount() async {
    try {
      final activeSlips = await _apiService.fetchSlips(status: 'active');
      if (!mounted) return;
      final visibleSlips = widget.activeSlipController
          .mergeWithRecentLockedSlips(activeSlips);
      widget.activeSlipController.setLockedSlipCount(visibleSlips.length);
    } catch (_) {
      // Leave the last known count in place on a transient failure.
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _liveStatsTimer?.cancel();
    unawaited(_liveSubscription?.cancel());
    unawaited(_liveUpdates.dispose());
    widget.activeSlipController.removeListener(_handleLockedSlipChange);
    super.dispose();
  }

  void _handleLockedSlipChange() {
    if (!mounted || _isHistory) return;
    final recent = widget.activeSlipController.recentLockedSlips;
    if (recent.isNotEmpty) {
      setState(() => _slipsFuture = Future.value(recent));
    }
    unawaited(_reloadSlipsOnly());
  }

  Future<void> _reloadSlipsOnly() async {
    try {
      final slips = await _fetchForTab(_selectedTab);
      if (!mounted) return;
      setState(() {
        _lastUpdated = DateTime.now();
        _slipsFuture = Future.value(slips);
      });
      widget.activeSlipController.setLockedSlipCount(slips.length);
    } catch (_) {
      // Keep the optimistic/local ticket visible during a transient failure.
    }
  }

  void _reloadFromTicketEvent() {
    if (!mounted) return;
    setState(() {
      _lastUpdated = DateTime.now();
      _slipsFuture = _fetchForTab(_selectedTab);
    });
    unawaited(_refreshLockedSlipCount());
    if (_hasEnhancedLiveTracking) {
      unawaited(_refreshLiveStats());
    }
  }

  void _selectTab(String tab) {
    setState(() {
      _selectedTab = tab;
      _slipsFuture = _fetchForTab(tab);
    });
  }

  Future<void> _changeStatus(SavedSlip slip, String status) async {
    await _apiService.updateSlipStatus(slipId: slip.id, status: status);
    if (!mounted) {
      return;
    }
    setState(() {
      _slipsFuture = _fetchForTab(_selectedTab);
    });
    unawaited(_refreshLockedSlipCount());
  }

  Future<void> _unlockSlip(SavedSlip slip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0C1824),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF73500B)),
        ),
        title: const Text('Unlock this slip?'),
        content: Text(
          'This removes the ${slip.legs.length}-leg slip from Slip Watcher. '
          'This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5D68),
            ),
            child: const Text('UNLOCK'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _apiService.deleteSlip(slip.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to unlock slip: $error')));
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _slipsFuture = _fetchForTab(_selectedTab);
    });
    unawaited(_refreshLockedSlipCount());
  }

  Future<void> _refreshGameStatuses() async {
    if (_isRefreshingGames) {
      return;
    }
    setState(() {
      _isRefreshingGames = true;
      _refreshError = null;
    });
    try {
      if (_isHistory) {
        // Resolved slips don't need game-status refreshing or re-grading -
        // just pull the latest list (e.g. a slip resolved elsewhere since
        // this page loaded).
        final refreshedSlips = await _fetchForTab(_selectedTab);
        if (!mounted) return;
        setState(() {
          _lastUpdated = DateTime.now();
          _slipsFuture = Future.value(refreshedSlips);
        });
        return;
      }
      await _apiService.refreshAllSlipGames();
      // Grade every completed leg covered by an authoritative stat provider.
      await _apiService.gradePendingSlips();
      final refreshedSlips = await _fetchForTab(_selectedTab);
      await _syncActiveSlipFromSavedSlips(refreshedSlips);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastUpdated = DateTime.now();
        _slipsFuture = Future.value(refreshedSlips);
      });
      unawaited(_refreshLockedSlipCount());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingGames = false;
        });
      }
    }
  }

  Future<void> _syncActiveSlipFromSavedSlips(List<SavedSlip> slips) async {
    final existingByPropId = <String, Map<String, dynamic>>{};
    for (final leg in widget.activeSlipController.legs) {
      final propId = leg['prop_id']?.toString() ?? leg['id']?.toString() ?? '';
      if (propId.isEmpty) {
        continue;
      }
      existingByPropId[propId] = leg;
    }

    final gradedLegs = <Map<String, dynamic>>[];
    for (final slip in slips) {
      for (final savedLeg in slip.legs) {
        final existing = existingByPropId[savedLeg.propId];
        if (existing == null) {
          continue;
        }
        final merged = Map<String, dynamic>.from(existing)
          ..['result_status'] = savedLeg.resultStatus
          ..['result_value'] = savedLeg.resultValue;
        gradedLegs.add(merged);
      }
    }

    if (gradedLegs.isEmpty) {
      return;
    }

    await widget.activeSlipController.updateMatchingLegs(gradedLegs);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isHistory ? 'PAST SLIP HISTORY' : 'SLIP WATCHER',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _isHistory
                        ? 'Settled tickets and final results'
                        : 'Locked tickets with live grading',
                    style: const TextStyle(
                      color: Color(0xFF8B98A8),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (!_isHistory)
                      IconButton(
                        tooltip: _showInsights
                            ? 'Hide Slip Watcher insights'
                            : 'Show Slip Watcher insights',
                        onPressed: () =>
                            setState(() => _showInsights = !_showInsights),
                        icon: Icon(
                          _showInsights
                              ? Icons.close_rounded
                              : Icons.insights_rounded,
                          color: const Color(0xFFF2BC35),
                          size: 19,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Refresh slips',
                      onPressed: _isRefreshingGames
                          ? null
                          : _refreshGameStatuses,
                      icon: _isRefreshingGames
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFF2BC35),
                              ),
                            )
                          : const Icon(Icons.refresh, size: 19),
                      color: const Color(0xFFF2BC35),
                    ),
                  ],
                ),
                if (_lastUpdated != null)
                  Text(
                    'Updated ${TimeOfDay.fromDateTime(_lastUpdated!).format(context)}',
                    style: const TextStyle(
                      color: Color(0xFF8B98A8),
                      fontSize: 8,
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (!_isHistory && _showInsights) ...[
          const SizedBox(height: 8),
          _SlipWatcherTierBanner(hasProAccess: widget.hasProAccess),
        ],
        if (_isHistory) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _tab('ALL', 'all'),
              const SizedBox(width: 6),
              _tab('WON', 'won'),
              const SizedBox(width: 6),
              _tab('LOST', 'lost'),
            ],
          ),
          if (!widget.hasProAccess) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFC8CED6).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC8CED6)),
              ),
              child: const Text(
                'CORE HISTORY • LAST 14 DAYS • STANDARD WIN/LOSS GRADING',
                style: TextStyle(
                  color: Color(0xFFC8CED6),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 8),
        if (_showInsights) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF201A06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF8B6813)),
            ),
            child: Row(
              children: [
                Icon(
                  _isRefreshingGames ? Icons.sync : Icons.track_changes,
                  size: 15,
                  color: const Color(0xFFF2BC35),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isRefreshingGames
                        ? 'UPDATING SLIP RESULTS AND TOTALS...'
                        : _lastUpdated == null
                        ? 'LIVE SLIP TRACKING READY'
                        : 'LIVE TOTALS UPDATED ${_formatRefreshTime(_lastUpdated!)}',
                    style: const TextStyle(
                      color: Color(0xFFF2BC35),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_refreshError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF291417),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF72313A)),
            ),
            child: Text(
              _refreshError!,
              style: const TextStyle(color: Color(0xFFFFA6AE), fontSize: 9),
            ),
          ),
        ],
        Expanded(
          child: FutureBuilder<List<SavedSlip>>(
            future: _slipsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              final slips = snapshot.data ?? [];
              final totals = _buildTotals(slips);
              if (slips.isEmpty) {
                return const Center(child: Text('No slips in this view.'));
              }
              return Column(
                children: [
                  if (_showInsights) ...[
                    _TotalsBar(totals: totals),
                    const SizedBox(height: 8),
                    if (widget.hasProAccess) ...[
                      _ProfitKeeper(totals: totals),
                      const SizedBox(height: 8),
                      _ClvSummary(totals: totals),
                    ],
                    const SizedBox(height: 10),
                  ],
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1160
                            ? 3
                            : constraints.maxWidth >= 720
                            ? 2
                            : 1;
                        final cardWidth =
                            (constraints.maxWidth - ((columns - 1) * 12)) /
                            columns;
                        return SingleChildScrollView(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final slip in slips)
                                SizedBox(
                                  width: cardWidth,
                                  child: _SavedSlipCard(
                                    slip: slip,
                                    liveStats: _hasEnhancedLiveTracking
                                        ? _liveStats[slip.id] ?? const {}
                                        : const {},
                                    onWon: () => _changeStatus(slip, 'won'),
                                    onLost: () => _changeStatus(slip, 'lost'),
                                    onUnlock: () => _unlockSlip(slip),
                                    showDetails: _showInsights,
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
        ),
      ],
    );
  }

  _SlipTotals _buildTotals(List<SavedSlip> slips) {
    var wonLegs = 0;
    var lostLegs = 0;
    var pendingLegs = 0;
    var measuredClvLegs = 0;
    var beatCloseLegs = 0;
    var clvPercentTotal = 0.0;
    var wonSlips = 0;
    var lostSlips = 0;
    final profitByBook = <String, double>{};

    for (final slip in slips) {
      final slipStatus = slip.status.toLowerCase();
      if (slipStatus == 'won') wonSlips += 1;
      if (slipStatus == 'lost') lostSlips += 1;
      final book =
          slip.legs.isEmpty || slip.legs.first.sportsbook.trim().isEmpty
          ? 'Unknown site'
          : slip.legs.first.sportsbook.trim();
      final settledProfit = slipStatus == 'won'
          ? slip.potentialPayout - slip.stake
          : slipStatus == 'lost'
          ? -slip.stake
          : 0.0;
      profitByBook.update(
        book,
        (value) => value + settledProfit,
        ifAbsent: () => settledProfit,
      );
      final legLiveStats = _liveStats[slip.id] ?? const {};
      for (final leg in slip.legs) {
        if (leg.lineClvPercent != null && leg.beatClosingLine != null) {
          measuredClvLegs += 1;
          clvPercentTotal += leg.lineClvPercent!;
          if (leg.beatClosingLine!) beatCloseLegs += 1;
        }
        // Uses the live-projected result (when available) so the totals
        // bar reacts as each leg's status bar flips, not just once a leg
        // is officially graded.
        final effectiveStatus = _effectiveLegState(
          leg,
          legLiveStats,
        ).resultStatus.toLowerCase();
        switch (effectiveStatus) {
          case 'won':
          case 'win':
            wonLegs += 1;
            break;
          case 'lost':
          case 'loss':
            lostLegs += 1;
            break;
          default:
            pendingLegs += 1;
        }
      }
    }

    return _SlipTotals(
      totalSlips: slips.length,
      wonSlips: wonSlips,
      lostSlips: lostSlips,
      profitByBook: profitByBook,
      wonLegs: wonLegs,
      lostLegs: lostLegs,
      pendingLegs: pendingLegs,
      measuredClvLegs: measuredClvLegs,
      beatCloseLegs: beatCloseLegs,
      averageClvPercent: measuredClvLegs == 0
          ? 0
          : clvPercentTotal / measuredClvLegs,
    );
  }

  String _formatRefreshTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Widget _tab(String label, String value) {
    final selected = _selectedTab == value;
    return Expanded(
      child: SizedBox(
        height: 36,
        child: OutlinedButton(
          onPressed: () => _selectTab(value),
          style: OutlinedButton.styleFrom(
            backgroundColor: selected
                ? const Color(0xFF5A3B08)
                : const Color(0xFF0C1824),
            foregroundColor: selected ? const Color(0xFFF2BC35) : Colors.white,
            side: BorderSide(
              color: selected
                  ? const Color(0xFFF2BC35)
                  : const Color(0xFF283846),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _SlipWatcherTierBanner extends StatelessWidget {
  const _SlipWatcherTierBanner({required this.hasProAccess});

  final bool hasProAccess;

  @override
  Widget build(BuildContext context) {
    final accent = hasProAccess
        ? const Color(0xFFF2BC35)
        : const Color(0xFFC8CED6);
    return Container(
      key: ValueKey(
        hasProAccess ? 'pro-slip-watcher-banner' : 'core-slip-watcher-banner',
      ),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent),
      ),
      child: Row(
        children: [
          Icon(
            hasProAccess
                ? Icons.bolt_rounded
                : Icons.check_circle_outline_rounded,
            color: accent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasProAccess
                  ? 'PRO SLIP WATCHER • LIVE LEG PROGRESS • 20-SECOND UPDATES • PROFIT + CLV'
                  : 'CORE SLIP WATCHER • TICKET STATUS • FINAL GRADING • WIN/LOSS TOTALS',
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: .3,
              ),
            ),
          ),
          if (!hasProAccess)
            const Tooltip(
              message:
                  'Pro adds live leg progress, 20-second updates, Profit Keeper, and closing-line value.',
              child: Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFFC8CED6),
                size: 15,
              ),
            ),
        ],
      ),
    );
  }
}

class _SlipTotals {
  const _SlipTotals({
    required this.totalSlips,
    required this.wonSlips,
    required this.lostSlips,
    required this.profitByBook,
    required this.wonLegs,
    required this.lostLegs,
    required this.pendingLegs,
    required this.measuredClvLegs,
    required this.beatCloseLegs,
    required this.averageClvPercent,
  });

  final int totalSlips;
  final int wonSlips;
  final int lostSlips;
  final Map<String, double> profitByBook;
  final int wonLegs;
  final int lostLegs;
  final int pendingLegs;
  final int measuredClvLegs;
  final int beatCloseLegs;
  final double averageClvPercent;
}

class _ClvSummary extends StatelessWidget {
  const _ClvSummary({required this.totals});

  final _SlipTotals totals;

  @override
  Widget build(BuildContext context) {
    final rate = totals.measuredClvLegs == 0
        ? 0.0
        : totals.beatCloseLegs / totals.measuredClvLegs * 100;
    final positive = totals.averageClvPercent > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF101D28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF344758)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.show_chart_rounded,
            size: 16,
            color: positive ? const Color(0xFF36B9FF) : const Color(0xFFF2BC35),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              totals.measuredClvLegs == 0
                  ? 'CLV pending — no closing snapshots yet'
                  : 'Beat close ${rate.toStringAsFixed(1)}%  •  Avg CLV ${totals.averageClvPercent >= 0 ? '+' : ''}${totals.averageClvPercent.toStringAsFixed(2)}%  •  n=${totals.measuredClvLegs}',
              style: const TextStyle(
                color: Color(0xFFDCE8F4),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const ContextHelp(
            title: 'Closing Line Value',
            message:
                'Beat-close rate is the share of measured ticket legs with a better entry line than the closing market. Average CLV summarizes the size of that advantage. A larger sample is more meaningful than a few individual results.',
          ),
        ],
      ),
    );
  }
}

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.totals});

  final _SlipTotals totals;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF101D28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF8B98A8),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
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
        ),
      );
    }

    return Row(
      children: [
        pill('SLIPS', '${totals.totalSlips}', const Color(0xFFF2BC35)),
        const SizedBox(width: 8),
        pill('SLIP WINS', '${totals.wonSlips}', const Color(0xFFF2BC35)),
        const SizedBox(width: 8),
        pill('SLIP LOSSES', '${totals.lostSlips}', const Color(0xFFFF5D68)),
        const SizedBox(width: 8),
        pill('PENDING', '${totals.pendingLegs}', const Color(0xFFF2BC35)),
      ],
    );
  }
}

class _ProfitKeeper extends StatelessWidget {
  const _ProfitKeeper({required this.totals});

  final _SlipTotals totals;

  @override
  Widget build(BuildContext context) {
    final entries = totals.profitByBook.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final net = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    String money(double value) =>
        '${value >= 0 ? '+' : '-'}\$${value.abs().toStringAsFixed(2)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF101D28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF344758)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: Color(0xFFF2BC35),
              ),
              const SizedBox(width: 7),
              const Text(
                'PROFIT KEEPER',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                money(net),
                style: TextStyle(
                  color: net >= 0
                      ? const Color(0xFFF2BC35)
                      : const Color(0xFFFF5D68),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: entries
                  .map(
                    (entry) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07131D),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${entry.key}: ${money(entry.value)}',
                        style: TextStyle(
                          color: entry.value >= 0
                              ? const Color(0xFFF2BC35)
                              : const Color(0xFFFF5D68),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

typedef _LiveLegState = ({
  double? current,
  String resultStatus,
  String gameStatus,
  bool gameCompleted,
});

/// Merges a leg's persisted (graded) result with its live in-progress
/// value, when available. [legLiveStats] is keyed by propId, e.g. the
/// per-slip map from `/api/slips/live-stats`.
_LiveLegState _effectiveLegState(
  SavedSlipLeg leg,
  Map<String, dynamic> legLiveStats,
) {
  final live = legLiveStats[leg.propId];
  if (live is! Map) {
    return (
      current: leg.resultValue,
      resultStatus: leg.resultStatus,
      gameStatus: leg.gameStatus,
      gameCompleted: leg.gameCompleted,
    );
  }
  final rawGameStatus = live['game_status']?.toString() ?? leg.gameStatus;
  return (
    current: (live['result_value'] as num?)?.toDouble() ?? leg.resultValue,
    resultStatus: live['result_status']?.toString() ?? leg.resultStatus,
    gameStatus: rawGameStatus,
    gameCompleted: rawGameStatus.toLowerCase() == 'final',
  );
}

/// Live projection for an active slip as a whole, from its legs' live
/// state - not the official graded result. Null means no live data has
/// loaded for this slip yet, so callers should fall back to "ACTIVE".
enum _SlipLiveProjection { winning, losing, live }

_SlipLiveProjection? _slipLiveProjection(
  SavedSlip slip,
  Map<String, dynamic> legLiveStats,
) {
  if (legLiveStats.isEmpty) {
    return null;
  }
  var hasLosingLeg = false;
  var allLegsDecided = true;
  for (final leg in slip.legs) {
    final status = _effectiveLegState(
      leg,
      legLiveStats,
    ).resultStatus.toLowerCase();
    if (status == 'lost' || status == 'loss') {
      hasLosingLeg = true;
    } else if (status == 'won' || status == 'win' || status == 'push') {
      // Currently favorable - keep checking the rest of the legs.
    } else {
      allLegsDecided = false;
    }
  }
  if (hasLosingLeg) {
    return _SlipLiveProjection.losing;
  }
  return allLegsDecided
      ? _SlipLiveProjection.winning
      : _SlipLiveProjection.live;
}

class _CompactSlipLegRow extends StatelessWidget {
  const _CompactSlipLegRow({
    required this.leg,
    required this.live,
    required this.progress,
    required this.statusColor,
    required this.statusLabel,
  });

  final SavedSlipLeg leg;
  final _LiveLegState live;
  final double progress;
  final Color statusColor;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final isOver = leg.side.toUpperCase() == 'OVER';
    final pickColor = isOver
        ? const Color(0xFFF2BC35)
        : const Color(0xFFC8CED6);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF091620),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 7),
          SizedBox(
            width: 52,
            height: 68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _LegPhoto(leg: leg, size: 52),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        leg.player,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    GameStatusBadge(status: live.gameStatus),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  leg.matchup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF8996A6), fontSize: 8),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text(
                      live.current?.toStringAsFixed(1) ?? '0.0',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      live.current == null ? 'PENDING' : statusLabel,
                      style: TextStyle(
                        color: live.current == null
                            ? const Color(0xFF8B98A8)
                            : statusColor,
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: progress,
                    backgroundColor: const Color(0xFF263746),
                    valueColor: AlwaysStoppedAnimation(statusColor),
                  ),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    leg.line.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Color(0xFF8B98A8),
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 82,
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF101D28),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: pickColor.withValues(alpha: .45)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isOver ? 'MORE' : 'LESS',
                  style: TextStyle(
                    color: pickColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  leg.line.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  leg.market.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFD7DEE5),
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
        ],
      ),
    );
  }
}

class _SavedSlipCard extends StatelessWidget {
  final SavedSlip slip;
  final Map<String, dynamic> liveStats;
  final VoidCallback onWon;
  final VoidCallback onLost;
  final VoidCallback onUnlock;
  final bool showDetails;

  const _SavedSlipCard({
    required this.slip,
    this.liveStats = const {},
    required this.onWon,
    required this.onLost,
    required this.onUnlock,
    this.showDetails = false,
  });

  _LiveLegState _liveState(SavedSlipLeg leg) =>
      _effectiveLegState(leg, liveStats);

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = slip.status.toLowerCase();
    final isWon = normalizedStatus == 'won';
    final isLost = normalizedStatus == 'lost';
    final liveProjection = normalizedStatus == 'active'
        ? _slipLiveProjection(slip, liveStats)
        : null;
    final isLiveWinning = liveProjection == _SlipLiveProjection.winning;
    final isLiveLosing = liveProjection == _SlipLiveProjection.losing;
    final borderColor = isWon
        ? const Color(0xFFF2BC35)
        : isLiveWinning
        ? const Color(0xFF4CAF50)
        : isLost || isLiveLosing
        ? const Color(0xFFFF5D68)
        : const Color(0xFFF2BC35);
    final statusColor = isWon
        ? const Color(0xFFF2BC35)
        : isLiveWinning
        ? const Color(0xFF4CAF50)
        : isLost || isLiveLosing
        ? const Color(0xFFFF5D68)
        : const Color(0xFFF2BC35);
    final statusLabel = isWon
        ? 'WON'
        : isLost
        ? 'LOST'
        : isLiveLosing
        ? 'LIVE • LOSING'
        : isLiveWinning
        ? 'LIVE • WINNING'
        : liveProjection == _SlipLiveProjection.live
        ? 'LIVE'
        : slip.status.toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C1824),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        children: [
          if (isWon)
            const Positioned.fill(
              child: IgnorePointer(child: _GoldTicketConfetti()),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${slip.legs.length} PICKS',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (normalizedStatus == 'active') ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Unlock (remove) this slip',
                        child: IconButton(
                          onPressed: onUnlock,
                          icon: const Icon(
                            Icons.lock_open_rounded,
                            size: 13,
                            color: Color(0xFF8B98A8),
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(22, 22),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                ...slip.legs.map((leg) {
                  final pickColor = leg.side.toUpperCase() == 'OVER'
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFEF5350);
                  final live = _liveState(leg);
                  final normalizedResult = live.resultStatus.toLowerCase();
                  Color statusColor;
                  String statusLabel;
                  switch (normalizedResult) {
                    case 'won':
                    case 'win':
                      statusColor = const Color(0xFF4CAF50);
                      statusLabel = 'WON';
                      break;
                    case 'lost':
                    case 'loss':
                      statusColor = const Color(0xFFFF5D68);
                      statusLabel = 'LOST';
                      break;
                    case 'push':
                      statusColor = const Color(0xFF8B98A8);
                      statusLabel = 'PUSH';
                      break;
                    default:
                      statusColor = const Color(0xFFF2BC35);
                      statusLabel = live.gameCompleted ? 'FINAL' : 'LIVE';
                  }
                  final progress = leg.line <= 0 || live.current == null
                      ? 0.0
                      : (live.current! / leg.line).clamp(0.0, 1.0);
                  if (!showDetails) {
                    return _CompactSlipLegRow(
                      leg: leg,
                      live: live,
                      progress: progress,
                      statusColor: statusColor,
                      statusLabel: statusLabel,
                    );
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF091620),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF263B4B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFF2BC35),
                                ),
                              ),
                              child: ClipOval(
                                child: _LegPhoto(leg: leg, size: 36),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    leg.player,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    leg.matchup,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF8996A6),
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            GameStatusBadge(status: live.gameStatus),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C1824),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: pickColor.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${leg.side.toUpperCase() == 'OVER' ? 'MORE' : 'LESS'} ${leg.line.toStringAsFixed(1)} ${leg.market.toUpperCase()}',
                                      style: TextStyle(
                                        color: pickColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    live.current == null
                                        ? '--'
                                        : '${live.current!.toStringAsFixed(1)} / ${leg.line.toStringAsFixed(1)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: progress,
                                  backgroundColor: const Color(0xFF263746),
                                  valueColor: AlwaysStoppedAnimation(
                                    statusColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                live.current == null ? 'PENDING' : statusLabel,
                                style: TextStyle(
                                  color: live.current == null
                                      ? const Color(0xFF8B98A8)
                                      : statusColor,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (showDetails && leg.closingLine == null)
                          const Text(
                            'CLV: pending closing line',
                            style: TextStyle(
                              color: Color(0xFF8B98A8),
                              fontSize: 9,
                            ),
                          )
                        else if (showDetails)
                          Text(
                            'Entry ${leg.entryLine.toStringAsFixed(1)} → Close ${leg.closingLine!.toStringAsFixed(1)}  •  ${leg.beatClosingLine == true
                                ? 'BEAT CLOSE'
                                : leg.lineClv == 0
                                ? 'PUSH'
                                : 'MISSED CLOSE'}  ${leg.lineClvPercent == null ? '' : '${leg.lineClvPercent! >= 0 ? '+' : ''}${leg.lineClvPercent!.toStringAsFixed(2)}%'}',
                            style: TextStyle(
                              color: leg.beatClosingLine == true
                                  ? const Color(0xFF36B9FF)
                                  : const Color(0xFFFFB74D),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                if (slip.status == 'active') ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: OutlinedButton(
                            onPressed: onWon,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFF2BC35),
                              side: const BorderSide(color: Color(0xFFF2BC35)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: const Text('MARK WON'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: OutlinedButton(
                            onPressed: onLost,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF5D68),
                              side: const BorderSide(color: Color(0xFFFF5D68)),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: const Text('MARK LOST'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldTicketConfetti extends StatelessWidget {
  const _GoldTicketConfetti();

  @override
  Widget build(BuildContext context) {
    Widget piece(
      double left,
      double top,
      double width,
      double height,
      double angle,
      Color color,
      BorderRadius radius,
    ) {
      return Positioned(
        left: left,
        top: top,
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: radius),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFFC400).withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          piece(
            14,
            14,
            10,
            4,
            0.35,
            const Color(0xFFFFD76A),
            BorderRadius.circular(10),
          ),
          piece(
            52,
            28,
            6,
            6,
            0.0,
            const Color(0xFFF2BC35),
            BorderRadius.circular(999),
          ),
          piece(
            98,
            12,
            12,
            4,
            -0.45,
            const Color(0xFF8B6813),
            BorderRadius.circular(10),
          ),
          piece(
            145,
            20,
            8,
            8,
            0.0,
            const Color(0xFFFFC400),
            BorderRadius.circular(999),
          ),
          piece(
            188,
            14,
            10,
            4,
            0.6,
            const Color(0xFFFFE08A),
            BorderRadius.circular(10),
          ),
          piece(
            232,
            26,
            7,
            7,
            0.0,
            const Color(0xFFF2BC35),
            BorderRadius.circular(999),
          ),
          piece(
            278,
            16,
            11,
            4,
            -0.3,
            const Color(0xFF8B6813),
            BorderRadius.circular(10),
          ),
          piece(
            320,
            24,
            6,
            6,
            0.0,
            const Color(0xFFFFD76A),
            BorderRadius.circular(999),
          ),
          piece(
            366,
            12,
            10,
            4,
            0.4,
            const Color(0xFFFFC400),
            BorderRadius.circular(10),
          ),
          piece(
            410,
            20,
            7,
            7,
            0.0,
            const Color(0xFFFFE08A),
            BorderRadius.circular(999),
          ),
          piece(
            24,
            54,
            8,
            8,
            0.0,
            const Color(0xFFF2BC35),
            BorderRadius.circular(999),
          ),
          piece(
            118,
            62,
            9,
            4,
            -0.55,
            const Color(0xFFFFD76A),
            BorderRadius.circular(10),
          ),
          piece(
            212,
            56,
            8,
            8,
            0.0,
            const Color(0xFFFFC400),
            BorderRadius.circular(999),
          ),
          piece(
            304,
            60,
            10,
            4,
            0.5,
            const Color(0xFF8B6813),
            BorderRadius.circular(10),
          ),
          piece(
            396,
            54,
            8,
            8,
            0.0,
            const Color(0xFFF2BC35),
            BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }
}

class GameStatusBadge extends StatelessWidget {
  final String status;

  const GameStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    late Color color;
    late String label;

    switch (normalized) {
      case 'live':
        color = const Color(0xFFF2BC35);
        label = '● LIVE';
        break;
      case 'completed':
        color = const Color(0xFF8B98A8);
        label = 'FINAL';
        break;
      default:
        color = const Color(0xFF7F8B98);
        label = 'SCHEDULED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
