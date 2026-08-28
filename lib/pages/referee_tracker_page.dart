import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';

typedef RefereeTrackerLoader =
    Future<Map<String, dynamic>> Function(String sport);

class RefereeTrackerPage extends StatefulWidget {
  const RefereeTrackerPage({super.key, this.loader});

  final RefereeTrackerLoader? loader;

  @override
  State<RefereeTrackerPage> createState() => _RefereeTrackerPageState();
}

class _RefereeTrackerPageState extends State<RefereeTrackerPage> {
  late final RefereeTrackerLoader _loader =
      widget.loader ??
      (sport) => ApiService().fetchIntelligence(
        'officiating-tracker?sport=${Uri.encodeQueryComponent(sport)}',
      );
  String _sport = 'WNBA';
  String _query = '';
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _payload;
  Timer? _refreshTimer;
  bool _loadInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await _loader(_sport);
      if (!mounted) return;
      setState(() => _payload = payload);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Referee data is temporarily unavailable. Try refreshing shortly.';
      });
    } finally {
      _loadInFlight = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _officials {
    final raw = _payload?['officials'];
    if (raw is! List) return const [];
    final query = _query.trim().toLowerCase();
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (item) =>
              query.isEmpty ||
              '${item['officialName'] ?? ''}'.toLowerCase().contains(query),
        )
        .toList();
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildControls(),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
              )
            else if (_error != null)
              _MessagePanel(
                icon: Icons.cloud_off_outlined,
                message: _error!,
                action: _load,
              )
            else if (_officials.isEmpty)
              _MessagePanel(
                icon: Icons.sports_outlined,
                message:
                    '${_payload?['reason'] ?? 'No $_sport officiating profiles are available yet.'}',
                action: _load,
              )
            else ...[
              _buildSummary(),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1050
                      ? 3
                      : constraints.maxWidth >= 650
                      ? 2
                      : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final official in _officials)
                        SizedBox(
                          width: width,
                          child: _OfficialCard(
                            official: official,
                            sport: _sport,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                '${_payload?['disclaimer'] ?? 'Historical tendencies are informational and do not guarantee future outcomes.'}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderGold),
    ),
    child: const Row(
      children: [
        CircleAvatar(
          backgroundColor: Color(0x24FFC400),
          child: Icon(Icons.sports_outlined, color: AppColors.gold),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'OFFICIATING TRACKER',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  _ProBadge(),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'Compare sample-adjusted referee and umpire tendencies.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildControls() => Wrap(
    spacing: 10,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'WNBA', label: Text('WNBA')),
          ButtonSegment(value: 'NBA', label: Text('NBA')),
          ButtonSegment(value: 'MLB', label: Text('MLB')),
        ],
        selected: {_sport},
        onSelectionChanged: (selection) {
          setState(() => _sport = selection.first);
          _load();
        },
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.background
                : AppColors.silver,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.gold
                : AppColors.panel,
          ),
        ),
      ),
      SizedBox(
        width: 260,
        child: TextField(
          onChanged: (value) => setState(() => _query = value),
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: 'Search officials',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.panel,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Refresh referee data',
        onPressed: _load,
        icon: const Icon(Icons.refresh, color: AppColors.gold),
      ),
    ],
  );

  Widget _buildSummary() {
    final officials = _officials;
    final sampleGames = officials.fold<int>(
      0,
      (sum, item) => sum + (_number(item['sampleSize']).round()),
    );
    final leagueRate = officials.isEmpty
        ? 0.0
        : _number(officials.first['leagueRate']);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SummaryTile(
          label: _sport == 'MLB' ? 'UMPIRES' : 'REFEREES',
          value: '${officials.length}',
        ),
        _SummaryTile(
          label: _sport == 'MLB' ? 'PROFILE PITCHES' : 'PROFILE GAMES',
          value: '$sampleGames',
        ),
        _SummaryTile(
          label: _sport == 'MLB'
              ? 'LEAGUE CALLED-STRIKE AVG'
              : 'LEAGUE WHISTLE AVG',
          value: _sport == 'MLB'
              ? '${(leagueRate * 100).toStringAsFixed(1)}%'
              : leagueRate.toStringAsFixed(1),
        ),
      ],
    );
  }
}

class _OfficialCard extends StatelessWidget {
  const _OfficialCard({required this.official, required this.sport});

  final Map<String, dynamic> official;
  final String sport;

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  @override
  Widget build(BuildContext context) {
    final index = _number(official['tendencyIndex']);
    final delta = (index - 1) * 100;
    final metric = sport == 'MLB' ? 'called-strike rate' : 'whistle rate';
    final tendency = delta >= 3
        ? 'Above league $metric'
        : delta <= -3
        ? 'Below league $metric'
        : 'Near league $metric';
    final recent = (official['recentAssignments'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .toList();
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_search_outlined, color: AppColors.gold),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${official['officialName'] ?? 'Unknown official'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: sport == 'MLB' ? 'CALLED STRIKE %' : 'AVG WHISTLES',
                  value: sport == 'MLB'
                      ? '${(_number(official['rawRate']) * 100).toStringAsFixed(1)}%'
                      : _number(official['rawRate']).toStringAsFixed(1),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'VS LEAGUE',
                  value: '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'GAMES',
                  value: '${official['sampleSize'] ?? 0}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            tendency.toUpperCase(),
            style: TextStyle(
              color: delta.abs() < 3 ? AppColors.silver : AppColors.gold,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: .4,
            ),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: _number(official['confidence']).clamp(0, 1),
            minHeight: 4,
            backgroundColor: AppColors.gunmetal,
            color: AppColors.gold,
          ),
          const SizedBox(height: 5),
          Text(
            'Profile confidence ${(_number(official['confidence']) * 100).round()}%',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 13),
            const Divider(color: AppColors.border),
            const Text(
              'RECENT ASSIGNMENTS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final assignment in recent)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${assignment['gameDate']}  •  ${assignment['totalFouls']} fouls  •  ${assignment['totalFreeThrowAttempts']} FTA',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ],
  );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: 175,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppColors.panelLight,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.gold,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'PRO',
      style: TextStyle(
        color: AppColors.background,
        fontSize: 9,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    required this.action,
  });
  final IconData icon;
  final String message;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppColors.textMuted, size: 36),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: action,
          icon: const Icon(Icons.refresh),
          label: const Text('TRY AGAIN'),
        ),
      ],
    ),
  );
}
