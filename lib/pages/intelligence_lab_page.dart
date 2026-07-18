import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/live_update_service.dart';
import '../models/slip_selection.dart';
import '../theme/app_colors.dart';
import '../widgets/context_help.dart';

class IntelligenceLabPage extends StatefulWidget {
  const IntelligenceLabPage({super.key, this.selections = const []});

  final List<SlipSelection> selections;

  @override
  State<IntelligenceLabPage> createState() => _IntelligenceLabPageState();
}

class _IntelligenceLabPageState extends State<IntelligenceLabPage> {
  final _api = ApiService();
  final _alertUpdates = LiveUpdateService(channels: const {'alerts'});
  StreamSubscription<dynamic>? _alertSubscription;
  final _playerA = TextEditingController(text: 'Quarterback');
  final _marketA = TextEditingController(text: 'Passing Yards');
  final _playerB = TextEditingController(text: 'Receiver');
  final _marketB = TextEditingController(text: 'Receiving Yards');
  final _projectionA = TextEditingController(text: '275');
  final _lineA = TextEditingController(text: '265.5');
  final _projectionB = TextEditingController(text: '82');
  final _lineB = TextEditingController(text: '74.5');
  final _recentStretch = TextEditingController(text: '18, 21, 20, 24, 26');
  String _script = 'CLOSE';
  String _sideA = 'OVER';
  String _sideB = 'OVER';
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _correlation;
  Map<String, dynamic>? _simulation;
  Map<String, dynamic>? _sentiment;
  Map<String, dynamic>? _alert;
  Map<String, dynamic>? _similarity;
  Map<String, dynamic>? _calibration;
  Map<String, dynamic>? _performance;
  bool _calibrationLoading = true;
  SlipSelection? _selectionA;
  SlipSelection? _selectionB;
  String? _savedAlertMessage;
  String? _alertDeliveryMessage;

  @override
  void initState() {
    super.initState();
    _loadActiveSlip(widget.selections);
    unawaited(_loadCalibration());
    unawaited(_loadAlertDeliveries());
    _alertSubscription = _alertUpdates.stream.listen((raw) {
      try {
        final event = jsonDecode(raw.toString());
        if (event is Map && event['type'] == 'alert.triggered' && mounted) {
          final data = event['data'];
          setState(
            () => _alertDeliveryMessage =
                'LIVE ALERT: ${data is Map ? data['name'] : 'Rule triggered'}',
          );
        }
      } catch (_) {}
    }, onError: (_) {});
    _alertUpdates.connect();
  }

  Future<void> _loadCalibration() async {
    try {
      final results = await Future.wait([
        _api.fetchIntelligence('calibration'),
        _api.fetchIntelligence('performance'),
      ]);
      if (mounted) {
        setState(() {
          _calibration = results[0];
          _performance = results[1];
        });
      }
    } catch (_) {
      // Analysis remains usable if readiness telemetry is temporarily offline.
    } finally {
      if (mounted) setState(() => _calibrationLoading = false);
    }
  }

  Future<void> _loadAlertDeliveries() async {
    try {
      final deliveries = await _api.fetchAlertDeliveries();
      if (mounted && deliveries.isNotEmpty) {
        setState(
          () => _alertDeliveryMessage =
              'LATEST ALERT: ${deliveries.first['name']}',
        );
      }
    } catch (_) {
      // Signed-out users and an empty delivery feed do not block the lab.
    }
  }

  Widget _calibrationPanel() {
    const requiredSamples = 100;
    final sampleSize = (_calibration?['sampleSize'] as num?)?.toInt() ?? 0;
    final progress = (sampleSize / requiredSamples).clamp(0.0, 1.0);
    final calibrated = sampleSize >= requiredSamples;
    final score = _calibration?['brierScore'] as num?;
    final roi = _performance?['simulatedRoi'] as num?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: calibrated
            ? Colors.greenAccent.withValues(alpha: .08)
            : AppColors.gold.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: calibrated ? Colors.greenAccent : AppColors.gold,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                calibrated ? Icons.verified_outlined : Icons.science_outlined,
                color: calibrated ? Colors.greenAccent : AppColors.gold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  calibrated ? 'MODEL CALIBRATED' : 'MODEL WARMING UP',
                  style: TextStyle(
                    color: calibrated ? Colors.greenAccent : AppColors.gold,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_calibrationLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  '$sampleSize / $requiredSamples graded',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _calibrationLoading ? null : progress,
            color: calibrated ? Colors.greenAccent : AppColors.gold,
            backgroundColor: Colors.white12,
          ),
          const SizedBox(height: 10),
          Text(
            calibrated
                ? 'Probabilities are backed by the minimum graded sample. Brier score: ${score?.toStringAsFixed(3) ?? '--'}.'
                : 'Probabilities are experimental until at least 100 genuine pregame predictions are graded. No retrospective results are counted.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          if (sampleSize > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Accuracy ${(((_performance?['accuracy'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%'
              '  •  Simulated ROI ${roi == null ? '--' : '${(roi.toDouble() * 100).toStringAsFixed(1)}%'}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant IntelligenceLabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selections != widget.selections) {
      _loadActiveSlip(widget.selections);
    }
  }

