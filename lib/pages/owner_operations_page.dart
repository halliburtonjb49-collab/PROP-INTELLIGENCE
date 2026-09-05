import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/prop_data.dart';
import '../models/game_market.dart';
import '../services/api_service.dart';
import '../services/prop_chat_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_colors.dart' as brand_colors;
import '../widgets/owner_command_center_overview.dart';
import '../widgets/owner_model_audit_panel.dart';
import '../widgets/owner_user_account_controls.dart';
import '../widgets/provider_availability_dashboard.dart';
import '../widgets/provider_reliability_banner.dart';

class OwnerOperationsPage extends StatefulWidget {
  const OwnerOperationsPage({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<OwnerOperationsPage> createState() => _OwnerOperationsPageState();
}

class _OwnerMoneylinePick {
  const _OwnerMoneylinePick({
    required this.event,
    required this.team,
    required this.fairProbability,
    required this.price,
    required this.sportsbook,
    required this.bookCount,
    required this.stale,
  });

  final GameMarketEvent event;
  final String team;
  final double fairProbability;
  final int price;
  final String sportsbook;
  final int bookCount;
  final bool stale;
}

class _OwnerMoneylineCard extends StatelessWidget {
  const _OwnerMoneylineCard({
    required this.rank,
    required this.pick,
    required this.sport,
  });

  final int rank;
  final _OwnerMoneylinePick pick;
  final String sport;

  @override
  Widget build(BuildContext context) {
    final price = pick.price > 0 ? '+${pick.price}' : '${pick.price}';
    final start = pick.event.commenceTime?.toLocal();
    final time = start == null
        ? 'TBD'
        : TimeOfDay.fromDateTime(start).format(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: .14),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold),
            ),
            child: Text(
              '#$rank',
              style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pick.team,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$sport  •  ${pick.event.awayTeam} @ ${pick.event.homeTeam}  •  $time',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'BEST LISTED $price  •  ${pick.sportsbook.toUpperCase()}  •  ${pick.bookCount} BOOKS${pick.stale ? '  •  CACHED — VERIFY' : ''}',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(pick.fairProbability * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Color(0xFF8CFFB2),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'SHIN FAIR',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

@visibleForTesting
List<PropData> mergeOwnerTopPicksForRefresh({
  required List<PropData> previous,
  required List<PropData> fresh,
  required Set<String> successfulSports,
  required List<String> sportOrder,
}) {
  final freshBySport = <String, List<PropData>>{};
  final previousBySport = <String, List<PropData>>{};
  for (final prop in fresh) {
    freshBySport
        .putIfAbsent(prop.sport.trim().toUpperCase(), () => [])
        .add(prop);
  }
  for (final prop in previous) {
    previousBySport
        .putIfAbsent(prop.sport.trim().toUpperCase(), () => [])
        .add(prop);
  }

  final merged = <PropData>[];
  for (final sport in sportOrder) {
    final current = freshBySport[sport] ?? const <PropData>[];
    if (current.isNotEmpty || successfulSports.contains(sport)) {
      merged.addAll(current.take(5));
    } else {
      // A failed sport request must not erase that sport's last verified
      // daily shortlist. Successful empty responses still remove inactive
      // sports, and the static cache is cleared at the next local day.
      merged.addAll((previousBySport[sport] ?? const <PropData>[]).take(5));
    }
  }
  return merged;
}

@visibleForTesting
List<PropData> selectOwnerTopFiveWithPrizePicks(List<PropData> ranked) {
  if (ranked.length <= 5 || ranked.take(5).any(_isPrizePicksOwnerProp)) {
    return ranked.take(5).toList(growable: false);
  }
  PropData? prizePicks;
  for (final prop in ranked.skip(5)) {
    if (_isPrizePicksOwnerProp(prop)) {
      prizePicks = prop;
      break;
    }
  }
  if (prizePicks == null) return ranked.take(5).toList(growable: false);

  // Keep the four strongest overall signals and guarantee that the best
  // available PrizePicks line is represented in the owner shortlist.
  return <PropData>[...ranked.take(4), prizePicks];
}

bool _isPrizePicksOwnerProp(PropData prop) {
  final provider = prop.sportsbook.toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9]+'),
    '',
  );
  return provider.contains('PRIZEPICKS');
}

@visibleForTesting
String ownerResearchSide(PropData prop) {
  final proSide = prop.proSuggestedSide?.trim().toUpperCase() ?? '';
  if (proSide == 'OVER' || proSide == 'UNDER') return proSide;
  final boardSide = prop.pick.trim().toUpperCase();
  if (boardSide == 'OVER' || boardSide == 'UNDER') return boardSide;
  return 'REVIEW';
}

@visibleForTesting
bool isOwnerResearchCandidate(PropData prop) =>
    prop.player.trim().isNotEmpty &&
    prop.market.trim().isNotEmpty &&
    prop.line.isFinite &&
    ownerResearchSide(prop) != 'REVIEW';

class _OwnerOperationsPageState extends State<OwnerOperationsPage> {
  static List<PropData> _cachedOwnerTopPicks = const [];
  static DateTime? _cachedOwnerTopPicksDay;
  static Map<String, List<_OwnerMoneylinePick>> _cachedOwnerMoneylines =
      const {};

  late final ApiService _api = widget.apiService ?? ApiService();
  Map<String, dynamic>? _control;
  Map<String, dynamic>? _billing;
  Map<String, dynamic>? _commandCenter;
  Map<String, dynamic>? _modelAudit;
  Map<String, dynamic>? _review;
  Map<String, dynamic>? _providerAvailability;
  Map<String, dynamic>? _providerRecovery;
  Map<String, dynamic>? _identityRegistry;
  Map<String, dynamic> _providerReliability = const {};
  List<PropData> _ownerTopPicks = _cachedOwnerTopPicks;
  Map<String, List<_OwnerMoneylinePick>> _ownerMoneylines =
      _cachedOwnerMoneylines;
  bool _recoverySubmitting = false;
  bool _reconcilingIdentity = false;
  Map<String, dynamic> _strikeoutControlsDraft = const {};
  bool _savingStrikeoutControls = false;
  bool _loading = true;
  String? _error;
  DateTime? _lastChecked;

  Timer? _retryTimer;
  Timer? _liveRefreshTimer;
  int _consecutiveFailures = 0;
  String _selectedWindow = 'today';
  DateTimeRange? _customRange;

