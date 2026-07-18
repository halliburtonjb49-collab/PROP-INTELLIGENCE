import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/active_slip_controller.dart';
import '../models/saved_slip.dart';
import '../services/api_service.dart';
import '../services/live_update_service.dart';
import 'context_help.dart';

class SlipHistoryPanel extends StatefulWidget {
  const SlipHistoryPanel({super.key, required this.activeSlipController});

  final ActiveSlipController activeSlipController;

  @override
  State<SlipHistoryPanel> createState() => _SlipHistoryPanelState();
}

class _SlipHistoryPanelState extends State<SlipHistoryPanel> {
  final ApiService _apiService = ApiService();
  final LiveUpdateService _liveUpdates = LiveUpdateService(
    channels: const {'tickets'},
  );
  StreamSubscription<dynamic>? _liveSubscription;
  String _selectedTab = 'all';
  late Future<List<SavedSlip>> _slipsFuture;
  Timer? _refreshTimer;
  bool _isRefreshingGames = false;
  String? _refreshError;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _slipsFuture = _apiService.fetchSlips();
    _liveSubscription = _liveUpdates.stream.listen(
      (_) => _reloadFromTicketEvent(),
      onError: (_) {},
    );
    _liveUpdates.connect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshGameStatuses();
    });
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshGameStatuses(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_liveSubscription?.cancel());
    unawaited(_liveUpdates.dispose());
    super.dispose();
  }

  void _reloadFromTicketEvent() {
    if (!mounted) return;
    setState(() {
      _lastUpdated = DateTime.now();
      _slipsFuture = _apiService.fetchSlips(
        status: _selectedTab == 'all' ? null : _selectedTab,
      );
    });
  }

  void _selectTab(String tab) {
    setState(() {
      _selectedTab = tab;
      _slipsFuture = _apiService.fetchSlips(status: tab == 'all' ? null : tab);
    });
  }

  Future<void> _changeStatus(SavedSlip slip, String status) async {
    await _apiService.updateSlipStatus(slipId: slip.id, status: status);
    if (!mounted) {
      return;
    }
    setState(() {
      _slipsFuture = _apiService.fetchSlips(
        status: _selectedTab == 'all' ? null : _selectedTab,
      );
    });
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
      await _apiService.refreshAllSlipGames();
      // Automatically grade completed WNBA props.
      await _apiService.gradeWnbaSlips();
      final refreshedSlips = await _apiService.fetchSlips(
        status: _selectedTab == 'all' ? null : _selectedTab,
      );
      await _syncActiveSlipFromSavedSlips(refreshedSlips);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastUpdated = DateTime.now();
        _slipsFuture = Future.value(refreshedSlips);
      });
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
            const Text(
              'SAVED SLIPS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _isRefreshingGames ? null : _refreshGameStatuses,
                  icon: _isRefreshingGames
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFF2BC35),
                          ),
                        )
                      : const Icon(Icons.refresh, size: 17),
                  label: Text(_isRefreshingGames ? 'UPDATING' : 'REFRESH'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF2BC35),
                    textStyle: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
        const SizedBox(height: 8),
        Row(
          children: [
            _tab('ALL', 'all'),
            const SizedBox(width: 6),
            _tab('ACTIVE', 'active'),
            const SizedBox(width: 6),
            _tab('WON', 'won'),
            const SizedBox(width: 6),
            _tab('LOST', 'lost'),
          ],
        ),
        const SizedBox(height: 12),
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
                return Column(
                  children: [
                    _TotalsBar(totals: totals),
                    const SizedBox(height: 10),
                    const Expanded(
                      child: Center(child: Text('No slips in this view.')),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _TotalsBar(totals: totals),
                  const SizedBox(height: 8),
                  _ClvSummary(totals: totals),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: slips.length,
                      separatorBuilder: (context, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final slip = slips[index];
                        return _SavedSlipCard(
                          slip: slip,
                          onWon: () => _changeStatus(slip, 'won'),
                          onLost: () => _changeStatus(slip, 'lost'),
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

    for (final slip in slips) {
      for (final leg in slip.legs) {
        if (leg.lineClvPercent != null && leg.beatClosingLine != null) {
          measuredClvLegs += 1;
          clvPercentTotal += leg.lineClvPercent!;
          if (leg.beatClosingLine!) beatCloseLegs += 1;
        }
        switch (leg.resultStatus.toLowerCase()) {
          case 'won':
            wonLegs += 1;
            break;
          case 'lost':
            lostLegs += 1;
            break;
          default:
            pendingLegs += 1;
        }
      }
    }

    return _SlipTotals(
      totalSlips: slips.length,
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

class _SlipTotals {
  const _SlipTotals({
    required this.totalSlips,
    required this.wonLegs,
    required this.lostLegs,
    required this.pendingLegs,
    required this.measuredClvLegs,
    required this.beatCloseLegs,
    required this.averageClvPercent,
  });

  final int totalSlips;
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
            color: positive ? const Color(0xFF25D97D) : const Color(0xFFF2BC35),
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
        pill('WON LEGS', '${totals.wonLegs}', const Color(0xFFF2BC35)),
        const SizedBox(width: 8),
        pill('LOST LEGS', '${totals.lostLegs}', const Color(0xFF63A8FF)),
        const SizedBox(width: 8),
        pill('PENDING', '${totals.pendingLegs}', const Color(0xFFF2BC35)),
      ],
    );
  }
}

class _SavedSlipCard extends StatelessWidget {
  final SavedSlip slip;
  final VoidCallback onWon;
  final VoidCallback onLost;

  const _SavedSlipCard({
    required this.slip,
    required this.onWon,
    required this.onLost,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = slip.status.toLowerCase();
    final isWon = normalizedStatus == 'won';
    final isLost = normalizedStatus == 'lost';
    final borderColor = isWon
        ? const Color(0xFFF2BC35)
        : isLost
        ? const Color(0xFF63A8FF)
        : const Color(0xFF73500B);
    final statusColor = isWon
        ? const Color(0xFFF2BC35)
        : isLost
        ? const Color(0xFF63A8FF)
        : const Color(0xFFF2BC35);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C1824),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        children: [
          if (isWon)
            const Positioned.fill(
              child: IgnorePointer(child: _GoldTicketConfetti()),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${slip.legs.length} LEG SLIP',
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
                        slip.status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...slip.legs.map(
                  (leg) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                leg.player,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${leg.side} ${leg.line} ${leg.market}',
                                style: TextStyle(
                                  color: isLost
                                      ? const Color(0xFF8EC1FF)
                                      : const Color(0xFFF2BC35),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                leg.matchup,
                                style: const TextStyle(
                                  color: Color(0xFF8996A6),
                                  fontSize: 9,
                                ),
                              ),
                              if (leg.resultValue != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  'Final result: ${leg.resultValue}',
                                  style: const TextStyle(
                                    color: Color(0xFF8B98A8),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 3),
                              if (leg.closingLine == null)
                                const Text(
                                  'CLV: pending closing line',
                                  style: TextStyle(
                                    color: Color(0xFF8B98A8),
                                    fontSize: 9,
                                  ),
                                )
                              else
                                Text(
                                  'Entry ${leg.entryLine.toStringAsFixed(1)} → Close ${leg.closingLine!.toStringAsFixed(1)}  •  ${leg.beatClosingLine == true
                                      ? 'BEAT CLOSE'
                                      : leg.lineClv == 0
                                      ? 'PUSH'
                                      : 'MISSED CLOSE'}  ${leg.lineClvPercent == null ? '' : '${leg.lineClvPercent! >= 0 ? '+' : ''}${leg.lineClvPercent!.toStringAsFixed(2)}%'}',
                                  style: TextStyle(
                                    color: leg.beatClosingLine == true
                                        ? const Color(0xFF25D97D)
                                        : const Color(0xFFFFB74D),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GameStatusBadge(status: leg.gameStatus),
                      ],
                    ),
                  ),
                ),
                if (slip.status == 'active') ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onWon,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF2BC35),
                            side: const BorderSide(color: Color(0xFFF2BC35)),
                          ),
                          child: const Text('MARK WON'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onLost,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF63A8FF),
                            side: const BorderSide(color: Color(0xFF63A8FF)),
                          ),
                          child: const Text('MARK LOST'),
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
