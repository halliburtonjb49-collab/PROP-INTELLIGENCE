import 'package:flutter/material.dart';

import '../theme/app_colors.dart' as brand_colors;

class GeneratedBuilderLegCard extends StatelessWidget {
  const GeneratedBuilderLegCard({
    super.key,
    required this.subtreeKey,
    this.cardKey,
    required this.leg,
    required this.index,
    required this.propId,
    required this.isSelected,
    required this.isLocked,
    required this.isWatchlisted,
    required this.isInActiveSlip,
    required this.isLoadingWatchlist,
    required this.isReplacing,
    required this.isEditingNote,
    required this.isExplanationExpanded,
    required this.explanationPanel,
    required this.onRemoveFromSlip,
    required this.onToggleSelection,
    required this.onToggleLock,
    required this.onToggleWatchlist,
    required this.onReplace,
    required this.onEditNote,
    required this.onShowLabelMenu,
    required this.onToggleExplanation,
  });

  final Key subtreeKey;
  final Key? cardKey;
  final Map<String, dynamic> leg;
  final int index;
  final String propId;
  final bool isSelected;
  final bool isLocked;
  final bool isWatchlisted;
  final bool isInActiveSlip;
  final bool isLoadingWatchlist;
  final bool isReplacing;
  final bool isEditingNote;
  final bool isExplanationExpanded;
  final Widget explanationPanel;
  final VoidCallback onRemoveFromSlip;
  final VoidCallback onToggleSelection;
  final VoidCallback onToggleLock;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onReplace;
  final VoidCallback onEditNote;
  final VoidCallback onShowLabelMenu;
  final VoidCallback onToggleExplanation;

  static String _movementLabel(Map<String, dynamic> leg) {
    final status =
        leg['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    return switch (status) {
      'BETTER' => 'BETTER LINE',
      'WORSE' => 'WORSE LINE',
      'MOVED' => 'LINE MOVED',
      'UNAVAILABLE' => 'LINE UNAVAILABLE',
      _ => 'NO CHANGE',
    };
  }

  static IconData _movementIcon(String status) {
    return switch (status.toUpperCase()) {
      'BETTER' => Icons.trending_up,
      'WORSE' => Icons.trending_down,
      'MOVED' => Icons.swap_vert,
      'UNAVAILABLE' => Icons.remove_circle_outline,
      _ => Icons.horizontal_rule,
    };
  }

  static String _formatAmericanOdds(int odds) => odds > 0 ? '+$odds' : '$odds';