  void _loadActiveSlip(List<SlipSelection> selections) {
    _selectionA = selections.firstOrNull;
    _selectionB = selections.length > 1 ? selections[1] : null;
    if (selections.isEmpty) return;
    void load(
      SlipSelection selection,
      TextEditingController player,
      TextEditingController market,
      TextEditingController projection,
      TextEditingController line,
      void Function(String side) setSide,
    ) {
      final prop = selection.prop;
      player.text = prop.player;
      market.text = prop.market;
      projection.text = (prop.projection ?? prop.line).toString();
      line.text = prop.line.toString();
      setSide(selection.sideLabel);
    }

    load(
      selections.first,
      _playerA,
      _marketA,
      _projectionA,
      _lineA,
      (side) => _sideA = side,
    );
    if (selections.length > 1) {
      load(
        selections[1],
        _playerB,
        _marketB,
        _projectionB,
        _lineB,
        (side) => _sideB = side,
      );
    }
  }

  Map<String, dynamic> get _compoundRule => {
    'name': 'High correlation + public interest',
    'logic': 'ALL',
    'conditions': [
      {'field': 'correlation', 'operator': 'GTE', 'value': .35},
      {'field': 'interest', 'operator': 'GTE', 'value': 8},
    ],
  };

  Future<void> _saveAlert() async {
    try {
      final result = await _api.saveCompoundAlert(_compoundRule);
      if (mounted) {
        setState(
          () => _savedAlertMessage = result['created'] == true
              ? 'Alert saved and monitoring.'
              : result['reason']?.toString(),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _savedAlertMessage = error.toString());
      }
    }
  }

  Map<String, dynamic> _leg(
    String id,
    String player,
    String market,
    String projection,
    String line,
    String side,
    SlipSelection? source,
  ) => {
    'id': source?.prop.id.isNotEmpty == true ? source!.prop.id : id,
    'player': player,
    'team': '',
    'opponent': '',
    'game_id': source?.prop.eventId.isNotEmpty == true
        ? source!.prop.eventId
        : 'lab-game',
    'sport': source?.prop.sport.isNotEmpty == true
        ? source!.prop.sport.toUpperCase()
        : _analysisSport,
    'market': market,
    'side': side,
    'baseline_projection': double.tryParse(projection),
    'line': double.tryParse(line),
  };

  String get _analysisSport {
    final selectedSport = _selectionA?.prop.sport.trim();
    if (selectedSport != null && selectedSport.isNotEmpty) {
      return selectedSport.toUpperCase();
    }
    final markets = '${_marketA.text} ${_marketB.text}'.toLowerCase();
    if (markets.contains('passing') || markets.contains('receiving')) {
      return 'NFL';
    }
    return 'NBA';
  }

  String get _similarityMarket {
    final sourceMarket = _selectionA?.prop.market.trim();
    return sourceMarket?.isNotEmpty == true ? sourceMarket! : _marketA.text;
  }

