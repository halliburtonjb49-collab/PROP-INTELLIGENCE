import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../controllers/active_slip_controller.dart';
import '../models/saved_slip.dart';
import '../services/api_service.dart';
import '../services/live_update_service.dart';
import '../services/player_image_resolver.dart';
import '../services/slip_manager.dart';
import 'context_help.dart';

import '../theme/app_colors.dart' as brand_colors;

class _LegPhoto extends StatelessWidget {
  final SavedSlipLeg leg;
  final double size;

  const _LegPhoto({required this.leg, this.size = 40});

  Widget _placeholder() {
    final initial = leg.player.trim().isEmpty
        ? '?'
        : leg.player.trim().substring(0, 1).toUpperCase();
    return Container(
      color: brand_colors.AppColors.bgPanel,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: brand_colors.AppColors.gold,
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
      key: ValueKey(imagePath),
      imageUrl: imagePath,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }
}

/// [active] is the Slip Watcher page - unresolved slips only, with
/// result acknowledgement and unlock actions. [history] is the Past Slip History page -
/// resolved (won/lost) slips only, read-only.
enum SlipHistoryMode { active, history }

@visibleForTesting
bool supportsEnhancedSlipWatcher({
  required SlipHistoryMode mode,
  required bool hasProAccess,
}) {
  return mode == SlipHistoryMode.active;
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
    this.isActive = true,
    this.onClose,
  });

  final ActiveSlipController activeSlipController;
  final SlipHistoryMode mode;
  final bool hasProAccess;
  final bool isActive;
  final VoidCallback? onClose;

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
  List<SavedSlip> _lastGoodSlips = const [];
  List<SavedSlip> _historySummarySlips = const [];
  final Set<String> _earlyWinNotified = <String>{};
  final Set<String> _piWeakeningNotified = <String>{};
  final Set<String> _updatingSlipIds = <String>{};

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
    late final List<SavedSlip> result;
    if (!_isHistory) {
      final slips = await _apiService.fetchSlips(status: 'active');
      result = widget.activeSlipController.mergeWithRecentLockedSlips(slips);
    } else {
      final all = await _apiService.fetchSlips();
      final resolved = all
          .where((slip) => slip.status.toLowerCase() != 'active')
          .toList();
      final available = limitHistoryForCore(
        resolved,
        hasProAccess: widget.hasProAccess,
      );
      _historySummarySlips = available;
      result = tab == 'all'
          ? available
          : available
                .where((slip) => slip.status.toLowerCase() == tab)
                .toList(growable: false);
    }
    _rememberSlips(result);
    return result;
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = _isHistory ? 'all' : 'active';
    final recent = widget.activeSlipController.recentLockedSlips;
    _slipsFuture = !widget.isActive
        ? Future.value(recent)
        : !_isHistory && recent.isNotEmpty
        ? Future.value(recent)
        : _fetchForTab(_selectedTab);
    widget.activeSlipController.addListener(_handleLockedSlipChange);
    if (widget.isActive) unawaited(_refreshLockedSlipCount());
    _liveSubscription = _liveUpdates.stream.listen((_) {
      if (widget.isActive) _reloadFromTicketEvent();
    }, onError: (_) {});
    if (widget.isActive) _liveUpdates.connect();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isHistory) {
          unawaited(_reconcileHistory());
        } else {
          unawaited(_reloadSlipsOnly());
        }
      });
    }
    if (widget.isActive) _startPolling();
  }

  void _startPolling() {
    _refreshTimer?.cancel();
    // Opening Watch should reconcile and archive completed tickets now,
    // rather than leaving a stale FINAL/PENDING card until the first timer.
    unawaited(_refreshGameStatuses());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshGameStatuses(),
    );
    if (_hasEnhancedLiveTracking) _startLiveStatsTracking();
  }

  void _stopPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _stopLiveStatsTracking();
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
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _liveUpdates.resume();
        final recent = widget.activeSlipController.recentLockedSlips;
        if (!_isHistory && recent.isNotEmpty) {
          _rememberSlips(recent);
          setState(() => _slipsFuture = Future.value(recent));
          unawaited(_reloadSlipsOnly());
        } else {
          setState(() => _slipsFuture = _fetchForTab(_selectedTab));
        }
        unawaited(_refreshLockedSlipCount());
        _startPolling();
      } else {
        unawaited(_liveUpdates.pause());
        _stopPolling();
      }
      return;
    }
    if (!widget.isActive) return;
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
      _notifyEarlyWinners(stats);
      _notifyPiWeakening(stats);
      unawaited(_settleCompletedTickets(stats));
    } catch (_) {
      // Keep the last known live stats on a transient failure.
    }
  }

  Future<void> _settleCompletedTickets(
    Map<String, Map<String, dynamic>> stats,
  ) async {
    if (_isHistory) return;
    for (final slip in List<SavedSlip>.from(_lastGoodSlips)) {
      final slipStats = stats[slip.id] ?? const <String, dynamic>{};
      // A ticket can become mathematically lost before every game ends, but
      // moving it to history at that moment stops live polling for its other
      // legs. Keep it in Watch until every leg has an authoritative FINAL so
      // all progress and permanent result values are recorded correctly.
      final allLegsFinal = slip.legs.every(
        (leg) => _effectiveLegState(leg, slipStats).gameCompleted,
      );
      if (!allLegsFinal) continue;
      final status = terminalSlipStatus(slip, slipStats);
      if (status == null || _updatingSlipIds.contains(slip.id)) continue;
      await _changeStatus(slip, status, automatic: true);
    }
  }

  void _notifyEarlyWinners(Map<String, Map<String, dynamic>> stats) {
    for (final slip in _lastGoodSlips) {
      if (_earlyWinNotified.contains(slip.id)) continue;
      final projection = _slipLiveProjection(slip, stats[slip.id] ?? const {});
      if (projection != _SlipLiveProjection.winning) continue;
      _earlyWinNotified.add(slip.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF8CFFB2),
          content: Text(
            'WINNING TICKET — every pick has already cleared its line.',
            style: TextStyle(
              color: brand_colors.AppColors.bgBase,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }
  }

  void _notifyPiWeakening(Map<String, Map<String, dynamic>> stats) {
    for (final slip in _lastGoodSlips) {
      final slipStats = stats[slip.id] ?? const <String, dynamic>{};
      for (final leg in slip.legs) {
        final live = slipStats[leg.propId];
        if (live is! Map ||
            live['pi_change_status'] != 'WEAKENED' ||
            live['pi_material_change'] != true) {
          continue;
        }
        final key = '${slip.id}:${leg.propId}:${live['current_projection']}:${live['current_confidence']}';
        if (!_piWeakeningNotified.add(key)) continue;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFFF8A65),
            content: Text(
              'PI UPDATE: ${leg.player} has weakened. Open Watch to review what changed.',
              style: const TextStyle(
                color: brand_colors.AppColors.bgBase,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      }
    }
  }

  void _rememberSlips(List<SavedSlip> slips) {
    _lastGoodSlips = slips;
    if (!_isHistory) {
      widget.activeSlipController.reconcileActiveLockedSlips(slips);
      SlipManager.reserveActiveSlips(slips);
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
    if (!mounted || _isHistory || !widget.isActive) return;
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
      _rememberSlips(slips);
      widget.activeSlipController.setLockedSlipCount(slips.length);
    } catch (_) {
      // Keep the optimistic/local ticket visible during a transient failure.
    }
  }

  Future<void> _reconcileHistory() async {
    try {
      await _apiService.reconcileSlips();
    } catch (_) {
      // History remains readable if authoritative verification is unavailable.
    }
    await _reloadSlipsOnly();
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

  Future<void> _changeStatus(
    SavedSlip slip,
    String status, {
    bool automatic = false,
  }) async {
    if (_updatingSlipIds.contains(slip.id)) return;
    if (slip.id.startsWith('pending-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This ticket is still syncing. Try again in a moment.'),
        ),
      );
      return;
    }
    setState(() => _updatingSlipIds.add(slip.id));
    try {
      await _apiService.updateSlipStatus(
        slipId: slip.id,
        status: status,
        recalculation: Map<String, dynamic>.from(
          _liveStats[slip.id] ?? const <String, dynamic>{},
        ),
      );
      if (!mounted) return;
      final remaining = _lastGoodSlips
          .where((item) => item.id != slip.id)
          .toList();
      widget.activeSlipController.removeLockedSlip(slip.id);
      SlipManager.reserveActiveSlips(remaining);
      setState(() {
        _updatingSlipIds.remove(slip.id);
        _lastGoodSlips = remaining;
        _slipsFuture = Future.value(remaining);
        _refreshError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: brand_colors.AppColors.gold,
          content: Text(
            automatic
                ? 'Final ticket moved to Past Tickets.'
                : status == 'won'
                ? 'Win acknowledged and moved to Past Tickets.'
                : 'Ticket marked lost and moved to Past Tickets.',
            style: const TextStyle(
              color: brand_colors.AppColors.bgBase,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
      unawaited(_reloadSlipsOnly());
      unawaited(_refreshLockedSlipCount());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _updatingSlipIds.remove(slip.id);
        _refreshError =
            'That result could not be saved. Check your connection and try again.';
      });
    }
  }

  Future<void> _unlockSlip(SavedSlip slip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: brand_colors.AppColors.bgPanel,
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
              foregroundColor: brand_colors.AppColors.danger,
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
    widget.activeSlipController.removeLockedSlip(slip.id);
    final remaining = _lastGoodSlips
        .where((item) => item.id != slip.id)
        .toList();
    _lastGoodSlips = remaining;
    SlipManager.reserveActiveSlips(remaining);
    setState(() {
      _slipsFuture = Future.value(remaining);
    });
    unawaited(_reloadSlipsOnly());
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
      String? backgroundSyncError;
      if (_isHistory) {
        try {
          await _apiService.reconcileSlips();
        } catch (_) {
          backgroundSyncError =
              'Official result verification is retrying; saved history is still available.';
        }
        final refreshedSlips = await _fetchForTab(_selectedTab);
        if (!mounted) return;
        setState(() {
          _lastUpdated = DateTime.now();
          _slipsFuture = Future.value(refreshedSlips);
          _refreshError = backgroundSyncError;
        });
        return;
      }
      try {
        await _apiService.refreshSavedSlipGameStatuses();
      } catch (_) {
        backgroundSyncError =
            'Game-status sync is retrying; your saved ticket remains available.';
      }
      try {
        // Grade every completed leg covered by an authoritative stat provider.
        await _apiService.gradePendingSlips();
      } catch (_) {
        backgroundSyncError ??=
            'Live grading is retrying; your saved ticket remains available.';
      }
      final refreshedSlips = await _fetchForTab(_selectedTab);
      _rememberSlips(refreshedSlips);
      await _syncActiveSlipFromSavedSlips(refreshedSlips);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastUpdated = DateTime.now();
        _slipsFuture = Future.value(refreshedSlips);
        _refreshError = backgroundSyncError;
      });
      unawaited(_refreshLockedSlipCount());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshError =
            'Live updates paused briefly. Your last ticket view is still safe; tap refresh to retry.';
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(
                    _isHistory ? 'PAST SLIP HISTORY' : 'SLIP WATCHER',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isHistory
                        ? 'Settled slips and final outcomes'
                        : 'Saved slips with live grading',
                    style: const TextStyle(
                      color: brand_colors.AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Independent sports research and tracking only. Prop Intelligence does not accept wagers, operate a sportsbook, or facilitate betting transactions.',
                    style: TextStyle(
                      color: brand_colors.AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  ],
                ),
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
                          color: brand_colors.AppColors.gold,
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
                                color: brand_colors.AppColors.gold,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 19),
                      color: brand_colors.AppColors.gold,
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        key: const ValueKey('close-slip-watcher'),
                        tooltip: _isHistory
                            ? 'Close Past Slip History'
                            : 'Close Slip Watcher',
                        onPressed: widget.onClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: brand_colors.AppColors.white,
                          size: 21,
                        ),
                      ),
                  ],
                ),
                if (_lastUpdated != null)
                  Text(
                    'Updated ${TimeOfDay.fromDateTime(_lastUpdated!).format(context)}',
                    style: const TextStyle(
                      color: brand_colors.AppColors.textMuted,
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
                color: brand_colors.AppColors.silver.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: brand_colors.AppColors.silver),
              ),
              child: const Text(
                'CORE HISTORY • LAST 14 DAYS • STANDARD WIN/LOSS GRADING',
                style: TextStyle(
                  color: brand_colors.AppColors.silver,
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
              color: brand_colors.AppColors.goldSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: brand_colors.AppColors.goldShadow),
            ),
            child: Row(
              children: [
                Icon(
                  _isRefreshingGames ? Icons.sync : Icons.track_changes,
                  size: 15,
                  color: brand_colors.AppColors.gold,
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
                      color: brand_colors.AppColors.gold,
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
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _lastGoodSlips.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError && _lastGoodSlips.isEmpty) {
                return _SlipLoadError(
                  isHistory: _isHistory,
                  onRetry: _refreshGameStatuses,
                );
              }
              final slips =
                  snapshot.connectionState == ConnectionState.waiting ||
                      snapshot.hasError
                  ? _lastGoodSlips
                  : snapshot.data ?? const <SavedSlip>[];
              final totals = _buildTotals(slips);
              final now = DateTime.now();
              final todaySlips = _historySummarySlips.where((slip) {
                final created = slip.createdAt?.toLocal();
                return created != null &&
                    created.year == now.year &&
                    created.month == now.month &&
                    created.day == now.day;
              }).toList(growable: false);
              final todayTotals = _buildTotals(todaySlips);
              if (slips.isEmpty) {
                return const Center(child: Text('No slips in this view.'));
              }
              return Column(
                children: [
                  if (_isHistory) ...[
                    _TodayPickPerformance(totals: todayTotals),
                    const SizedBox(height: 10),
                  ],
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
                                    isUpdating: _updatingSlipIds.contains(
                                      slip.id,
                                    ),
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
        height: 44,
        child: OutlinedButton(
          onPressed: () => _selectTab(value),
          style: OutlinedButton.styleFrom(
            backgroundColor: selected
                ? const Color(0xFF5A3B08)
                : brand_colors.AppColors.bgPanel,
            foregroundColor: selected
                ? brand_colors.AppColors.gold
                : Colors.white,
            side: BorderSide(
              color: selected
                  ? brand_colors.AppColors.gold
                  : brand_colors.AppColors.chromeShadow,
            ),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
        ? brand_colors.AppColors.gold
        : brand_colors.AppColors.silver;
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
                color: brand_colors.AppColors.silver,
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

class _TodayPickPerformance extends StatelessWidget {
  const _TodayPickPerformance({required this.totals});

  final _SlipTotals totals;

  @override
  Widget build(BuildContext context) {
    final graded = totals.wonLegs + totals.lostLegs;
    final winRate = graded == 0 ? 0.0 : totals.wonLegs / graded * 100;
    final lossRate = graded == 0 ? 0.0 : totals.lostLegs / graded * 100;

    Widget metric(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: brand_colors.AppColors.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: brand_colors.AppColors.bgPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: brand_colors.AppColors.gold.withValues(alpha: .62),
        ),
      ),
      child: Row(
        children: [
          metric('TODAY\'S GRADED PICKS', '$graded', Colors.white),
          metric(
            'WINS',
            '${totals.wonLegs}  |  ${winRate.toStringAsFixed(1)}%',
            brand_colors.AppColors.success,
          ),
          metric(
            'LOSSES',
            '${totals.lostLegs}  |  ${lossRate.toStringAsFixed(1)}%',
            brand_colors.AppColors.danger,
          ),
          metric(
            'PENDING',
            '${totals.pendingLegs}',
            brand_colors.AppColors.warning,
          ),
        ],
      ),
    );
  }

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
        color: brand_colors.AppColors.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand_colors.AppColors.gunmetalLight),
      ),
      child: Row(
        children: [
          Icon(
            Icons.show_chart_rounded,
            size: 16,
            color: positive
                ? brand_colors.AppColors.blue
                : brand_colors.AppColors.gold,
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
            color: brand_colors.AppColors.bgPanel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: brand_colors.AppColors.textMuted,
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
        pill('SLIPS', '${totals.totalSlips}', brand_colors.AppColors.silver),
        const SizedBox(width: 8),
        pill('SLIP WINS', '${totals.wonSlips}', brand_colors.AppColors.success),
        const SizedBox(width: 8),
        pill(
          'SLIP LOSSES',
          '${totals.lostSlips}',
          brand_colors.AppColors.danger,
        ),
        const SizedBox(width: 8),
        pill(
          'PENDING',
          '${totals.pendingLegs}',
          brand_colors.AppColors.warning,
        ),
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
        color: brand_colors.AppColors.bgPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand_colors.AppColors.gunmetalLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: brand_colors.AppColors.gold,
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
                      ? brand_colors.AppColors.gold
                      : brand_colors.AppColors.danger,
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
                        color: brand_colors.AppColors.sidebar,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${entry.key}: ${money(entry.value)}',
                        style: TextStyle(
                          color: entry.value >= 0
                              ? brand_colors.AppColors.gold
                              : brand_colors.AppColors.danger,
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

class _SlipLoadError extends StatelessWidget {
  const _SlipLoadError({required this.isHistory, required this.onRetry});

  final bool isHistory;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: brand_colors.AppColors.gold,
              size: 34,
            ),
            const SizedBox(height: 12),
            const Text(
              'TICKET HISTORY IS TEMPORARILY OFFLINE',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              isHistory
                  ? 'Your saved tickets are safe. History will sync automatically when the connection returns.'
                  : 'Your tickets remain saved. Live grading will resume automatically when the connection returns.',
              textAlign: TextAlign.center,
              style: TextStyle(color: brand_colors.AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _LiveLegState = ({
  double? current,
  String resultStatus,
  String gameStatus,
  String gameDetail,
  bool gameCompleted,
  double? currentProjection,
  int? currentConfidence,
  String piChangeStatus,
  List<Map<String, dynamic>> piChanges,
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
      gameDetail: '',
      gameCompleted: leg.gameCompleted,
      currentProjection: leg.currentProjection ?? leg.projection,
      currentConfidence: leg.currentConfidence ?? leg.confidence,
      piChangeStatus: leg.piChangeStatus,
      piChanges: leg.piChanges,
    );
  }
  final rawGameStatus = live['game_status']?.toString() ?? leg.gameStatus;
  return (
    current: (live['result_value'] as num?)?.toDouble() ?? leg.resultValue,
    resultStatus: live['result_status']?.toString() ?? leg.resultStatus,
    gameStatus: rawGameStatus,
    gameDetail: live['game_detail']?.toString() ?? '',
    gameCompleted: rawGameStatus.toLowerCase() == 'final',
    currentProjection: (live['current_projection'] as num?)?.toDouble(),
    currentConfidence: (live['current_confidence'] as num?)?.toInt(),
    piChangeStatus: live['pi_change_status']?.toString() ?? 'UNCHANGED',
    piChanges: (live['pi_changes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false),
  );
}

String _piChangeSummary(_LiveLegState live) {
  return live.piChanges.map((change) {
    final label = change['label']?.toString() ?? 'Evidence';
    return '$label ${change['original']} -> ${change['current']}';
  }).join('  •  ');
}

/// Live projection for an active slip as a whole, from its legs' live
/// state - not the official graded result. Null means no live data has
/// loaded for this slip yet, so callers should fall back to "ACTIVE".
enum _SlipLiveProjection { winning, losing, live }

_SlipLiveProjection? _slipLiveProjection(
  SavedSlip slip,
  Map<String, dynamic> legLiveStats,
) {
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

/// Returns a terminal saved-ticket status only after every leg has an
/// authoritative final state. This prevents a completed ticket from being
/// presented as LIVE while its status update is being persisted.
String? terminalSlipStatus(SavedSlip slip, Map<String, dynamic> legLiveStats) {
  if (slip.status.toLowerCase() == 'won') return 'won';
  if (slip.status.toLowerCase() == 'lost') return 'lost';
  if (slip.legs.isEmpty) return null;

  var hasLoss = false;
  for (final leg in slip.legs) {
    final state = _effectiveLegState(leg, legLiveStats);
    final result = state.resultStatus.toLowerCase();
    if (!state.gameCompleted ||
        !{'won', 'win', 'lost', 'loss', 'push'}.contains(result)) {
      return null;
    }
    hasLoss = hasLoss || result == 'lost' || result == 'loss';
  }
  return hasLoss ? 'lost' : 'won';
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

  String _eventTime(BuildContext context) {
    final parsed = DateTime.tryParse(leg.gameStartTime);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return TimeOfDay.fromDateTime(local).format(context);
  }

  @override
  Widget build(BuildContext context) {
    final isOver = leg.side.toUpperCase() == 'OVER';
    final pickColor = isOver
        ? brand_colors.AppColors.gold
        : brand_colors.AppColors.silver;
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
                    GameStatusBadge(
                      status: live.gameStatus,
                      detail: live.gameDetail,
                    ),
                    if (leg.resultVerified) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: leg.resultSource.isEmpty
                            ? 'Result verified'
                            : 'Verified by ${leg.resultSource}',
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: brand_colors.AppColors.success,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    leg.matchup,
                    if (_eventTime(context).isNotEmpty) _eventTime(context),
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF8996A6), fontSize: 8),
                ),
                if (leg.projection != null || leg.confidence != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (leg.projection != null)
                        'MODEL ${leg.projection!.toStringAsFixed(2)}',
                      if (leg.confidence != null) 'CONF ${leg.confidence}%',
                      if (leg.projectionSource.trim().isNotEmpty)
                        leg.projectionSource.trim().toUpperCase(),
                    ].join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: brand_colors.AppColors.gold,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text(
                      live.current?.floor().toString() ?? '0',
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
                            ? brand_colors.AppColors.textMuted
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
                      color: brand_colors.AppColors.textMuted,
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
              color: brand_colors.AppColors.bgPanel,
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
                    color: brand_colors.AppColors.silver,
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
  final bool isUpdating;
  final bool showDetails;

  const _SavedSlipCard({
    required this.slip,
    this.liveStats = const {},
    required this.onWon,
    required this.onLost,
    required this.onUnlock,
    this.isUpdating = false,
    this.showDetails = false,
  });

  _LiveLegState _liveState(SavedSlipLeg leg) =>
      _effectiveLegState(leg, liveStats);

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = slip.status.toLowerCase();
    final terminalStatus = terminalSlipStatus(slip, liveStats);
    final isWon = terminalStatus == 'won';
    final isLost = terminalStatus == 'lost';
    final liveProjection =
        normalizedStatus == 'active' && terminalStatus == null
        ? _slipLiveProjection(slip, liveStats)
        : null;
    final isLiveWinning = liveProjection == _SlipLiveProjection.winning;
    final isLiveLosing = liveProjection == _SlipLiveProjection.losing;
    final borderColor = isWon
        ? brand_colors.AppColors.gold
        : isLiveWinning
        ? const Color(0xFF4CAF50)
        : isLost || isLiveLosing
        ? brand_colors.AppColors.danger
        : brand_colors.AppColors.gold;
    final statusColor = isWon
        ? brand_colors.AppColors.gold
        : isLiveWinning
        ? const Color(0xFF4CAF50)
        : isLost || isLiveLosing
        ? brand_colors.AppColors.danger
        : brand_colors.AppColors.gold;
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
        color: brand_colors.AppColors.bgPanel,
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
                    if (normalizedStatus == 'active' &&
                        terminalStatus == null) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Unlock (remove) this slip',
                        child: IconButton(
                          onPressed: onUnlock,
                          icon: const Icon(
                            Icons.lock_open_rounded,
                            size: 13,
                            color: brand_colors.AppColors.textMuted,
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
                      statusColor = brand_colors.AppColors.danger;
                      statusLabel = 'LOST';
                      break;
                    case 'push':
                      statusColor = brand_colors.AppColors.textMuted;
                      statusLabel = 'PUSH';
                      break;
                    default:
                      statusColor = brand_colors.AppColors.gold;
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
                                  color: brand_colors.AppColors.gold,
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
                            GameStatusBadge(
                              status: live.gameStatus,
                              detail: live.gameDetail,
                            ),
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
                            color: brand_colors.AppColors.bgPanel,
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
                                        : '${live.current!.floor()} / ${leg.line.toStringAsFixed(1)}',
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
                                      ? brand_colors.AppColors.textMuted
                                      : statusColor,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (leg.projection != null || leg.piTrustScore > 0)
                          Text(
                            [
                              if (leg.projection != null)
                                'ENTRY MODEL ${leg.projection!.toStringAsFixed(2)}',
                              if (leg.piTrustScore > 0)
                                'PI TRUST ${leg.piTrustScore}/100',
                              if (leg.projectionSource.trim().isNotEmpty)
                                leg.projectionSource.trim().toUpperCase(),
                              if (leg.projectionModelVersion.trim().isNotEmpty)
                                'V${leg.projectionModelVersion.trim()}',
                              leg.projectionCalibrated
                                  ? 'CALIBRATED'
                                  : 'UNCALIBRATED',
                            ].join('  •  '),
                            style: const TextStyle(
                              color: brand_colors.AppColors.gold,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        if (leg.projection != null || leg.piTrustScore > 0)
                          const SizedBox(height: 6),
                        if (live.piChangeStatus != 'UNCHANGED') ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF091620),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: live.piChangeStatus == 'IMPROVED'
                                    ? brand_colors.AppColors.success
                                    : live.piChangeStatus == 'WEAKENED'
                                    ? const Color(0xFFFF8A65)
                                    : brand_colors.AppColors.blue,
                              ),
                            ),
                            child: Text(
                              'WHAT CHANGED • PI ${live.piChangeStatus}\n${_piChangeSummary(live)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (showDetails && leg.closingLine == null)
                          const Text(
                            'CLV: pending closing line',
                            style: TextStyle(
                              color: brand_colors.AppColors.textMuted,
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
                                  ? brand_colors.AppColors.blue
                                  : const Color(0xFFFFB74D),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                if (normalizedStatus == 'active' && terminalStatus == null) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF071520),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isLiveWinning
                            ? brand_colors.AppColors.gold
                            : const Color(0xFF2A3B48),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isUpdating)
                          const SizedBox.square(
                            dimension: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: brand_colors.AppColors.gold,
                            ),
                          )
                        else
                          Icon(
                            Icons.sync_rounded,
                            size: 14,
                            color: isLiveWinning
                                ? brand_colors.AppColors.gold
                                : const Color(0xFF8FA5B5),
                          ),
                        const SizedBox(width: 7),
                        Text(
                          isUpdating
                              ? 'FINALIZING RESULT'
                              : 'AUTO-GRADING • REFRESHES EVERY 20 SEC',
                          style: TextStyle(
                            color: isLiveWinning
                                ? brand_colors.AppColors.gold
                                : const Color(0xFF8FA5B5),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
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
                    brand_colors.AppColors.gold.withValues(alpha: 0.05),
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
            brand_colors.AppColors.gold,
            BorderRadius.circular(999),
          ),
          piece(
            98,
            12,
            12,
            4,
            -0.45,
            brand_colors.AppColors.goldShadow,
            BorderRadius.circular(10),
          ),
          piece(
            145,
            20,
            8,
            8,
            0.0,
            brand_colors.AppColors.gold,
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
            brand_colors.AppColors.gold,
            BorderRadius.circular(999),
          ),
          piece(
            278,
            16,
            11,
            4,
            -0.3,
            brand_colors.AppColors.goldShadow,
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
            brand_colors.AppColors.gold,
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
            brand_colors.AppColors.gold,
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
            brand_colors.AppColors.gold,
            BorderRadius.circular(999),
          ),
          piece(
            304,
            60,
            10,
            4,
            0.5,
            brand_colors.AppColors.goldShadow,
            BorderRadius.circular(10),
          ),
          piece(
            396,
            54,
            8,
            8,
            0.0,
            brand_colors.AppColors.gold,
            BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }
}

class GameStatusBadge extends StatelessWidget {
  final String status;
  final String detail;

  const GameStatusBadge({super.key, required this.status, this.detail = ''});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    late Color color;
    late String label;

    switch (normalized) {
      case 'live':
      case 'in_progress':
      case 'in progress':
      case 'inprogress':
      case 'ongoing':
        color = brand_colors.AppColors.gold;
        final gameContext = detail.trim();
        label = gameContext.isEmpty
            ? '\u25CF LIVE'
            : '\u25CF LIVE \u2022 $gameContext';
        break;
      case 'completed':
      case 'final':
      case 'finished':
      case 'closed':
        color = brand_colors.AppColors.textMuted;
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
