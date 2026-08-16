import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';

PropData? bestResearchComparison(PropData prop, Iterable<PropData> candidates) {
  final peers = candidates
      .where(
        (item) =>
            item.id != prop.id && item.sport == prop.sport && item.selectable,
      )
      .toList();
  peers.sort((a, b) {
    final trust = b.piTrustScore.compareTo(a.piTrustScore);
    return trust;
  });
  return peers.isEmpty ? null : peers.first;
}

String answerPropResearchQuestion(
  PropData prop,
  String question, {
  PropData? comparison,
}) {
  final query = question.trim().toLowerCase();
  if (query.contains('compare')) {
    if (comparison == null) {
      return 'No other selectable ${prop.sport} prop is available to compare right now. PI will not substitute a stale or unverified prop.';
    }
    final trustWinner = prop.piTrustScore >= comparison.piTrustScore
        ? prop
        : comparison;
    return '${prop.player} ${prop.displayMarket} has PI Trust ${prop.piTrustScore}/100. '
        '${comparison.player} ${comparison.displayMarket} has PI Trust ${comparison.piTrustScore}/100. '
        '${trustWinner.player} has the stronger data foundation based on verified inputs. '
        'Confirm both live lines before choosing.';
  }
  if (query.contains('injur') ||
      query.contains('lineup') ||
      query.contains('change')) {
    final factors = <String>[
      'injury: ${prop.injuryStatus}',
      'lineup: ${prop.lineupStatus}',
      if (prop.roleChange.toUpperCase() != 'UNKNOWN')
        'role: ${prop.roleChange.replaceAll('_', ' ')}',
      if (prop.usageMultiplier != null)
        'usage factor: ${prop.usageMultiplier!.toStringAsFixed(2)}x',
      if (prop.wowyMultiplier != null)
        'with/without factor: ${prop.wowyMultiplier!.toStringAsFixed(2)}x',
    ];
    return 'The verified change checks for this prop are ${factors.join(', ')}. PI does not estimate an injury effect when a verified factor is missing.';
  }
  if (query.contains('trust') ||
      query.contains('data') ||
      query.contains('reliable')) {
    final warning = prop.piTrustWarnings.isEmpty
        ? 'No current trust warning.'
        : prop.piTrustWarnings.first;
    return 'PI Trust is ${prop.piTrustScore}/100 (${prop.piTrustBand}). $warning Trust measures research-data dependability, not the chance that the pick wins.';
  }
  if (query.contains('line move') ||
      query.contains('movement') ||
      query.contains('price')) {
    final moved = prop.currentLine - prop.openingLine;
    return 'The line opened at ${prop.openingLine.toStringAsFixed(1)} and is now ${prop.currentLine.toStringAsFixed(1)} '
        '(${moved >= 0 ? '+' : ''}${moved.toStringAsFixed(1)}). Last movement: ${prop.lineMovedAtUtc.isEmpty ? 'not supplied' : prop.lineMovedAtUtc}. Confirm the current provider line before saving.';
  }
  if (query.contains('why') ||
      query.contains('lean') ||
      query.contains('play')) {
    final reason = prop.verdict.reason.isNotEmpty
        ? prop.verdict.reason
        : prop.recommendationExplanation.isNotEmpty
        ? prop.recommendationExplanation
        : 'No model explanation is available yet.';
    final projection = prop.projection == null
        ? 'No verified numeric projection is available.'
        : 'Projection ${prop.projection!.toStringAsFixed(1)} versus line ${prop.line.toStringAsFixed(1)}.';
    return '${prop.verdict.headline.isEmpty ? prop.pickText : prop.verdict.headline}. $projection $reason Trust ${prop.piTrustScore}/100.';
  }
  return '${prop.player} ${prop.displayMarket}: line ${prop.line.toStringAsFixed(1)}, PI Trust ${prop.piTrustScore}/100, '
      'injury ${prop.injuryStatus}, lineup ${prop.lineupStatus}. '
      'Ask why it is a lean, what could change, whether the data is reliable, about line movement, or to compare it.';
}

class PropResearchAiButton extends StatelessWidget {
  const PropResearchAiButton({
    super.key,
    required this.prop,
    this.comparisonCandidates = const [],
  });

  final PropData prop;
  final List<PropData> comparisonCandidates;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('ask-pi-research'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.panel,
        builder: (_) => _ResearchAssistantSheet(
          prop: prop,
          comparison: bestResearchComparison(prop, comparisonCandidates),
        ),
      ),
      icon: const Icon(Icons.auto_awesome_outlined, size: 15),
      label: const Text('ASK PI RESEARCH AI'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.gold,
        side: BorderSide(color: AppColors.gold.withValues(alpha: .7)),
        textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _ResearchAssistantSheet extends StatefulWidget {
  const _ResearchAssistantSheet({required this.prop, this.comparison});

  final PropData prop;
  final PropData? comparison;

  @override
  State<_ResearchAssistantSheet> createState() =>
      _ResearchAssistantSheetState();
}

class _ResearchAssistantSheetState extends State<_ResearchAssistantSheet> {
  final _controller = TextEditingController();
  String _answer =
      'Ask a grounded question about this live prop. Answers use only the data shown by PI.';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ask(String question) {
    _controller.text = question;
    setState(
      () => _answer = answerPropResearchQuestion(
        widget.prop,
        question,
        comparison: widget.comparison,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'PI RESEARCH AI',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.prop.player} · ${widget.prop.displayMarket}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final prompt in const [
                    'Why is this a lean?',
                    'Can I trust this data?',
                    'What could change?',
                    'Compare these two props',
                  ])
                    ActionChip(
                      label: Text(prompt),
                      onPressed: () => _ask(prompt),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ask about this prop',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _ask(_controller.text),
                  ),
                ),
                onSubmitted: _ask,
              ),
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('pi-research-answer'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: .35),
                  ),
                ),
                child: Text(
                  _answer,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Grounded in the current PI payload. Informational research only; no outcome is guaranteed.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