  String get _sentimentPropId =>
      _selectionA?.prop.id.isNotEmpty == true ? _selectionA!.prop.id : 'a';

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final legs = [
      _leg(
        'a',
        _playerA.text,
        _marketA.text,
        _projectionA.text,
        _lineA.text,
        _sideA,
        _selectionA,
      ),
      _leg(
        'b',
        _playerB.text,
        _marketB.text,
        _projectionB.text,
        _lineB.text,
        _sideB,
        _selectionB,
      ),
    ];
    final stretch = _recentStretch.text
        .split(',')
        .map((value) => double.tryParse(value.trim()))
        .whereType<double>()
        .toList(growable: false);
    if (stretch.length < 3) {
      setState(() {
        _busy = false;
        _error = 'Enter at least three comma-separated recent values.';
      });
      return;
    }
    try {
      final results = await Future.wait([
        _api.postIntelligence('correlations', {'legs': legs}),
        _api.postIntelligence('game-script', {
          'script': _script,
          'sport': _analysisSport,
          'props': legs,
          'simulations': 10000,
          'seed': 42,
        }),
        _api.fetchPropSentiment(_sentimentPropId),
        _api.postIntelligence('alerts/evaluate', {
          ..._compoundRule,
          'snapshot': {'correlation': .62, 'interest': 10},
        }),
        _api.postIntelligence('similarity/database', {
          'player': _playerA.text,
          'sport': _analysisSport,
          'market': _similarityMarket,
          'recent_stretch': stretch,
          'limit': 5,
        }),
      ]);
      if (!mounted) return;
      setState(() {
        _correlation = results[0];
        _simulation = results[1];
        _sentiment = results[2];
        _alert = results[3];
        _similarity = results[4];
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(
    String title,
    Widget child, {
    String? description,
    String? help,
    int? step,
  }) => Card(
    color: AppColors.panel,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null && help != null && step != null)
            GuidedSectionHeader(
              step: step,
              title: title,
              description: description,
              help: help,
            )
          else
            Text(
              title,
              style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );

  void _showGuide() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('How to use Intelligence Lab'),
        content: const SizedBox(
          width: 470,
          child: Text(
            '1. Compare two props and enter your projections and sportsbook lines.\n\n'
            '2. Choose the game environment you want to test.\n\n'
            '3. Add recent results for historical matching.\n\n'
            '4. Run the analysis and review each result card.\n\n'
            'Results are decision support—not guaranteed outcomes. Always verify live lines before placing a wager.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('START ANALYSIS'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pair =
        (_correlation?['pairs'] as List?)?.firstOrNull as Map<String, dynamic>?;
    final impacts = (_simulation?['impacts'] as List?) ?? const [];
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'INTELLIGENCE LAB',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _showGuide,
              icon: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('QUICK GUIDE'),
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          'Model prop relationships, game scripts, market sentiment, and compound triggers.',
          style: TextStyle(color: Color(0xFF9DB0C2)),
        ),
        const SizedBox(height: 16),
        _calibrationPanel(),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            avatar: const Icon(Icons.link_rounded, size: 16),
            label: Text(
              _selectionA == null
                  ? 'DEMO CONTEXT: $_analysisSport'
                  : 'ACTIVE SLIP CONTEXT: $_analysisSport',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _card(
          'PROP CORRELATION WORKFLOW',
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _playerA,
                      decoration: const InputDecoration(labelText: 'Player 1'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _marketA,
                      decoration: const InputDecoration(labelText: 'Market 1'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _playerB,
                      decoration: const InputDecoration(labelText: 'Player 2'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _marketB,
                      decoration: const InputDecoration(labelText: 'Market 2'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _projectionA,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Projection 1',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lineA,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Line 1'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _projectionB,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Projection 2',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lineB,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Line 2'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          step: 1,
          description: 'Compare two props and see how their outcomes interact.',
          help:
              'Correlation estimates how two outcomes tend to move together. Positive correlation means they are more likely to hit together; negative correlation means one may work against the other.',
        ),
        _card(
          'GAME-SCRIPT SIMULATOR',
          DropdownButton<String>(
            value: _script,
            isExpanded: true,
            items: const [
              'CLOSE',
              'HOME_BLOWOUT',
              'AWAY_BLOWOUT',
              'SHOOTOUT',
              'LOW_SCORING',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: _busy ? null : (v) => setState(() => _script = v!),
          ),
          step: 2,
          description:
              'Test how the expected game environment changes projections.',
          help:
              'A game script is a hypothetical game environment. A blowout can reduce starter minutes, while a shootout can increase passing or scoring volume.',
        ),
        _card(
          'PGVECTOR SIMILARITY MATCHER',
          TextField(
            controller: _recentStretch,
            decoration: const InputDecoration(
              labelText: 'Recent values (comma separated)',
              helperText: 'Example: 18, 21, 20, 24, 26',
            ),
          ),
          step: 3,
          description:
              'Find historical stretches that resemble recent performance.',
          help:
              'Historical similarity compares the shape of recent results with prior stretches and shows what happened next. It provides context, not a guaranteed forecast.',
        ),
        ElevatedButton(
          onPressed: _busy ? null : () => unawaited(_run()),
          child: Text(_busy ? 'RUNNING…' : 'RUN INTELLIGENCE'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (_alertDeliveryMessage != null)
          _card(
            'LIVE ALERT DELIVERY',
            Text(
              _alertDeliveryMessage!,
              style: const TextStyle(color: Colors.greenAccent),
            ),
          ),
        if (_correlation != null)
          _card(
            'CORRELATION RESULT',
            Text(
              '${pair?['classification'] ?? 'NEUTRAL'}  •  ${pair?['coefficient'] ?? 0}\n${pair?['reason'] ?? _correlation?['warning']}',
              style: const TextStyle(color: Colors.white),
            ),
            step: 4,
            description:
                'Review the strength and direction of the relationship.',
            help:
                'Coefficients range from -1 to +1. Values near zero have little measured relationship; stronger positive or negative values matter more when building a parlay.',
          ),
        if (_simulation != null)
          _card(
            'MONTE CARLO SCRIPT IMPACTS',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_simulation?['simulations']} simulations | portfolio hit '
                  '${_simulation?['portfolioHitProbability'] == null ? '--' : '${((_simulation?['portfolioHitProbability'] as num) * 100).toStringAsFixed(1)}%'}',
                  style: const TextStyle(color: Colors.greenAccent),
                ),
                const SizedBox(height: 8),
                Text(
                  impacts
                      .map(
                        (e) =>
                            '${e['player']}: ${e['adjustedProjection'] ?? '--'} vs ${e['line'] ?? '--'} | hit ${e['hitProbability'] == null ? '--' : '${((e['hitProbability'] as num) * 100).toStringAsFixed(1)}%'}',
                      )
                      .join('\n'),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            step: 5,
            description:
                'See modeled hit rates across thousands of game outcomes.',
            help:
                'Monte Carlo simulation samples many plausible outcomes. Hit probability is the share that cleared the line, not a promise that the prop will hit.',
          ),
        if (_sentiment != null)
          _card(
            'SENTIMENT DISPLAY',
            Text(
              '${_sentiment?['label']}  •  Score ${_sentiment?['score']}  •  Sample ${_sentiment?['sampleSize']}',
              style: const TextStyle(color: Colors.white),
            ),
            step: 6,
            description:
                'Understand whether app activity leans follow or fade.',
            help:
                'Sentiment summarizes searches and interactions inside the app. Always consider sample size; a small sample is less reliable.',
          ),
        if (_similarity != null)
          _card(
            'HISTORICAL ANALOGS',
            Text(
              'Projected next game: ${_similarity?['analogNextGameProjection'] ?? '--'}\n'
              '${((_similarity?['matches'] as List?) ?? const []).map((match) => '${match['player']} | similarity ${match['similarity']} | next ${match['nextGameValue']}').join('\n')}',
              style: const TextStyle(color: Colors.white),
            ),
            step: 7,
            description: 'Review comparable stretches and next-game results.',
            help:
                'Vector similarity locates statistically comparable sequences. Review the quality and number of matches before using the next-game projection.',
          ),
        if (_alert != null)
          _card(
            'COMPOUND-ALERT BUILDER',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _alert?['triggered'] == true
                      ? 'TRIGGERED — all configured conditions match.'
                      : 'Monitoring — conditions not yet met.',
                  style: TextStyle(
                    color: _alert?['triggered'] == true
                        ? Colors.greenAccent
                        : Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => unawaited(_saveAlert()),
                  child: const Text('SAVE ALERT RULE'),
                ),
                if (_savedAlertMessage != null)
                  Text(
                    _savedAlertMessage!,
                    style: const TextStyle(color: Color(0xFF9DB0C2)),
                  ),
              ],
            ),
            step: 8,
            description: 'Save multiple conditions as one monitored rule.',
            help:
                'Compound alerts trigger only when the configured logic is satisfied. This example requires both strong correlation and elevated community interest.',
          ),
      ],
    );
  }

  @override
  void dispose() {
    unawaited(_alertSubscription?.cancel());
    unawaited(_alertUpdates.dispose());
    _playerA.dispose();
    _marketA.dispose();
    _playerB.dispose();
    _marketB.dispose();
    _projectionA.dispose();
    _lineA.dispose();
    _projectionB.dispose();
    _lineB.dispose();
    _recentStretch.dispose();
    super.dispose();
  }
}
