import 'dart:async';

import 'package:flutter/material.dart';

import '../models/slip_selection.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class ContextResearchPanel extends StatefulWidget {
  const ContextResearchPanel({super.key, this.selection, required this.sport});

  final SlipSelection? selection;
  final String sport;

  @override
  State<ContextResearchPanel> createState() => _ContextResearchPanelState();
}

class _ContextResearchPanelState extends State<ContextResearchPanel> {
  static const _metrics = <String, String>{
    'points': 'PTS',
    'rebounds': 'REB',
    'assists': 'AST',
    'steals': 'STL',
    'blocks': 'BLK',
    'threes': '3PM',
  };
  final _api = ApiService();
  late final TextEditingController _player;
  final _threshold = TextEditingController(text: '25');
  final Set<String> _selected = {'points', 'rebounds', 'assists'};
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = TextEditingController(text: widget.selection?.prop.player ?? '');
  }

  @override
  void didUpdateWidget(covariant ContextResearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.selection?.prop.player ?? '';
    if (next.isNotEmpty && next != oldWidget.selection?.prop.player) {
      _player.text = next;
      _result = null;
    }
  }

  Future<void> _run() async {
    final threshold = double.tryParse(_threshold.text);
    if (_player.text.trim().length < 2 ||
        threshold == null ||
        _selected.isEmpty) {
      setState(
        () => _error = 'Enter a player, threshold, and at least one stat.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.postIntelligence('context-research', {
        'player': _player.text.trim(),
        'sport': widget.sport.toUpperCase(),
        'metrics': _selected.toList(),
        'threshold': threshold,
        'limit': 40,
      });
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _metric(String label, String value) => Container(
    width: 126,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final prop = widget.selection?.prop;
    final supported = {'NBA', 'WNBA'}.contains(widget.sport.toUpperCase());
    final sample = (_result?['sampleSize'] as num?)?.toInt() ?? 0;
    final hitRate = (_result?['hitRate'] as num?)?.toDouble();
    final splits =
        (_result?['restSplits'] as List?)?.whereType<Map>().toList() ??
        const [];
    return Card(
      color: AppColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.gold),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CONTEXT RESEARCH',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Build a custom full-game Stat Slam and see how rest and matchup context change the result.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (prop != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (prop.restDays != null)
                    Chip(
                      label: Text(
                        '${prop.restDays!.toStringAsFixed(0)} DAYS REST',
                      ),
                    ),
                  if (prop.fatigueMultiplier != null)
                    Chip(
                      label: Text(
                        'FATIGUE ${(prop.fatigueMultiplier! * 100).toStringAsFixed(0)}% PROJECTION',
                      ),
                    ),
                  if (prop.matchupMultiplier != null)
                    Chip(
                      label: Text(
                        'MATCHUP ${(prop.matchupMultiplier! * 100).toStringAsFixed(0)}%',
                      ),
                    ),
                ],
              ),
              if (prop.matchupContext.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  prop.matchupContext,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 14),
            if (!supported)
              const Text(
                'Verified Stat Slam history is currently available for NBA and WNBA. Other sports will unlock only after their full-game historical fields are verified.',
                style: TextStyle(color: AppColors.warning),
              )
            else ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 230,
                    child: TextField(
                      controller: _player,
                      decoration: const InputDecoration(labelText: 'Player'),
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _threshold,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Threshold'),
                    ),
                  ),
                  ..._metrics.entries.map(
                    (entry) => FilterChip(
                      label: Text(entry.value),
                      selected: _selected.contains(entry.key),
                      onSelected: (selected) => setState(() {
                        selected
                            ? _selected.add(entry.key)
                            : _selected.remove(entry.key);
                      }),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : () => unawaited(_run()),
                    icon: const Icon(Icons.query_stats),
                    label: Text(_loading ? 'ANALYZING' : 'RUN STAT SLAM'),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              if (_result!['available'] != true)
                Text(
                  _result!['reason']?.toString() ??
                      'No verified games found for this player.',
                  style: const TextStyle(color: AppColors.warning),
                )
              else ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metric(
                      'HIT RATE',
                      hitRate == null
                          ? '--'
                          : '${(hitRate * 100).toStringAsFixed(1)}%',
                    ),
                    _metric('GAMES', '$sample'),
                    _metric(
                      'AVERAGE',
                      (_result!['average'] as num?)?.toStringAsFixed(1) ?? '--',
                    ),
                    _metric(
                      'MEDIAN',
                      (_result!['median'] as num?)?.toStringAsFixed(1) ?? '--',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'PERFORMANCE BY REST',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: splits.map((raw) {
                    final split = Map<String, dynamic>.from(raw);
                    final rate = (split['hitRate'] as num?)?.toDouble();
                    return _metric(
                      '${split['label']} • ${split['games']} G',
                      rate == null
                          ? '--'
                          : '${(rate * 100).toStringAsFixed(0)}%  |  AVG ${(split['average'] as num).toStringAsFixed(1)}',
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_result!['source']} • Sample size is always shown; full-game results only.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    _threshold.dispose();
    super.dispose();
  }
}