  // A deploy or a brief network fault used to leave this screen showing dashes
  // until somebody reloaded the page. It now retries on its own, backing off
  // so a genuinely down API is not hammered.
  static const List<Duration> _retryBackoff = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
  ];
  static const List<String> _ownerPickSports = [
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
  static const List<String> _ownerMoneylineSports = [
    'MLB',
    'NFL',
    'NBA',
    'WNBA',
    'NHL',
    'NCAAF',
    'NCAAB',
    'CFL',
    'EPL',
    'MLS',
  ];

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    if (_cachedOwnerTopPicksDay != today) {
      _cachedOwnerTopPicks = const [];
      _cachedOwnerTopPicksDay = today;
      _ownerTopPicks = const [];
    }
    // Paint today's last verified device snapshot immediately. The live
    // requests below replace it in the background, so returning to Command
    // Center never starts from a blank slate or carries picks into a new day.
    unawaited(_hydrateDailyPicksFromDevice());
    unawaited(_refresh());
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) unawaited(_refresh(showLoading: false));
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay =
        _retryBackoff[_consecutiveFailures.clamp(0, _retryBackoff.length - 1)];
    _retryTimer = Timer(delay, () {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<Map<String, dynamic>> _optionalSnapshot(
    Future<Map<String, dynamic>> request,
  ) async {
    try {
      return await request;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _hydrateDailyPicksFromDevice() async {
    final cachedPropPages = await Future.wait(
      _ownerPickSports.map(
        (sport) => _api
            .loadCachedProps(
              selectedSport: sport,
              sortBy: 'trust',
              verdictFilter: 'ALL',
            )
            .catchError((_) => <PropData>[]),
      ),
    );
    final cachedMarketFeeds = await Future.wait<GameMarketFeed?>(
      _ownerMoneylineSports.map(
        (sport) => _api.loadCachedGameMarkets(sport).catchError((_) => null),
      ),
    );
    // A faster live response wins over this startup snapshot.
    if (!mounted || _lastChecked != null) return;
    final cachedPicks = _rankOwnerTopPicks(
      cachedPropPages.expand((page) => page).toList(growable: false),
    );
    final cachedMoneylines = <String, List<_OwnerMoneylinePick>>{};
    for (var index = 0; index < _ownerMoneylineSports.length; index++) {
      final picks = _rankMoneylines(
        cachedMarketFeeds[index],
        allowCached: true,
      );
      if (picks.isNotEmpty) {
        cachedMoneylines[_ownerMoneylineSports[index]] = picks;
      }
    }
    if (cachedPicks.isEmpty && cachedMoneylines.isEmpty) return;
    setState(() {
      if (cachedPicks.isNotEmpty) _ownerTopPicks = cachedPicks;
      if (cachedMoneylines.isNotEmpty) {
        _ownerMoneylines = {..._ownerMoneylines, ...cachedMoneylines};
      }
    });
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (mounted && showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // Fetch every sport independently. A single mixed catalog page can be
      // exhausted by a high-volume league before another active league is
      // represented, which made its Owner Top 5 silently disappear.
      final topPicksRequest =
          Future.wait(
            _ownerPickSports.map((sport) async {
              try {
                final props = await _api.fetchProps(
                  selectedSport: sport,
                  sortBy: 'trust',
                  verdictFilter: 'ALL',
                  // The panel only renders five unique picks. Pull a small
                  // cushion for duplicate provider lines instead of asking
                  // the API to build and serialize 900 props at once.
                  limit: 50,
                  // Reliability is already loaded by the command-center
                  // snapshot below. Rebuilding the complete provider report
                  // for every sport made this nine-request fan-out capable
                  // of exhausting the API instance during owner login.
                  includeReliability: false,
                );
                return (sport: sport, props: props, failed: false);
              } catch (_) {
                return (sport: sport, props: <PropData>[], failed: true);
              }
            }),
          ).then(
            (sportPages) => (
              props: sportPages
                  .expand((page) => page.props)
                  .toList(growable: false),
              successfulSports: sportPages
                  .where((page) => !page.failed)
                  .map((page) => page.sport)
                  .toSet(),
            ),
          );
      final moneylineRequest = Future.wait<GameMarketFeed?>(
        _ownerMoneylineSports.map(
          (sport) => _api
              .fetchGameMarkets(sport: sport)
              .then<GameMarketFeed?>((feed) => feed)
              .catchError((_) => null),
        ),
      );
      // Pick feeds are the first thing the owner came here to see. Publish
      // them as soon as they finish instead of holding them behind billing,
      // audit, recovery, identity, and telemetry requests.
      unawaited(
        topPicksRequest.then((result) {
          if (!mounted) return;
          final ranked = _mergeOwnerTopPicks(
            _rankOwnerTopPicks(result.props),
            result.successfulSports,
          );
          setState(() {
            _ownerTopPicks = ranked;
            _cachedOwnerTopPicks = ranked;
            _cachedOwnerTopPicksDay = DateUtils.dateOnly(DateTime.now());
          });
        }),
      );
      unawaited(
        moneylineRequest.then((feeds) {
          if (!mounted) return;
          final ranked = <String, List<_OwnerMoneylinePick>>{};
          for (var index = 0; index < _ownerMoneylineSports.length; index++) {
            final picks = _rankMoneylines(feeds[index], allowCached: true);
            if (picks.isNotEmpty) ranked[_ownerMoneylineSports[index]] = picks;
          }
          if (ranked.isEmpty) return;
          setState(() {
            _ownerMoneylines = {..._ownerMoneylines, ...ranked};
            _cachedOwnerMoneylines = _ownerMoneylines;
          });
        }),
      );
      final results = await Future.wait([
        _optionalSnapshot(_api.fetchLaunchControlPanel()),
        _optionalSnapshot(_api.fetchBillingCertification()),
        _optionalSnapshot(
          _api.fetchOwnerCommandCenter(
            window: _selectedWindow,
            start: _customRange?.start,
            end: _customRange?.end.add(const Duration(days: 1)),
          ),
        ),
        _optionalSnapshot(
          _api.fetchOwnerModelAudit(
            window: _selectedWindow,
            start: _customRange?.start,
            end: _customRange?.end.add(const Duration(days: 1)),
          ),
        ),
        _optionalSnapshot(_api.fetchOwnerGradingReview()),
        _optionalSnapshot(_api.fetchProviderAvailability()),
        _optionalSnapshot(_api.fetchProviderRecovery()),
        _optionalSnapshot(_api.fetchIdentityRegistry()),
      ]);
      final topPicks = await topPicksRequest;
      final moneylineFeeds = await moneylineRequest;
      final rankedTopPicks = _mergeOwnerTopPicks(
        _rankOwnerTopPicks(topPicks.props),
        topPicks.successfulSports,
      );
      final rankedMoneylines = <String, List<_OwnerMoneylinePick>>{};
      for (var index = 0; index < _ownerMoneylineSports.length; index++) {
        final picks = _rankMoneylines(moneylineFeeds[index], allowCached: true);
        if (picks.isNotEmpty) {
          rankedMoneylines[_ownerMoneylineSports[index]] = picks;
        }
      }
      if (!mounted) return;
      setState(() {
        _control = results[0];
        _billing = results[1];
        _commandCenter = results[2];
        _modelAudit = results[3];
        _review = results[4];
        _providerAvailability = results[5];
        _providerRecovery = results[6];
        _identityRegistry = results[7];
        _providerReliability = _api.lastProviderReliability;
        _ownerTopPicks = rankedTopPicks;
        _cachedOwnerTopPicks = rankedTopPicks;
        _cachedOwnerTopPicksDay = DateUtils.dateOnly(DateTime.now());
        if (rankedMoneylines.isNotEmpty) {
          _ownerMoneylines = {..._ownerMoneylines, ...rankedMoneylines};
          _cachedOwnerMoneylines = _ownerMoneylines;
        }
        final ownerInsights =
            _control?['ownerOnlyInsights'] as Map? ?? const {};
        final controlPayload =
            ownerInsights['strikeoutReleaseControls'] as Map? ?? const {};
        final controls = controlPayload['controls'] as Map? ?? const {};
        _strikeoutControlsDraft = Map<String, dynamic>.from(
          controls.map((key, value) => MapEntry('$key', value)),
        );
        _lastChecked = DateTime.now();
      });
      _consecutiveFailures = 0;
      _retryTimer?.cancel();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        _consecutiveFailures += 1;
        _scheduleRetry();
      }
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _selectWindow(String value) async {
    if (value == 'custom') {
      final selected = await showDateRangePicker(
        context: context,
        firstDate: DateTime.now().subtract(const Duration(days: 366)),
        lastDate: DateTime.now(),
        initialDateRange: _customRange,
      );
      if (selected == null || !mounted) return;
      setState(() {
        _selectedWindow = value;
        _customRange = selected;
      });
    } else {
      setState(() {
        _selectedWindow = value;
        _customRange = null;
      });
    }
    await _refresh();
  }

  /// Opens the rows behind a tile.
  ///
  /// A count answers "how many" and immediately raises "which ones", which
  /// previously meant leaving the panel for the database.
  Future<void> _openDetail(String metric, String label) async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C1823),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _DetailSheet(
        title: label,
        future: _api.fetchOperationsDetail(metric),
      ),
    );
  }

  Map _map(String key) => _control?[key] as Map? ?? const {};

  Widget _identityRegistryPanel() {
    final data = _identityRegistry ?? const <String, dynamic>{};
    final identities = data['identities'] as Map? ?? const {};
    final inventory = data['inventory'] as List? ?? const [];
    final queue = data['queue'] as List? ?? const [];
    final alerts = inventory
        .where(
          (row) =>
              row is Map &&
              {
                'warning',
                'critical',
                'interrupted',
              }.contains('${row['status']}'),
        )
        .length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A25),
        border: Border.all(color: AppColors.gold.withValues(alpha: .55)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint, color: AppColors.gold),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'IDENTITY & MEDIA REGISTRY',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('owner-identity-reconcile'),
                onPressed: _reconcilingIdentity
                    ? null
                    : () => unawaited(_reconcileIdentityRegistry()),
                icon: _reconcilingIdentity
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 16),
                label: Text(_reconcilingIdentity ? 'RECONCILING' : 'RECONCILE'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${identities['player'] ?? 0} players  |  ${identities['team'] ?? 0} teams  |  ${data['approvedMedia'] ?? 0} approved images  |  ${data['unresolved'] ?? 0} unmatched',
            style: const TextStyle(
              color: Color(0xFFB9C3CC),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (alerts > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$alerts provider inventory drop alert(s)',
              style: const TextStyle(
                color: Color(0xFFFF7676),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (queue.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...queue.take(8).map((raw) {
              final row = raw as Map;
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${row['sport']} | ${row['provider']} | ${row['observedName']} | ${row['reason']}',
                  style: const TextStyle(
                    color: Color(0xFFD7DEE5),
                    fontSize: 12,
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Future<void> _reconcileIdentityRegistry() async {
    if (_reconcilingIdentity) return;
    setState(() => _reconcilingIdentity = true);
    try {
      await _api.reconcileIdentityRegistry();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity registry reconciled.')),
      );
      await _refresh(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Identity reconciliation failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _reconcilingIdentity = false);
    }
  }

  bool _boolControl(String key, bool fallback) {
    final value = _strikeoutControlsDraft[key];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  int _intControl(String key, int fallback) {
    final value = _strikeoutControlsDraft[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  Future<void> _saveStrikeoutControls() async {
    if (_savingStrikeoutControls) return;
    setState(() => _savingStrikeoutControls = true);
    try {
      final response = await _api.updateStrikeoutControls(
        _strikeoutControlsDraft,
      );
      if (!mounted) return;
      final controls = response['controls'] as Map? ?? const {};
      setState(() {
        _strikeoutControlsDraft = Map<String, dynamic>.from(
          controls.map((key, value) => MapEntry('$key', value)),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Strikeout controls updated.')),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update controls: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingStrikeoutControls = false);
    }
  }

  Future<String?> _ownerActionReason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0C1823),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Required audit reason (at least 5 characters)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.length >= 5) Navigator.pop(dialogContext, reason);
            },
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _updatePropControl(Map item, bool quarantined) async {
    final reason = await _ownerActionReason(
      quarantined ? 'Quarantine this prop?' : 'Restore this prop?',
    );
    if (reason == null) return;
    try {
      await _api.updateOwnerPropControl(
        item: item,
        quarantined: quarantined,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            quarantined
                ? 'Prop quarantined and hidden.'
                : 'Prop restored to the live feed.',
          ),
        ),
      );
      await _refresh(showLoading: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Owner action failed: $error')));
      }
    }
  }

  Future<void> _updateAlertAcknowledgement(Map alert, bool acknowledged) async {
    final reason = await _ownerActionReason(
      acknowledged ? 'Acknowledge this alert?' : 'Reopen this alert?',
    );
    if (reason == null) return;
    try {
      await _api.updateOwnerAlertAcknowledgement(
        alert: alert,
        acknowledged: acknowledged,
        reason: reason,
      );
      if (!mounted) return;
      await _refresh(showLoading: false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Alert action failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewItems = (_review?['items'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final failures = (_map('pipelines')['activeFailures'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _header(),
            if (_providerReliability.isNotEmpty) ...[
              const SizedBox(height: 12),
              ProviderReliabilityBanner(
                reliability: _providerReliability,
                selectedSite: 'ALL',
                onDetails: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: AppColors.background,
                  isScrollControlled: true,
                  builder: (_) => ProviderReliabilitySheet(
                    reliability: _providerReliability,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _timeFilter(),
            const SizedBox(height: 10),
            _ownerViewSelector(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.error_outline,
                'Operations data could not be loaded',
                _error!,
                const Color(0xFFFF7B7B),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle(
              'COMMAND OVERVIEW',
              'Users, memberships, inventory, model activity, and live platform services',
            ),
            const SizedBox(height: 10),
            OwnerCommandCenterOverview(
              data: _commandCenter ?? const <String, dynamic>{},
              onOpenMetric: (metric) {
                final rawKey = '${metric['key'] ?? ''}';
                final detailKey = switch (rawKey) {
                  'newUsers' => 'newSignups',
                  _ => rawKey,
                };
                _openDetail(detailKey, '${metric['label'] ?? rawKey}');
              },
            ),
            const SizedBox(height: 22),
            _sectionTitle(
              'OWNER TOP 5 PICKS BY SPORT',
              'Live, owner-only research shortlist ranked by PI Trust and edge for content preparation',
            ),
            const SizedBox(height: 10),
            _ownerTopPicksPanel(),
            const SizedBox(height: 22),
            _sectionTitle(
              'SEPARATE TEAM MONEYLINE RESEARCH — NOT PLAYER PROPS',
              'Top team-moneyline research for every active supported league; inactive leagues stay hidden and the player-prop Top 5 remains above',
            ),
            const SizedBox(height: 10),
            _ownerMoneylinePanel(),
            const SizedBox(height: 14),
            const OwnerUserAccountControls(),
            const SizedBox(height: 22),
            _sectionTitle(
              'PROP INVENTORY & DATA QUALITY',
              'Search the live catalog, inspect warnings, and drill into each provider',
            ),
            const SizedBox(height: 10),
            OwnerPropInventoryPanel(
              onPropControl: _updatePropControl,
              onAlertAcknowledgement: _updateAlertAcknowledgement,
              data:
                  _commandCenter?['inventory'] as Map<String, dynamic>? ??
                  const <String, dynamic>{},
            ),
            const SizedBox(height: 14),
            _identityRegistryPanel(),
            const SizedBox(height: 22),
            _sectionTitle(
              'SYSTEM STATUS',
              'Live production health and capacity',
            ),
            const SizedBox(height: 10),
            _statusGrid(),
            const SizedBox(height: 22),
            _sectionTitle(
              'PROVIDER AVAILABILITY',
              'Official lineup coverage, authorization, freshness, and missing-data alerts',
            ),
            const SizedBox(height: 10),
            _providerAvailabilityDashboard(),
            const SizedBox(height: 22),
            _sectionTitle(
              'SYNC CERTIFICATION',
              'Feed, worker, provider-key, broad-coverage, and automatic-retry status',
            ),
            const SizedBox(height: 10),
            _syncCertification(),
            const SizedBox(height: 22),
            _sectionTitle(
              'PRODUCTION DATA CERTIFICATION',
              'Automated provider parity, category completeness, freshness, slate, and line-history acceptance checks',
            ),
            const SizedBox(height: 10),
            _dataCertification(),
            const SizedBox(height: 22),
            _sectionTitle(
              'BILLING RELEASE CERTIFICATION',
              'Prices, trials, product mappings, entitlements, webhook delivery, and Founding Pro capacity',
            ),
            const SizedBox(height: 10),
            _billingCertification(),
            const SizedBox(height: 22),
            _sectionTitle(
              'PRODUCT OBSERVABILITY',
              'First-party crash, performance, and conversion signals with no raw prop or message content',
            ),
            const SizedBox(height: 10),
            _productObservability(),
            const SizedBox(height: 22),
            _sectionTitle(
              'PREDICTION & MODEL AUDIT',
              'Verified outcomes, confidence calibration, Over/Under performance, model versions, and pick-level inspection',
            ),
            const SizedBox(height: 10),
            OwnerModelAuditPanel(
              data: _modelAudit ?? const <String, dynamic>{},
            ),
            const SizedBox(height: 14),
            const Text(
              'RELEASE ACCOUNTABILITY',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            _modelAccountability(),
            const SizedBox(height: 22),
            _sectionTitle(
              'PI ADAPTIVE LEARNING',
              'Promoted, developing and rejected tendencies from verified prediction results',
            ),
            const SizedBox(height: 10),
            _piAdaptiveLearning(),
            const SizedBox(height: 22),
            _sectionTitle(
              'OWNER-ONLY STRIKEOUT INTELLIGENCE',
              'Log5 and binomial validation with environmental adjustments for MLB strikeout props',
            ),
            const SizedBox(height: 10),
            _strikeoutIntelligence(),
            const SizedBox(height: 22),
            _sectionTitle(
              'ISSUES REQUIRING REVIEW',
              'Unsettled legs and grades that need owner attention',
            ),
            const SizedBox(height: 10),
            if (reviewItems.isEmpty)
              _notice(
                Icons.verified_outlined,
                'No grading issues detected',
                'No overdue pending legs or unverified settled grades are currently in the queue.',
                const Color(0xFF8CFFB2),
              )
            else
              ...reviewItems.map(_reviewCard),
            const SizedBox(height: 22),
            _sectionTitle(
              'PIPELINE TRACKING',
              'Recent ingestion, refresh, and grading failures',
            ),
            const SizedBox(height: 10),
            if (failures.isEmpty)
              _notice(
                Icons.account_tree_outlined,
                'Pipelines are healthy',
                'No active pipeline failures were reported.',
                const Color(0xFF8CFFB2),
              )
            else
              ...failures.map(_pipelineCard),
            const SizedBox(height: 22),
            _sectionTitle(
              'USER FEEDBACK INBOX',
              'Live user suggestions and issue reports sent from the app',
            ),
            const SizedBox(height: 10),
            _feedbackInbox(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _requestProviderRecovery(String sport) async {
    if (_recoverySubmitting) return;
    setState(() => _recoverySubmitting = true);
    try {
      final response = await _api.requestProviderRecovery(targetSport: sport);
      if (!mounted) return;
      setState(() => _providerRecovery = response);
      final request = response['request'] as Map? ?? const {};
      final accepted = request['accepted'] == true;
      final reason =
          '${request['reason'] ?? response['message'] ?? 'Recovery status updated.'}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: accepted
              ? const Color(0xFF12634F)
              : const Color(0xFF8A3F3F),
        ),
      );
      await _refresh(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start provider recovery: $error')),
      );
    } finally {
      if (mounted) setState(() => _recoverySubmitting = false);
    }
  }

  Widget _providerAvailabilityDashboard() => ProviderAvailabilityDashboard(
    data: _providerAvailability ?? const <String, dynamic>{},
    recovery: _providerRecovery ?? const <String, dynamic>{},
    recoverySubmitting: _recoverySubmitting,
    onRecover: _requestProviderRecovery,
  );

  List<PropData> _rankOwnerTopPicks(List<PropData> props) {
    // Command Center is an owner research surface, not the customer action
    // gate. A valid catalog pick may be temporarily non-selectable because of
    // freshness/provider policy; hiding it here erased entire active sports.
    // Keep the warning banner and show the strongest real lines for review.
    final eligible = props
        .where(isOwnerResearchCandidate)
        .toList(growable: false);
    final unique = <String, PropData>{};
    for (final prop in eligible) {
      final key = [
        prop.sport.trim().toUpperCase(),
        prop.player.trim().toUpperCase(),
        (prop.displayMarket.isEmpty ? prop.market : prop.displayMarket)
            .trim()
            .toUpperCase(),
        prop.line.toStringAsFixed(2),
        ownerResearchSide(prop),
      ].join('|');
      final current = unique[key];
      if (current == null || _compareOwnerPicks(prop, current) < 0) {
        unique[key] = prop;
      }
    }
    final grouped = <String, List<PropData>>{};
    for (final prop in unique.values) {
      final sport = prop.sport.trim().toUpperCase();
      if (sport.isEmpty) continue;
      grouped.putIfAbsent(sport, () => []).add(prop);
    }
    final ranked = <PropData>[];
    final sports = grouped.keys.toList()..sort();
    for (final sport in sports) {
      final picks = grouped[sport]!..sort(_compareOwnerPicks);
      ranked.addAll(selectOwnerTopFiveWithPrizePicks(picks));
    }
    return ranked;
  }

  List<PropData> _mergeOwnerTopPicks(
    List<PropData> fresh,
    Set<String> successfulSports,
  ) => mergeOwnerTopPicksForRefresh(
    previous: _ownerTopPicks,
    fresh: fresh,
    successfulSports: successfulSports,
    sportOrder: _ownerPickSports,
  );

  int _compareOwnerPicks(PropData left, PropData right) {
    // A released actionable verdict is always the first choice. When an
    // active sport has fewer than five released plays, fill the daily board
    // with its strongest selectable research signals instead of hiding the
    // sport entirely behind an empty state.
    final actionable = (right.verdict.actionable ? 1 : 0).compareTo(
      left.verdict.actionable ? 1 : 0,
    );
    if (actionable != 0) return actionable;
    final marketPriority = _ownerMarketPriority(
      left,
    ).compareTo(_ownerMarketPriority(right));
    if (marketPriority != 0) return marketPriority;
    final bookCoverage = right.marketBookCount.compareTo(left.marketBookCount);
    if (bookCoverage != 0) return bookCoverage;
    final trust = right.piTrustScore.compareTo(left.piTrustScore);
    if (trust != 0) return trust;
    final edge = right.edge.abs().compareTo(left.edge.abs());
    if (edge != 0) return edge;
    return left.player.compareTo(right.player);
  }

  int _ownerMarketPriority(PropData prop) {
    final sport = prop.sport.trim().toUpperCase();
    final market =
        (prop.marketKey.isNotEmpty
                ? prop.marketKey
                : prop.displayMarket.isNotEmpty
                ? prop.displayMarket
                : prop.market)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
            .trim();

    bool hasAny(List<String> names) => names.any(market.contains);

    switch (sport) {
      case 'NBA':
      case 'WNBA':
      case 'NCAAB':
        if (hasAny(['points rebounds assists', 'pra'])) return 0;
        if (hasAny(['points rebounds', 'points assists'])) return 1;
        if (hasAny(['player points', 'points'])) return 2;
        if (hasAny(['player rebounds', 'rebounds'])) return 3;
        if (hasAny(['player assists', 'assists'])) return 4;
        if (hasAny(['three pointers made', '3 pointers made', 'threes'])) {
          return 5;
        }
        return 100;
      case 'NFL':
      case 'NCAAF':
      case 'CFL':
        if (hasAny(['passing yards'])) return 0;
        if (hasAny(['receiving yards'])) return 1;
        if (hasAny(['rushing yards'])) return 2;
        if (hasAny(['receptions'])) return 3;
        if (hasAny(['passing touchdowns', 'passing tds'])) return 4;
        if (hasAny(['completions', 'passing attempts'])) return 5;
        if (hasAny(['rushing receiving yards'])) return 6;
        return 100;
      case 'MLB':
        if (hasAny(['pitcher strikeouts', 'strikeouts'])) return 0;
        if (hasAny(['total bases'])) return 1;
        if (hasAny(['hits runs rbis', 'hits runs rbi'])) return 2;
        if (hasAny(['player hits', 'hits'])) return 3;
        if (hasAny(['runs batted in', 'rbis', 'rbi'])) return 4;
        if (hasAny(['runs scored', 'player runs'])) return 5;
        if (hasAny(['home runs'])) return 6;
        return 100;
      case 'NHL':
        if (hasAny(['shots on goal', 'player shots'])) return 0;
        if (hasAny(['goalie saves', 'saves'])) return 1;
        if (hasAny(['player points', 'points'])) return 2;
        if (hasAny(['player assists', 'assists'])) return 3;
        if (hasAny(['player goals', 'goals'])) return 4;
        return 100;
      default:
        return 100;
    }
  }

  Widget _ownerTopPicksPanel() {
    if (_loading && _ownerTopPicks.isEmpty) {
      return const _OwnerTopPicksLoading();
    }
    if (_ownerTopPicks.isEmpty) {
      return _notice(
        Icons.hourglass_empty_rounded,
        'NO QUALIFYING PICKS RIGHT NOW',
        'The live feed has no selectable actionable picks. This section updates automatically every 30 seconds.',
        AppColors.gold,
      );
    }
    final grouped = <String, List<PropData>>{};
    for (final prop in _ownerTopPicks) {
      grouped.putIfAbsent(prop.sport.trim().toUpperCase(), () => []).add(prop);
    }
    final dailyRanked = List<PropData>.of(_ownerTopPicks)
      ..sort(_compareOwnerPicks);
    final dailyTopFive = selectOwnerTopFiveWithPrizePicks(dailyRanked);
    return Column(
      key: const ValueKey('owner-top-picks-by-sport'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.gold.withValues(alpha: .45)),
          ),
          child: const Text(
            'OWNER USE ONLY  |  RESEARCH SIGNALS, NOT GUARANTEED OUTCOMES  |  VERIFY LIVE LINES BEFORE PUBLISHING',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _OwnerSportPickGroup(
          sport: "TODAY'S BEST 5 PLAYER PROPS • ALL ACTIVE SPORTS",
          picks: dailyTopFive,
        ),
        const SizedBox(height: 14),
        const Text(
          'PLAYER PROP TOP 5 BY ACTIVE SPORT',
          style: TextStyle(
            color: AppColors.silver,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in grouped.entries) ...[
          _OwnerSportPickGroup(sport: entry.key, picks: entry.value),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  List<_OwnerMoneylinePick> _rankMoneylines(
    GameMarketFeed? feed, {
    bool allowCached = false,
  }) {
    if (feed == null || (feed.stale && !allowCached)) return const [];
    final now = DateTime.now();
    final ranked = <_OwnerMoneylinePick>[];
    for (final event in feed.events) {
      if (event.commenceTime != null && event.commenceTime!.isBefore(now)) {
        continue;
      }
      final localStart = event.commenceTime?.toLocal();
      if (localStart == null ||
          localStart.year != now.year ||
          localStart.month != now.month ||
          localStart.day != now.day) {
        continue;
      }
      final byTeam =
          <
            String,
            List<({GameMarketOutcome outcome, SportsbookGameMarkets book})>
          >{};
      for (final book in event.bookmakers) {
        for (final outcome
            in book.markets['h2h'] ?? const <GameMarketOutcome>[]) {
          if (outcome.fairProbability == null) continue;
          byTeam.putIfAbsent(outcome.name, () => []).add((
            outcome: outcome,
            book: book,
          ));
        }
      }
      if (byTeam.isEmpty) continue;
      final candidates =
          byTeam.entries.map((entry) {
              final averageFair =
                  entry.value
                      .map((row) => row.outcome.fairProbability!)
                      .reduce((a, b) => a + b) /
                  entry.value.length;
              final best = entry.value.reduce(
                (current, next) =>
                    next.outcome.price > current.outcome.price ? next : current,
              );
              return _OwnerMoneylinePick(
                event: event,
                team: entry.key,
                fairProbability: averageFair,
                price: best.outcome.price,
                sportsbook: best.book.title,
                bookCount: entry.value.length,
                stale: feed.stale,
              );
            }).toList()
            ..sort((a, b) => b.fairProbability.compareTo(a.fairProbability));
      if (candidates.isNotEmpty) ranked.add(candidates.first);
    }
    ranked.sort((a, b) => b.fairProbability.compareTo(a.fairProbability));
    return ranked.take(5).toList(growable: false);
  }

  Widget _ownerMoneylinePanel() {
    if (_loading && _ownerMoneylines.isEmpty) {
      return const _OwnerTopPicksLoading();
    }
    if (_ownerMoneylines.isEmpty) {
      return _notice(
        Icons.sports_football_outlined,
        'NO VERIFIED MONEYLINES RIGHT NOW',
        'No active supported league currently has same-day games with enough fresh two-sided moneyline coverage. This updates automatically every 30 seconds.',
        AppColors.gold,
      );
    }
    final sportsWithPlayerProps = _ownerTopPicks
        .map((prop) => prop.sport.trim().toUpperCase())
        .where((sport) => sport.isNotEmpty)
        .toSet();
    final dailyMoneylines =
        <({String sport, _OwnerMoneylinePick pick})>[
          for (final entry in _ownerMoneylines.entries)
            if (sportsWithPlayerProps.isEmpty ||
                sportsWithPlayerProps.contains(entry.key))
              for (final pick in entry.value) (sport: entry.key, pick: pick),
        ]..sort(
          (left, right) =>
              right.pick.fairProbability.compareTo(left.pick.fairProbability),
        );
    final dailyTopFive = dailyMoneylines.take(5).toList(growable: false);
    return Column(
      key: const ValueKey('owner-moneyline-top-five-by-sport'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dailyTopFive.isNotEmpty) ...[
          const Text(
            "TODAY'S BEST 5 TEAM MONEYLINES • ACTIVE PLAYER-PROP SPORTS",
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < dailyTopFive.length; index++) ...[
            _OwnerMoneylineCard(
              rank: index + 1,
              pick: dailyTopFive[index].pick,
              sport: dailyTopFive[index].sport,
            ),
            if (index + 1 < dailyTopFive.length) const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          const Text(
            'MONEYLINE TOP 5 BY ACTIVE SPORT',
            style: TextStyle(
              color: AppColors.silver,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final sport in _ownerMoneylineSports)
          if (_ownerMoneylines[sport]?.isNotEmpty == true) ...[
            Text(
              '$sport | TOP ${_ownerMoneylines[sport]!.length}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            for (
              var index = 0;
              index < _ownerMoneylines[sport]!.length;
              index++
            ) ...[
              _OwnerMoneylineCard(
                rank: index + 1,
                pick: _ownerMoneylines[sport]![index],
                sport: sport,
              ),
              if (index + 1 < _ownerMoneylines[sport]!.length)
                const SizedBox(height: 8),
            ],
            const SizedBox(height: 14),
          ],
        const Text(
          'OWNER RESEARCH ONLY. RANKINGS USE FRESH TWO-SIDED MARKET FAIR PROBABILITY AND THE BEST AVAILABLE PRICE; NCAAF FEEDS ALSO CARRY PI GAME CONTEXT. VERIFY THE LIVE PRICE BEFORE USE.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _syncCertification() {
    final certification = _map('syncCertification');
    final checks = (certification['checks'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final status =
        certification['status']?.toString().toUpperCase() ?? 'PENDING';

    Color statusColor(String value) => switch (value) {
      'PASSED' => const Color(0xFF8CFFB2),
      'WARNING' || 'PENDING' => AppColors.gold,
      _ => const Color(0xFFFF7B7B),
    };

    if (checks.isEmpty) {
      return _notice(
        Icons.sync_problem_outlined,
        'PENDING | SYNC STATUS UNAVAILABLE',
        'The synchronization certification has not been reported yet.',
        AppColors.gold,
      );
    }

    return KeyedSubtree(
      key: const ValueKey('sync-certification'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _notice(
            status == 'PASSED'
                ? Icons.sync_outlined
                : Icons.sync_problem_outlined,
            '$status | SYNC CERTIFICATION',
            certification['automaticRetries'] == true
                ? 'Automatic retries are active.'
                : 'Automatic retries are not verified.',
            statusColor(status),
            trailing: certification['generatedAtUtc']?.toString(),
          ),
          const SizedBox(height: 8),
          ...checks.map((check) {
            final checkStatus =
                check['status']?.toString().toUpperCase() ?? 'FAILED';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                checkStatus == 'PASSED'
                    ? Icons.check_circle_outline
                    : checkStatus == 'PENDING'
                    ? Icons.schedule_outlined
                    : Icons.warning_amber_rounded,
                '$checkStatus | ${check['label'] ?? 'Sync check'}',
                check['detail']?.toString() ?? '',
                statusColor(checkStatus),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _dataCertification() {
    final certification = _map('dataCertification');
    final checks = (certification['checks'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final hasCertificationError =
        certification['error']?.toString().trim().isNotEmpty == true;
    final status =
        certification['status']?.toString().toUpperCase() ??
        (hasCertificationError ? 'FAIL' : 'PENDING');
    final summaryColor = status == 'PASS'
        ? const Color(0xFF8CFFB2)
        : status == 'WARN' || status == 'PENDING'
        ? AppColors.gold
        : const Color(0xFFFF7B7B);
    if (checks.isEmpty) {
      return _notice(
        Icons.fact_check_outlined,
        hasCertificationError
            ? 'CERTIFICATION UNAVAILABLE'
            : 'AWAITING FIRST CERTIFICATION',
        certification['error']?.toString() ??
            'The live catalog certification has not reported yet. It will appear after the next completed sync check.',
        summaryColor,
      );
    }
    return KeyedSubtree(
      key: const ValueKey('production-data-certification'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _notice(
            Icons.verified_outlined,
            '$status | SCORE ${certification['score'] ?? 0}/100',
            '${certification['passCount'] ?? 0} passed | ${certification['warningCount'] ?? 0} warnings | ${certification['failureCount'] ?? 0} failed',
            summaryColor,
            trailing: certification['generatedAtUtc']?.toString(),
          ),
          const SizedBox(height: 8),
          ...checks.map((check) {
            final checkStatus =
                check['status']?.toString().toUpperCase() ?? 'FAIL';
            final color = checkStatus == 'PASS'
                ? const Color(0xFF8CFFB2)
                : checkStatus == 'WARN'
                ? AppColors.gold
                : const Color(0xFFFF7B7B);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                checkStatus == 'PASS'
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                '$checkStatus | ${check['label'] ?? 'Data check'}',
                check['detail']?.toString() ?? '',
                color,
                trailing: check['value']?.toString(),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _billingCertification() {
    final certification = _billing?.isNotEmpty == true
        ? _billing!
        : _map('billingCertification');
    final checks = (certification['checks'] as List? ?? const [])
        .whereType<Map>()
        .toList(growable: false);
    final status = certification['status']?.toString().toUpperCase() ?? 'FAIL';
    final color = status == 'PASS'
        ? const Color(0xFF8CFFB2)
        : status == 'WARN'
        ? AppColors.gold
        : const Color(0xFFFF7B7B);
    if (checks.isEmpty) {
      return _notice(
        Icons.credit_card_off_outlined,
        'BILLING CERTIFICATION UNAVAILABLE',
        'The subscription release gate did not return any checks.',
        color,
      );
    }
    return KeyedSubtree(
      key: const ValueKey('billing-release-certification'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _notice(
            Icons.verified_user_outlined,
            '$status | ${certification['releaseReady'] == true ? 'READY TO SELL' : 'DO NOT RELEASE'}',
            '${certification['passCount'] ?? 0} passed | ${certification['warningCount'] ?? 0} warnings | ${certification['failureCount'] ?? 0} failed',
            color,
            trailing: certification['generatedAtUtc']?.toString(),
          ),
          const SizedBox(height: 8),
          ...checks.map((check) {
            final checkStatus =
                check['status']?.toString().toUpperCase() ?? 'FAIL';
            final checkColor = checkStatus == 'PASS'
                ? const Color(0xFF8CFFB2)
                : checkStatus == 'WARN'
                ? AppColors.gold
                : const Color(0xFFFF7B7B);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                checkStatus == 'PASS'
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                '$checkStatus | ${check['label'] ?? 'Billing check'}',
                check['detail']?.toString() ?? '',
                checkColor,
                trailing: check['value']?.toString(),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _productObservability() {
    final ownerInsights = _control?['ownerOnlyInsights'] as Map? ?? const {};
    final telemetry = ownerInsights['productObservability'] as Map? ?? const {};
    if (telemetry['available'] != true) {
      return _notice(
        Icons.monitor_heart_outlined,
        'Product telemetry is warming up',
        telemetry['reason']?.toString() ??
            'Release events will appear after authenticated customers use the updated app.',
        AppColors.gold,
      );
    }
    final reliability = telemetry['reliability'] as Map? ?? const {};
    final funnels = telemetry['funnels'] as Map? ?? const {};
    final errors = telemetry['errors'] as Map? ?? const {};
    final errorFree = (reliability['errorFreeUserRate'] as num?)?.toDouble();
    final slos = telemetry['slos'] as Map? ?? const {};
    String percent(Object? value) =>
        value is num ? '${(value * 100).toStringAsFixed(2)}%' : '--';
    bool targetMet(String key, {bool lowerIsBetter = false}) {
      final row = slos[key] as Map? ?? const {};
      final actual = row['actual'] as num?;
      final target = row['target'] as num?;
      if (actual == null || target == null) return true;
      return lowerIsBetter ? actual <= target : actual >= target;
    }

    final errorRows = errors.entries.toList()
      ..sort(
        (a, b) => ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0),
      );

    Widget funnelCard(String label, Object? value) {
      final stages = (value as List? ?? const []).whereType<Map>().toList(
        growable: false,
      );
      final detail = stages
          .map((stage) {
            final conversion = (stage['conversionFromPrevious'] as num?)
                ?.toDouble();
            final suffix = conversion == null
                ? ''
                : ' (${(conversion * 100).toStringAsFixed(1)}% from prior)';
            return '${stage['label']}: ${stage['uniqueUsers'] ?? 0} users$suffix';
          })
          .join('  |  ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _notice(
          Icons.filter_alt_outlined,
          '$label FUNNEL',
          detail.isEmpty ? 'No release events observed yet.' : detail,
          AppColors.gold,
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('product-observability-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _status(
                'Error-free users',
                errorFree == null
                    ? '--'
                    : '${(errorFree * 100).toStringAsFixed(1)}%',
                errorFree == null || errorFree >= .98,
                detail: '${reliability['errorUsers'] ?? 0} affected users',
              ),
              _status(
                'Slow-load users',
                '${reliability['slowLoadUsers'] ?? 0}',
                (reliability['slowLoadUsers'] as num? ?? 0) == 0,
                detail: 'Board loads over five seconds',
              ),
              _status(
                'Checkout failures',
                '${reliability['checkoutFailures'] ?? 0}',
                (reliability['checkoutFailures'] as num? ?? 0) == 0,
                detail: 'Canceled or unavailable checkout attempts',
              ),
              _status(
                'API availability',
                percent(reliability['apiAvailability']),
                targetMet('apiAvailability'),
                detail: 'SLO 99.9%',
              ),
              _status(
                'Prop-board loads',
                percent(reliability['propLoadSuccessRate']),
                targetMet('propBoardLoads'),
                detail: 'SLO 99%',
              ),
              _status(
                'Cached content p95',
                reliability['cachedContentP95Ms'] == null
                    ? '--'
                    : '${reliability['cachedContentP95Ms']} ms',
                targetMet('cachedContentMs', lowerIsBetter: true),
                detail: 'Target under 2 seconds',
              ),
              _status(
                'Live results p95',
                reliability['liveResultsP95Ms'] == null
                    ? '--'
                    : '${reliability['liveResultsP95Ms']} ms',
                targetMet('liveResultsMs', lowerIsBetter: true),
                detail: 'Target under 5 seconds',
              ),
            ],
          ),
          const SizedBox(height: 10),
          funnelCard('RESEARCH', funnels['research']),
          funnelCard('SUBSCRIPTION', funnels['subscription']),
          if (errorRows.isNotEmpty)
            _notice(
              Icons.bug_report_outlined,
              'TOP ERROR FINGERPRINTS',
              errorRows
                  .take(5)
                  .map((entry) => '${entry.key}: ${entry.value}')
                  .join('  |  '),
              const Color(0xFFFF7B7B),
            ),
        ],
      ),
    );
  }

  Widget _feedbackInbox() {
    final ownerInsights = _control?['ownerOnlyInsights'] as Map? ?? const {};
    final inbox = ownerInsights['feedbackInbox'] as Map? ?? const {};
    final summary = inbox['summary'] as Map? ?? const {};
    final items = (inbox['items'] as List? ?? const []).whereType<Map>().toList(
      growable: false,
    );
    if (inbox['available'] != true) {
      return _notice(
        Icons.inbox_outlined,
        'Feedback inbox unavailable',
        inbox['reason']?.toString() ??
            'Feedback storage is not configured yet.',
        brand_colors.AppColors.goldHighlight,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _notice(
          Icons.mark_email_read_outlined,
          'NEW ${summary['new'] ?? 0} | 24H ${summary['last24Hours'] ?? 0} | 7D ${summary['last7Days'] ?? 0}',
          'Total submissions ${summary['total'] ?? 0}',
          const Color(0xFF8CFFB2),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          _notice(
            Icons.chat_bubble_outline,
            'No feedback yet',
            'Once users submit issues or recommendations, they appear here.',
            AppColors.gold,
          )
        else
          ...items
              .take(8)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _notice(
                    Icons.feedback_outlined,
                    '${item['category'] ?? 'feedback'} | ${item['page'] ?? '--'}',
                    '${item['message'] ?? ''}',
                    AppColors.gold,
                    trailing: item['createdAt']?.toString() ?? '',
                  ),
                ),
              ),
      ],
    );
  }

  Widget _header() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OWNER COMMAND CENTER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Live platform health, model activity, accounts, and production controls',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        FilledButton.icon(
          key: const ValueKey('owner-operations-refresh'),
          onPressed: _loading ? null : () => unawaited(_refresh()),
          icon: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(_loading ? 'RUNNING CHECKS' : 'RUN ALL CHECKS'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: const Color(0xFF07121C),
          ),
        ),
        if (_lastChecked != null)
          Text(
            'Last checked ${TimeOfDay.fromDateTime(_lastChecked!).format(context)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
      ],
    );
  }

  Widget _timeFilter() {
    const windows = <String, String>{
      'live': 'LIVE',
      'today': 'TODAY',
      'yesterday': 'YESTERDAY',
      '7d': '7 DAYS',
      '30d': '30 DAYS',
      'custom': 'CUSTOM',
    };
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: windows.entries
          .map((entry) {
            final selected = _selectedWindow == entry.key;
            return ChoiceChip(
              key: ValueKey('owner-window-${entry.key}'),
              selected: selected,
              onSelected: (_) => unawaited(_selectWindow(entry.key)),
              label: Text(entry.value),
              selectedColor: AppColors.gold,
              backgroundColor: const Color(0xFF0C1823),
              side: BorderSide(color: AppColors.gold.withValues(alpha: .5)),
              labelStyle: TextStyle(
                color: selected ? const Color(0xFF07121C) : AppColors.gold,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.gold,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
      ),
    ],
  );

  Widget _statusGrid() {
    final api = _map('api');
    final redis = _map('redis');
    final workers = _map('workers');
    final providers = _map('providers');
    final freshness = _map('propFreshness');
    final scoreboard = _map('scoreboardLatency');
    final users = _map('activeUsers');
    final signups = _map('newSignups');
    final payments = _map('failedPayments');
    final slips = _map('unsettledSlips');
    final review = _map('gradingReview');
    final syncDiagnostics = _map('syncDiagnostics');
    final syncCategories = (syncDiagnostics['categories'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .map((item) => '${item['category']}: ${item['count']}')
        .join(' | ');
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _status('API', api['status'] ?? 'Loading', api['status'] == 'ok'),
        _status(
          'Redis',
          redis['available'] == true ? 'Connected' : 'Unavailable',
          redis['available'] == true,
        ),
        _status(
          'Workers',
          '${workers['workers'] ?? 0} online',
          workers['available'] == true,
          detail:
              '${workers['queued'] ?? 0} queued | ${workers['failed'] ?? 0} failed',
        ),
        _status(
          'Provider quality',
          '${providers['qualityScore'] ?? '--'}',
          (providers['qualityScore'] as num? ?? 0) >= .7,
          detail:
              '${providers['errors'] ?? 0} errors | ${providers['remainingQuota'] ?? '--'} quota',
        ),
        _status(
          'Prop freshness',
          '${freshness['ageMinutes'] ?? '--'} min',
          freshness['healthy'] == true,
          detail: '${freshness['total'] ?? 0} props',
        ),
        _status(
          'Scoreboard',
          '${scoreboard['lastMs'] ?? '--'} ms',
          scoreboard['status'] == 'ok',
          detail: 'p95 ${scoreboard['p95Ms'] ?? '--'} ms',
        ),
        _status(
          'Active users',
          '${users['count'] ?? '--'}',
          users['instrumented'] == true,
          metric: 'activeUsers',
        ),
        _status(
          'New signups',
          '${signups['count'] ?? '--'}',
          signups['instrumented'] == true,
          detail:
              '24h • 7d ${signups['last7Days'] ?? '--'} • total ${signups['total'] ?? '--'}',
          metric: 'newSignups',
        ),
        _status(
          'Failed payments',
          '${payments['count'] ?? '--'}',
          (payments['count'] ?? 0) == 0,
          metric: 'failedPayments',
        ),
        _status(
          'Unsettled slips',
          '${slips['count'] ?? '--'}',
          true,
          metric: 'unsettledSlips',
        ),
        _status(
          'Questionable grades',
          '${review['questionableCount'] ?? '--'}',
          (review['questionableCount'] ?? 0) == 0,
        ),
        _status(
          'Ticket sync reports',
          '${syncDiagnostics['last24Hours'] ?? 0} today',
          (syncDiagnostics['last24Hours'] ?? 0) == 0,
          detail: syncCategories.isEmpty
              ? 'No reports in 7 days'
              : syncCategories,
        ),
        _status('Deployment', _shortVersion(api['version']), true),
      ],
    );
  }

  Widget _modelAccountability() {
    final performance = _map('modelPerformance');
    final operations = _map('predictionOperations');
    final clv = performance['clv'] as Map? ?? const {};
    final sample = (performance['sampleSize'] as num?)?.toInt() ?? 0;
    final accuracy = (performance['accuracy'] as num?)?.toDouble();
    final brier = (performance['brierScore'] as num?)?.toDouble();
    final calibrated = performance['calibrated'] == true;
    final beatClose = (clv['beatClosingLineRate'] as num?)?.toDouble();
    final oddsClv = (clv['averageOddsClvExpectedValuePercent'] as num?)
        ?.toDouble();
    final positiveOddsClv = (clv['positiveOddsClvRate'] as num?)?.toDouble();
    final segments = (performance['qualitySegments'] as List? ?? const [])
        .whereType<Map>()
        .take(6)
        .toList(growable: false);
    final sideSegments = (performance['sideSegments'] as List? ?? const [])
        .whereType<Map>()
        .take(8)
        .toList(growable: false);
    final audit = performance['auditSummary'] as Map? ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _status(
              'Graded sample',
              '$sample / ${performance['minimumCalibrationSample'] ?? 100}',
              calibrated,
              detail: calibrated ? 'Calibration active' : 'Still warming',
            ),
            _status(
              'Accuracy',
              accuracy == null
                  ? '--'
                  : '${(accuracy * 100).toStringAsFixed(1)}%',
              sample > 0,
              detail: 'Out-of-sample only',
            ),
            _status(
              'Brier score',
              brier?.toStringAsFixed(3) ?? '--',
              brier != null,
              detail: 'Lower is better',
            ),
            _status(
              'Beat closing line',
              beatClose == null
                  ? '--'
                  : '${(beatClose * 100).toStringAsFixed(1)}%',
              beatClose != null && beatClose >= .5,
              detail: '${clv['sampleSize'] ?? 0} captured closes',
            ),
            _status(
              'Vig-free odds CLV',
              oddsClv == null ? '--' : '${oddsClv.toStringAsFixed(2)}%',
              oddsClv != null && oddsClv > 0,
              detail: positiveOddsClv == null
                  ? '${clv['oddsSampleSize'] ?? 0} paired closes'
                  : '${(positiveOddsClv * 100).toStringAsFixed(1)}% positive • ${clv['oddsSampleSize'] ?? 0} paired closes',
            ),
            _status(
              'Snapshots today',
              '${operations['snapshotsToday'] ?? 0}',
              operations['databaseConfigured'] == true,
              detail: '${operations['pendingPredictions'] ?? 0} pending grades',
            ),
          ],
        ),
        if (segments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'TOP VERIFIED SEGMENTS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...segments.map((segment) {
            final segmentAccuracy = (segment['accuracy'] as num?)?.toDouble();
            final averageConfidence = (segment['averageConfidence'] as num?)
                ?.toDouble();
            final calibrationGap = (segment['calibrationGap'] as num?)
                ?.toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _notice(
                Icons.analytics_outlined,
                '${segment['sport'] ?? '--'} | ${segment['category'] ?? '--'} | ${segment['provider'] ?? '--'}',
                '${segment['sampleSize'] ?? 0} picks | '
                    'accuracy ${segmentAccuracy == null ? '--' : '${(segmentAccuracy * 100).toStringAsFixed(1)}%'} | '
                    'confidence ${averageConfidence == null ? '--' : '${(averageConfidence * 100).toStringAsFixed(1)}%'} | '
                    'gap ${calibrationGap == null ? '--' : '${(calibrationGap * 100).toStringAsFixed(1)} pts'}',
                AppColors.gold,
              ),
            );
          }),
        ],
        if (sideSegments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'OVER / UNDER AUDIT',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${audit['healthy'] ?? 0} healthy  |  ${audit['monitor'] ?? 0} monitor  |  ${audit['recalibrate'] ?? 0} recalibrate  |  ${audit['collecting'] ?? 0} collecting',
            style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
          ),
          const SizedBox(height: 7),
          ...sideSegments.map((segment) {
            final status = '${segment['status'] ?? 'COLLECTING'}';
            final segmentAccuracy = (segment['accuracy'] as num?)?.toDouble();
            final gap = (segment['calibrationGap'] as num?)?.toDouble();
            final healthy = status == 'HEALTHY';
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _notice(
                healthy ? Icons.verified_outlined : Icons.rule_outlined,
                '${segment['sport'] ?? '--'} | ${segment['side'] ?? '--'} | ${segment['confidenceTier'] ?? '--'} | $status',
                '${segment['sampleSize'] ?? 0} picks | accuracy ${segmentAccuracy == null ? '--' : '${(segmentAccuracy * 100).toStringAsFixed(1)}%'} | gap ${gap == null ? '--' : '${(gap * 100).toStringAsFixed(1)} pts'} | ${segment['reason'] ?? ''}',
                healthy ? const Color(0xFF8CFFB2) : AppColors.gold,
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _piAdaptiveLearning() {
    final ownerInsights = _control?['ownerOnlyInsights'] as Map? ?? const {};
    final learning = ownerInsights['piAdaptiveLearning'] as Map? ?? const {};
    final summary = learning['summary'] as Map? ?? const {};
    final findings = (learning['findings'] as List? ?? const [])
        .whereType<Map>()
        .take(10)
        .toList(growable: false);
    if (learning['available'] != true) {
      return _notice(
        Icons.psychology_alt_outlined,
        'PI learning report is warming up',
        learning['reason']?.toString() ??
            'Settled prediction data is not available yet.',
        AppColors.gold,
      );
    }
    final promoted = (summary['promoted'] as num?)?.toInt() ?? 0;
    final developing = (summary['developing'] as num?)?.toInt() ?? 0;
    final rejected = (summary['rejected'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _notice(
          Icons.auto_graph_rounded,
          'PI learning is active',
          '${learning['settledPredictions'] ?? 0} settled predictions | $promoted promoted | $developing developing | $rejected rejected',
          const Color(0xFF8CFFB2),
        ),
        const SizedBox(height: 8),
        ...findings.map((finding) {
          final status = finding['status']?.toString() ?? 'DEVELOPING';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _notice(
              status == 'PROMOTED'
                  ? Icons.verified_outlined
                  : status == 'REJECTED'
                  ? Icons.block_outlined
                  : Icons.hourglass_top_rounded,
              '$status | ${finding['sport'] ?? ''} ${finding['market'] ?? ''}',
              finding['explanation']?.toString() ??
                  'Pattern details unavailable.',
              status == 'PROMOTED'
                  ? const Color(0xFF8CFFB2)
                  : status == 'REJECTED'
                  ? const Color(0xFFFF7B7B)
                  : AppColors.gold,
            ),
          );
        }),
      ],
    );
  }

  Widget _strikeoutIntelligence() {
    final ownerInsights = _control?['ownerOnlyInsights'] as Map? ?? const {};
    final strikeout =
        ownerInsights['strikeoutIntelligence'] as Map? ?? const {};
    final inputCoverage =
        ownerInsights['strikeoutInputCoverage'] as Map? ?? const {};
    final methodAudit =
        ownerInsights['strikeoutMethodAudit'] as Map? ?? const {};
    final releaseControls =
        ownerInsights['strikeoutReleaseControls'] as Map? ?? const {};
    final calibration =
        ownerInsights['strikeoutCalibration'] as Map? ?? const {};
    final backtest = ownerInsights['strikeoutBacktest'] as Map? ?? const {};
    final methodComparison =
        ownerInsights['strikeoutMethodComparison'] as Map? ?? const {};
    final explainability =
        ownerInsights['strikeoutExplainability'] as Map? ?? const {};
    final available = strikeout['available'] == true;
    if (!available) {
      return _notice(
        Icons.analytics_outlined,
        'Strikeout Report Not Ready',
        strikeout['reason']?.toString() ??
            'No graded MLB strikeout predictions are available yet.',
        AppColors.gold,
      );
    }

    String pct(Object? value) {
      final numeric = (value as num?)?.toDouble();
      return numeric == null ? '--' : '${(numeric * 100).toStringAsFixed(1)}%';
    }

    String numVal(Object? value, {int decimals = 2}) {
      final numeric = (value as num?)?.toDouble();
      return numeric == null ? '--' : numeric.toStringAsFixed(decimals);
    }

    final over = strikeout['over'] as Map? ?? const {};
    final under = strikeout['under'] as Map? ?? const {};
    final methods = (methodAudit['methods'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .toList(growable: false);
    final variants = (methodComparison['variants'] as List? ?? const [])
        .whereType<Map>()
        .take(2)
        .toList(growable: false);
    final explainItems = (explainability['items'] as List? ?? const [])
        .whereType<Map>()
        .take(4)
        .toList(growable: false);
    final backtestAlerts = (backtest['alerts'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .toList(growable: false);
    final calibrationAdjustments =
        (calibration['adjustments'] as List? ?? const [])
            .whereType<Map>()
            .take(4)
            .toList(growable: false);
    final health = (strikeout['health']?.toString() ?? 'COLLECTING')
        .toUpperCase();
    final healthy = health == 'HEALTHY';
    final controlsLoaded = releaseControls['controls'] is Map;
    if (_strikeoutControlsDraft.isEmpty && controlsLoaded) {
      _strikeoutControlsDraft = Map<String, dynamic>.from(
        (releaseControls['controls'] as Map).map(
          (key, value) => MapEntry('$key', value),
        ),
      );
    }
    final controlSource = releaseControls['source']?.toString() ?? 'defaults';
    final calibrationHealthy = calibration['healthy'] == true;
    final driftHealthy = backtest['healthy'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OWNER CONTROLS',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        _notice(
          Icons.tune,
          'Runtime Gate Controls',
          'Source: $controlSource | Toggle release rules without deploying new code.',
          AppColors.gold,
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1823),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gold.withValues(alpha: .2)),
          ),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _boolControl('enabled', true),
                onChanged: (value) =>
                    setState(() => _strikeoutControlsDraft['enabled'] = value),
                title: const Text(
                  'Gate enabled',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                subtitle: const Text(
                  'Blocks weak-data strikeout suggestive picks before release',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _boolControl('requireConfirmedLineup', true),
                onChanged: (value) => setState(
                  () =>
                      _strikeoutControlsDraft['requireConfirmedLineup'] = value,
                ),
                title: const Text(
                  'Require confirmed lineup',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _boolControl('requireTemperature', true),
                onChanged: (value) => setState(
                  () => _strikeoutControlsDraft['requireTemperature'] = value,
                ),
                title: const Text(
                  'Require weather temperature',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _boolControl('requireUmpireBoost', true),
                onChanged: (value) => setState(
                  () => _strikeoutControlsDraft['requireUmpireBoost'] = value,
                ),
                title: const Text(
                  'Require umpire signal',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Max lineup age: ${_intControl('maxLineupAgeMinutes', 240)} min',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                subtitle: Slider(
                  value: _intControl('maxLineupAgeMinutes', 240).toDouble(),
                  min: 30,
                  max: 720,
                  divisions: 23,
                  label: '${_intControl('maxLineupAgeMinutes', 240)}',
                  onChanged: (value) => setState(
                    () => _strikeoutControlsDraft['maxLineupAgeMinutes'] = value
                        .round(),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Min opposing lineup size: ${_intControl('minOpposingLineupSize', 8)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                subtitle: Slider(
                  value: _intControl('minOpposingLineupSize', 8).toDouble(),
                  min: 5,
                  max: 9,
                  divisions: 4,
                  label: '${_intControl('minOpposingLineupSize', 8)}',
                  onChanged: (value) => setState(
                    () => _strikeoutControlsDraft['minOpposingLineupSize'] =
                        value.round(),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Max fallback signals: ${_intControl('maxFallbackSignals', 0)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                subtitle: Slider(
                  value: _intControl('maxFallbackSignals', 0).toDouble(),
                  min: 0,
                  max: 3,
                  divisions: 3,
                  label: '${_intControl('maxFallbackSignals', 0)}',
                  onChanged: (value) => setState(
                    () => _strikeoutControlsDraft['maxFallbackSignals'] = value
                        .round(),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _savingStrikeoutControls
                      ? null
                      : _saveStrikeoutControls,
                  icon: _savingStrikeoutControls
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(
                    _savingStrikeoutControls
                        ? 'Saving...'
                        : 'Save strikeout controls',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: const Color(0xFF07121C),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _status(
              'Report health',
              health,
              healthy,
              detail: 'Visibility: owner only',
            ),
            _status(
              'Graded strikeout sample',
              '${strikeout['sampleSize'] ?? 0}',
              ((strikeout['sampleSize'] as num?)?.toInt() ?? 0) >= 40,
              detail:
                  'Suggestive picks tier: ${strikeout['suggestivePickTier'] ?? 'pro_gold'}',
            ),
            _status(
              'Strikeout accuracy',
              pct(strikeout['accuracy']),
              ((strikeout['accuracy'] as num?)?.toDouble() ?? 0) >= 0.5,
              detail: 'All MLB strikeout sides',
            ),
            _status(
              'Strikeout ROI',
              '${numVal(strikeout['simulatedRoi'])}%',
              ((strikeout['simulatedRoi'] as num?)?.toDouble() ?? 0) > 0,
              detail: 'Simulated average return',
            ),
            _status(
              'Beat closing line',
              pct(strikeout['beatClosingLineRate']),
              ((strikeout['beatClosingLineRate'] as num?)?.toDouble() ?? 0) >=
                  0.5,
              detail: '${strikeout['oddsSampleSize'] ?? 0} odds pairs',
            ),
            _status(
              'Positive odds CLV',
              pct(strikeout['positiveOddsClvRate']),
              ((strikeout['positiveOddsClvRate'] as num?)?.toDouble() ?? 0) >=
                  0.5,
              detail:
                  '${numVal(strikeout['averageOddsClvExpectedValuePercent'])}% avg',
            ),
            _status(
              'Calibration',
              calibrationHealthy ? 'HEALTHY' : 'MONITOR',
              calibrationHealthy,
              detail:
                  'Gap ${pct(calibration['overallGap'])} | ${calibration['sampleSize'] ?? 0} samples',
            ),
            _status(
              'Backtest drift',
              driftHealthy ? 'HEALTHY' : 'ALERT',
              driftHealthy,
              detail: '${backtestAlerts.length} active alerts',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _notice(
          Icons.security_outlined,
          'Owner-Only Visibility Guard',
          'Strikeout suggestive picks are shown only to Pro Gold users. Owner Operations exposes full validation telemetry for oversight.',
          AppColors.gold,
        ),
        const SizedBox(height: 10),
        if (inputCoverage['available'] == true)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _status(
                'Live strikeout props',
                '${inputCoverage['total'] ?? 0}',
                (inputCoverage['total'] as num? ?? 0) > 0,
                detail: 'Current cached MLB strikeout rows',
              ),
              _status(
                'Full-model coverage',
                pct(inputCoverage['fullModelCoverage']),
                ((inputCoverage['fullModelCoverage'] as num?)?.toDouble() ??
                        0) >=
                    .6,
                detail: 'Real matchup rate plus TBF inputs present',
              ),
              _status(
                'Fallback rate',
                pct(inputCoverage['fallbackRate']),
                ((inputCoverage['fallbackRate'] as num?)?.toDouble() ?? 1) <=
                    .4,
                detail: 'Live props still leaning on defaults',
              ),
              _status(
                'CSW coverage',
                pct(inputCoverage['pitcherCswCoverage']),
                ((inputCoverage['pitcherCswCoverage'] as num?)?.toDouble() ??
                        0) >=
                    .5,
                detail: 'Pitcher CSW present in cache',
              ),
              _status(
                'Lineup handedness',
                pct(inputCoverage['lineupKCoverage']),
                ((inputCoverage['lineupKCoverage'] as num?)?.toDouble() ?? 0) >=
                    .5,
                detail: 'Lineup K% vs handedness present',
              ),
              _status(
                'Environment coverage',
                pct(inputCoverage['environmentCoverage']),
                ((inputCoverage['environmentCoverage'] as num?)?.toDouble() ??
                        0) >=
                    .5,
                detail: 'Temp, umpire, and park loaded',
              ),
            ],
          )
        else
          _notice(
            Icons.storage_outlined,
            'Strikeout Input Coverage Unavailable',
            inputCoverage['reason']?.toString() ??
                'Live strikeout input coverage is not available yet.',
            AppColors.gold,
          ),
        const SizedBox(height: 10),
        _notice(
          Icons.trending_up,
          'OVER Side',
          '${over['sampleSize'] ?? 0} picks | accuracy ${pct(over['accuracy'])} | ROI ${numVal(over['simulatedRoi'])}% | beat close ${pct(over['beatClosingLineRate'])}',
          const Color(0xFF8CFFB2),
        ),
        const SizedBox(height: 8),
        _notice(
          Icons.trending_down,
          'UNDER Side',
          '${under['sampleSize'] ?? 0} picks | accuracy ${pct(under['accuracy'])} | ROI ${numVal(under['simulatedRoi'])}% | beat close ${pct(under['beatClosingLineRate'])}',
          AppColors.gold,
        ),
        if (methods.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'GRADED METHOD AUDIT',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...methods.map(
            (method) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                Icons.science_outlined,
                '${method['method'] ?? 'unknown'} | ${method['sampleSize'] ?? 0} graded',
                'accuracy ${pct(method['accuracy'])} | fallback pitcher ${pct(method['fallbackPitcherRate'])} | fallback lineup ${pct(method['fallbackLineupRate'])} | fallback TBF ${pct(method['fallbackTbfRate'])} | market blend ${pct(method['marketBlendRate'])}',
                AppColors.gold,
              ),
            ),
          ),
        ],
        if (variants.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'METHOD A/B',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...variants.map(
            (variant) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                Icons.compare_arrows,
                '${variant['variant'] ?? 'variant'} | ${variant['sampleSize'] ?? 0} graded',
                'accuracy ${pct(variant['accuracy'])} | predicted ${pct(variant['predicted'])} | brier ${numVal(variant['brier'], decimals: 3)} | ROI ${numVal(variant['simulatedRoi'])}',
                AppColors.gold,
              ),
            ),
          ),
        ],
        if (calibrationAdjustments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'CALIBRATION ADJUSTMENTS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...calibrationAdjustments.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                Icons.straighten,
                '${row['side'] ?? '--'} ${row['bucket'] ?? '--'} | ${row['sampleSize'] ?? 0} picks',
                'predicted ${pct(row['predicted'])} | actual ${pct(row['actual'])} | gap ${pct(row['gap'])} | adjust ${pct(row['recommendedAdjustment'])}',
                AppColors.gold,
              ),
            ),
          ),
        ],
        if (backtestAlerts.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'DRIFT ALERTS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...backtestAlerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                Icons.warning_amber_rounded,
                '${alert['severity'] ?? 'warning'} | ${alert['sportsbook'] ?? '--'} | ${alert['lineRange'] ?? '--'} | ${alert['handedness'] ?? '--'}',
                '${alert['message'] ?? ''} | sample ${alert['sampleSize'] ?? 0}',
                const Color(0xFFFF7B7B),
              ),
            ),
          ),
        ],
        if (explainItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'EXPLAINABILITY',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          ...explainItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _notice(
                Icons.psychology_outlined,
                '${item['player'] ?? '--'} | ${item['side'] ?? '--'} ${item['line'] ?? '--'}',
                '${item['summary'] ?? ''}',
                AppColors.gold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _shortVersion(Object? value) {
    final text = value?.toString() ?? 'Unknown';
    return text.length > 10 ? text.substring(0, 10) : text;
  }

  Widget _status(
    String label,
    String value,
    bool healthy, {
    String? detail,
    String? metric,
  }) {
    final color = healthy
        ? AppColors.success
        : brand_colors.AppColors.goldHighlight;
    final tile = Container(
      width: 205,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1823),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
            ),
          ],
          if (metric != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.list_alt_rounded,
                  size: 11,
                  color: AppColors.gold.withValues(alpha: .8),
                ),
                const SizedBox(width: 4),
                Text(
                  'TAP TO VIEW',
                  style: TextStyle(
                    color: AppColors.gold.withValues(alpha: .8),
                    fontSize: 8,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (metric == null) return tile;
    return InkWell(
      onTap: () => _openDetail(metric, label),
      borderRadius: BorderRadius.circular(10),
      child: tile,
    );
  }

  Widget _reviewCard(Map item) {
    final reasons = (item['reasons'] as List? ?? const [])
        .map((reason) => reason.toString().replaceAll('_', ' '))
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _notice(
        Icons.fact_check_outlined,
        '${item['player'] ?? 'Unknown player'} | ${item['market'] ?? 'Unknown market'}',
        '${item['side'] ?? ''} ${item['line'] ?? ''} | ${item['sport'] ?? ''} | $reasons',
        brand_colors.AppColors.goldHighlight,
        trailing: 'Slip ${item['slipId'] ?? '--'}',
      ),
    );
  }

  Widget _pipelineCard(Map item) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _notice(
      Icons.warning_amber_rounded,
      item['pipeline']?.toString() ??
          item['name']?.toString() ??
          'Pipeline issue',
      (item['errors'] as List? ?? [item['status'] ?? 'Review required']).join(
        ' | ',
      ),
      const Color(0xFFFF7B7B),
    ),
  );

  Widget _notice(
    IconData icon,
    String title,
    String detail,
    Color color, {
    String? trailing,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
      ],
    ),
  );

  Widget _ownerViewSelector() {
    const views = <({String label, String metric, IconData icon})>[
      (label: 'USERS', metric: 'activeUsers', icon: Icons.people_alt_outlined),
      (label: 'SIGNUPS', metric: 'newSignups', icon: Icons.person_add_alt_1),
      (
        label: 'PAYMENTS',
        metric: 'failedPayments',
        icon: Icons.payments_outlined,
      ),
      (
        label: 'SLIPS',
        metric: 'unsettledSlips',
        icon: Icons.receipt_long_outlined,
      ),
      (label: 'PROVIDERS', metric: 'providers', icon: Icons.hub_outlined),
      (
        label: 'INVENTORY',
        metric: 'propFreshness',
        icon: Icons.inventory_2_outlined,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: views
            .map(
              (view) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  key: ValueKey('owner-view-${view.metric}'),
                  onPressed: () => _openDetail(view.metric, view.label),
                  icon: Icon(view.icon, size: 15),
                  label: Text(view.label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    minimumSize: const Size(118, 44),
                    side: BorderSide(
                      color: AppColors.gold.withValues(alpha: .55),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

/// The rows behind one operations tile.
///
/// Rendered from the columns the backend declares rather than a fixed layout,
/// so a new tile detail needs no matching change here.
class _OwnerTopPicksLoading extends StatelessWidget {
  const _OwnerTopPicksLoading();

  @override
  Widget build(BuildContext context) => Container(
    height: 112,
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.gunmetalLight),
    ),
    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
  );
}

class _OwnerSportPickGroup extends StatelessWidget {
  const _OwnerSportPickGroup({required this.sport, required this.picks});

  final String sport;
  final List<PropData> picks;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF0C1823),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.gunmetalLight),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.gold,
              size: 16,
            ),
            const SizedBox(width: 7),
            Text(
              '$sport  |  TOP ${picks.length}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        for (var index = 0; index < picks.length; index++)
          _OwnerPickRow(rank: index + 1, prop: picks[index]),
      ],
    ),
  );
}

class _OwnerPickRow extends StatelessWidget {
  const _OwnerPickRow({required this.rank, required this.prop});

  final int rank;
  final PropData prop;

  @override
  Widget build(BuildContext context) {
    final side = ownerResearchSide(prop);
    final market = prop.displayMarket.isEmpty
        ? prop.market
        : prop.displayMarket;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gunmetalLight),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.gold,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: AppColors.background,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prop.player,
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
                  '${prop.sport}  |  $market  |  ${prop.matchup}  |  ${prop.sportsbook}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.silver, fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$side ${prop.line.toStringAsFixed(1)}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'TRUST ${prop.piTrustScore}  |  EDGE ${prop.edge.toStringAsFixed(1)}',
                style: const TextStyle(color: AppColors.silver, fontSize: 8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.title, required this.future});

  final String title;
  final Future<Map<String, dynamic>> future;

  String _label(String column) {
    final spaced = column.replaceAllMapped(
      RegExp(r'(?<=[a-z])(?=[A-Z])'),
      (_) => ' ',
    );
    return spaced.toUpperCase();
  }

  String _value(Object? raw) {
    if (raw == null) return '--';
    final text = raw.toString();
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      final local = parsed.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '${local.month}/${local.day} $hh:$mm';
    }
    return text;
  }

  Future<void> _email(BuildContext context, String email) async {
    final opened = await launchUrl(
      Uri(scheme: 'mailto', path: email),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email application is available.')),
      );
    }
  }

  Future<void> _chat(BuildContext context, Map row) async {
    final userId = '${row['userId'] ?? ''}'.trim();
    if (userId.isEmpty || userId.length < 20) return;
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0C1823),
        title: Text(
          'PRIVATE MESSAGE TO ${row['username'] ?? row['name'] ?? row['email']}',
          style: const TextStyle(color: AppColors.gold, fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('SEND'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.trim().isEmpty) return;
    try {
      final service = PropChatService();
      final conversationId = await service.startDirectConversation(userId);
      await service.sendDirectMessage(conversationId, message.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Private message sent.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to send message: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .92,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            final header = Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: brand_colors.AppColors.goldHighlight,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            );

            if (snapshot.connectionState != ConnectionState.done) {
              return Column(
                children: [
                  header,
                  const SizedBox(height: 40),
                  const CircularProgressIndicator(color: AppColors.gold),
                ],
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final rows = (data['rows'] as List? ?? const [])
                .whereType<Map>()
                .toList();
            final columns = (data['columns'] as List? ?? const [])
                .map((value) => value.toString())
                .toList();

            if (rows.isEmpty) {
              // Say why rather than showing an empty box that could equally
              // mean "none" or "failed".
              final reason = data['reason']?.toString();
              final friendlyReason = switch (reason) {
                'database_not_configured' =>
                  'The production database connection is not configured.',
                'no_detail_for_metric' =>
                  'This metric does not have a drilldown data source yet.',
                null || '' => 'No records were found for this time window.',
                _ => 'The data source is temporarily unavailable ($reason).',
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 24),
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.gold,
                    size: 28,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    friendlyReason,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                if (data['description'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      data['description'].toString(),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: AppColors.border, height: 14),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final email = '${row['email'] ?? ''}'.trim();
                      final userId = '${row['userId'] ?? ''}'.trim();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final column in columns)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 96,
                                    child: Text(
                                      _label(column),
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 9,
                                        letterSpacing: .6,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _value(row[column]),
                                      style: const TextStyle(
                                        color: AppColors.silver,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (email.isNotEmpty || userId.length >= 20)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  if (email.isNotEmpty)
                                    OutlinedButton.icon(
                                      onPressed: () => _email(context, email),
                                      icon: const Icon(
                                        Icons.email_outlined,
                                        size: 15,
                                      ),
                                      label: const Text('EMAIL'),
                                    ),
                                  if (userId.length >= 20)
                                    OutlinedButton.icon(
                                      onPressed: () => _chat(context, row),
                                      icon: const Icon(
                                        Icons.chat_bubble_outline,
                                        size: 15,
                                      ),
                                      label: const Text('PRIVATE CHAT'),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (data['truncated'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Showing the most recent ${rows.length}. '
                      'The tile count is the true total.',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