  @override
  Widget build(BuildContext context) {
    final side = leg['side']?.toString() ?? '';
    final displayedLine =
        leg['current_line']?.toString() ?? leg['line']?.toString() ?? '';
    final builtLine =
        leg['original_line']?.toString() ?? leg['line']?.toString() ?? '';
    final market = leg['market']?.toString() ?? '';
    final propSite = leg['prop_site']?.toString() ?? '';
    final edge = leg['edge']?.toString() ?? '';
    final confidence = leg['confidence']?.toString() ?? '';
    final matchup = leg['matchup']?.toString() ?? '';
    final customLabel = leg['custom_label']?.toString() ?? '';
    final manualNote = leg['manual_note']?.toString() ?? '';
    final resultStatus = leg['result_status']?.toString() ?? 'pending';
    final resultValue = (leg['result_value'] as num?)?.toDouble();
    final movementStatus =
        leg['movement_status']?.toString().toUpperCase() ?? 'UNCHANGED';
    final originalLine = (leg['original_line'] as num?)?.toDouble();
    final currentLine = (leg['current_line'] as num?)?.toDouble();
    final originalOdds = (leg['original_odds'] as num?)?.toInt();
    final currentOdds = (leg['current_odds'] as num?)?.toInt();

    return KeyedSubtree(
      key: subtreeKey,
      child: Card(
        key: cardKey,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12, top: 4),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                leg['player']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (isLocked) const Icon(Icons.lock, size: 18),
                          ],
                        ),
                        if (customLabel.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Chip(
                            avatar: const Icon(Icons.label, size: 16),
                            label: Text(customLabel),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text('Current: $side $displayedLine $market'),
                        if (builtLine != displayedLine) ...[
                          const SizedBox(height: 3),
                          Text('Built at: $side $builtLine'),
                        ],
                        if (originalLine != null &&
                            currentLine != null &&
                            originalLine != currentLine) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Line moved: ${originalLine.toStringAsFixed(1)} → ${currentLine.toStringAsFixed(1)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                        if (originalOdds != null &&
                            currentOdds != null &&
                            originalOdds != currentOdds) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Odds moved: ${_formatAmericanOdds(originalOdds)} → ${_formatAmericanOdds(currentOdds)}',
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text(
                          '$propSite • Edge $edge% • Confidence $confidence%',
                        ),
                        const SizedBox(height: 5),
                        Text(
                          matchup,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (resultValue != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Final: ${resultValue.toStringAsFixed(1)} • ${resultStatus.toUpperCase()}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: resultStatus == 'won'
                                  ? brand_colors.AppColors.blue
                                  : resultStatus == 'lost'
                                  ? Colors.redAccent
                                  : null,
                            ),
                          ),
                        ],
                        if (manualNote.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.sticky_note_2_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(manualNote)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            Chip(label: Text('Edge $edge%')),
                            Chip(label: Text('Confidence $confidence%')),
                            if (leg['last_line_check'] != null)
                              Chip(
                                avatar: Icon(
                                  _movementIcon(movementStatus),
                                  size: 17,
                                ),
                                label: Text(_movementLabel(leg)),
                              ),
                            if (leg['historical_hit_rate'] != null)
                              Chip(
                                label: Text(
                                  'History ${(leg['historical_hit_rate'] as num).toStringAsFixed(1)}%',
                                ),
                              ),
                            if (isInActiveSlip)
                              const Chip(
                                avatar: Icon(Icons.check_circle, size: 16),
                                label: Text('Active Slip'),
                              ),
                          ],
                        ),
                        if (movementStatus != 'UNCHANGED') ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: movementStatus == 'BETTER'
                                    ? brand_colors.AppColors.blue
                                    : movementStatus == 'WORSE'
                                    ? Colors.redAccent
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(_movementIcon(movementStatus)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _movementLabel(leg),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: isInActiveSlip
                            ? onRemoveFromSlip
                            : onToggleSelection,
                        icon: Icon(
                          isInActiveSlip || isSelected
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                        ),
                        label: Text(
                          isInActiveSlip
                              ? 'REMOVE FROM SLIP'
                              : isSelected
                              ? 'REMOVE'
                              : 'ADD',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: onToggleLock,
                        icon: Icon(isLocked ? Icons.lock : Icons.lock_open),
                        label: Text(isLocked ? 'SAVED' : 'SAVE SELECTION'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: isLoadingWatchlist
                            ? null
                            : onToggleWatchlist,
                        icon: Icon(
                          isWatchlisted
                              ? Icons.visibility
                              : Icons.visibility_outlined,
                        ),
                        label: Text(isWatchlisted ? 'WATCHING' : 'WATCHLIST'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: isLocked || isReplacing ? null : onReplace,
                        icon: isReplacing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          isLocked
                              ? 'LOCKED'
                              : isReplacing
                              ? 'REPLACING'
                              : 'REPLACE',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: isEditingNote ? null : onEditNote,
                        icon: const Icon(Icons.edit_note),
                        label: const Text('ADD NOTE'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: onShowLabelMenu,
                        icon: const Icon(Icons.label_outline),
                        label: const Text('LABEL'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: onToggleExplanation,
                        icon: Icon(
                          isExplanationExpanded
                              ? Icons.expand_less
                              : Icons.info_outline,
                        ),
                        label: Text(
                          isExplanationExpanded
                              ? 'HIDE DETAILS'
                              : 'WHY THIS PICK?',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (isExplanationExpanded) explanationPanel,
            ],
          ),
        ),
      ),
    );
  }
}
