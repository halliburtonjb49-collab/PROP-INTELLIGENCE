import 'package:flutter/material.dart';

import '../models/daily_briefing.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart' as app_colors;

/// Today's board, said once, before anyone scrolls five thousand cards.
///
/// The page is built around a distinction the board itself cannot draw: the
/// difference between a slate with nothing worth playing and a slate we
/// failed to read. Both produce an empty list, and they mean opposite things,
/// so a failure says so explicitly and never borrows the language of a quiet
/// day.
///
/// The caveats are a section rather than a footnote for the same reason. A
/// briefing that reports only its plays reads as confidence, and what today's
/// board cannot tell you changes what its plays are worth.
class BriefingPage extends StatefulWidget {
  const BriefingPage({super.key, this.apiService});

  final ApiService? apiService;

  @override
  State<BriefingPage> createState() => _BriefingPageState();
}

class _BriefingPageState extends State<BriefingPage>
    with WidgetsBindingObserver {
  late final ApiService _api = widget.apiService ?? ApiService();
  DailyBriefing _briefing = const DailyBriefing();
  bool _loading = true;
  String _error = '';
  bool _hasLoadedBriefing = false;

  String _freshnessLabel() {
    final updated = DateTime.tryParse(_briefing.sourceUpdatedAt)?.toLocal();
    if (updated == null) return '';
    final age = DateTime.now().difference(updated);
    if (age.isNegative || age.inMinutes < 1) return 'DATA UPDATED JUST NOW';
    if (age.inHours < 1) return 'DATA UPDATED ${age.inMinutes}M AGO';
    if (age.inDays < 1) return 'DATA UPDATED ${age.inHours}H AGO';
    return 'DATA UPDATED ${age.inDays}D AGO';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(background: true);
  }

  Future<void> _load({bool background = false}) async {
    setState(() {
      _loading = !_hasLoadedBriefing && !background;
      _error = '';
    });
    try {
      final payload = await _api.fetchTodaysBriefing().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() {
        _briefing = DailyBriefing.fromJson(payload);
        _hasLoadedBriefing = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (!_hasLoadedBriefing) _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: app_colors.AppColors.gold),
        ),
      );
    }

    if (_error.isNotEmpty) {
      // Deliberately not phrased as an empty slate. "Nothing clears the bar"
      // is a claim about the board; this is an admission about us.
      return _Panel(
        key: const ValueKey('briefing-unavailable'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "TODAY'S BRIEFING IS UNAVAILABLE",
              style: TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This is a failure to read the board, not a quiet day. Nothing '
              'here should be taken as a statement about what is available.',
              style: TextStyle(
                color: app_colors.AppColors.textSecondary,
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              key: const ValueKey('briefing-retry'),
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: app_colors.AppColors.gold,
                side: const BorderSide(color: app_colors.AppColors.gold),
              ),
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "TODAY'S PI BRIEFING",
                style: TextStyle(
                  color: app_colors.AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _briefing.summary,
                key: const ValueKey('briefing-summary'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _Stat(label: 'ON BOARD', value: '${_briefing.propsOnBoard}'),
                  _Stat(
                    label: 'CLEAR THE BAR',
                    value: '${_briefing.actionable}',
                  ),
                  _Stat(
                    label: 'SPORTS',
                    value: _briefing.sportsCovered.isEmpty
                        ? '--'
                        : '${_briefing.sportsCovered.length}',
                  ),
                ],
              ),
              if (_briefing.generatedAt.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'BOARD ${_briefing.boardDate.isEmpty ? 'TODAY' : _briefing.boardDate}'
                  '${_freshnessLabel().isEmpty ? '' : '  •  ${_freshnessLabel()}'}',
                  style: const TextStyle(
                    color: app_colors.AppColors.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_briefing.sportsToResearch.isNotEmpty) ...[
          const _SectionTitle('SPORTS TO RESEARCH'),
          const SizedBox(height: 8),
          for (final sport in _briefing.sportsToResearch) ...[
            _SportCard(sport: sport),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
        ],
        if (_briefing.leadPlays.isNotEmpty) ...[
          const _SectionTitle('LEADING RESEARCH'),
          const SizedBox(height: 8),
        ],
        if (_briefing.leadPlays.isEmpty)
          _Panel(
            key: const ValueKey('briefing-quiet-day'),
            child: const Text(
              'Nothing on the board clears the bar today. That is the '
              'finding, not a gap -- a slate worth skipping is a result worth '
              'reporting.',
              style: TextStyle(
                color: app_colors.AppColors.textSecondary,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          )
        else
          for (final play in _briefing.leadPlays) ...[
            _PlayCard(play: play),
            const SizedBox(height: 8),
          ],
        if (_briefing.caveats.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Panel(
            key: const ValueKey('briefing-caveats'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WHAT TODAY CANNOT TELL YOU',
                  style: TextStyle(
                    color: app_colors.AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 8),
                for (final caveat in _briefing.caveats)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '•  $caveat',
                      style: const TextStyle(
                        color: app_colors.AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayCard extends StatelessWidget {
  const _PlayCard({required this.play});

  final BriefingPlay play;

  @override
  Widget build(BuildContext context) {
    final colour = switch (play.decision) {
      'PLAY_NOW' => app_colors.AppColors.success,
      'SHOP' => app_colors.AppColors.gold,
      _ => app_colors.AppColors.textSecondary,
    };
    final line = play.line == null ? '' : play.line!.toStringAsFixed(1);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  play.headline.isEmpty ? play.decision : play.headline,
                  style: TextStyle(
                    color: colour,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (play.piTrustScore > 0)
                Text(
                  'PI TRUST ${play.piTrustScore}',
                  style: TextStyle(
                    color: colour,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${play.player}  •  ${play.market} $line'
            '${play.sportsbook.isEmpty ? '' : '  •  ${play.sportsbook}'}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (play.reason.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              play.reason,
              style: const TextStyle(
                color: app_colors.AppColors.textSecondary,
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SportCard extends StatelessWidget {
  const _SportCard({required this.sport});

  final BriefingSport sport;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sport.sport,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${sport.playable} RESEARCH-READY',
                style: const TextStyle(
                  color: app_colors.AppColors.success,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _MiniStat(label: 'ALL', value: sport.total),
              _MiniStat(label: 'PLAY NOW', value: sport.playNow),
              _MiniStat(label: 'SHOP', value: sport.shop),
              _MiniStat(label: 'LEAN', value: sport.lean),
              _MiniStat(label: 'WAIT', value: sport.wait),
              _MiniStat(label: 'AVG PI TRUST', value: sport.averagePiTrust),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label ',
        style: const TextStyle(
          color: app_colors.AppColors.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
        children: [
          TextSpan(
            text: '$value',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: app_colors.AppColors.gold,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: .5,
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: app_colors.AppColors.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1823),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      child: child,
    );
  }
}
