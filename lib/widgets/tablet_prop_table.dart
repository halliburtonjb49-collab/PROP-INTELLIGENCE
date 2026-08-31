import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../models/slip_selection.dart';
import '../services/prop_book_group.dart';
import '../theme/app_colors.dart' as app_colors;
import 'player_image_widget.dart';

typedef TabletPropSelectionCallback =
    void Function(PropData prop, PickSide side);

typedef TabletLineOptionsCallback = Future<void> Function(PropBookGroup group);

/// Dense comparison table used only for tablet-width prop boards.
///
/// MainDashboard and PropGrid still own loading, filtering, sorting and state.
/// This widget only changes presentation, so phone, tablet and desktop always
/// show the same live props and use the same active-slip callbacks.
class TabletPropTable extends StatefulWidget {
  const TabletPropTable({
    super.key,
    required this.groups,
    required this.selections,
    required this.onSelect,
    required this.onShowLineAlternatives,
    this.onOpenProp,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
  });

  final List<PropBookGroup> groups;
  final List<SlipSelection> selections;
  final TabletPropSelectionCallback onSelect;
  final TabletLineOptionsCallback onShowLineAlternatives;
  final ValueChanged<PropData>? onOpenProp;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;

  @override
  State<TabletPropTable> createState() => _TabletPropTableState();
}

class _TabletPropTableState extends State<TabletPropTable> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math
            .max(constraints.maxWidth, _TabletColumns.total)
            .toDouble();
        final scrollable = tableWidth > constraints.maxWidth;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF07131E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: app_colors.AppColors.borderGold,
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (scrollable) const _TabletScrollHint(),
                Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: scrollable,
                  trackVisibility: false,
                  interactive: true,
                  thickness: 6,
                  radius: const Radius.circular(999),
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _TabletTableHeader(),
                          for (
                            var index = 0;
                            index < widget.groups.length;
                            index++
                          )
                            _TabletPropRow(
                              key: ValueKey(
                                'tablet-prop-row-${widget.groups[index].groupId}',
                              ),
                              group: widget.groups[index],
                              selections: widget.selections,
                              onSelect: widget.onSelect,
                              onOpenProp: widget.onOpenProp,
                              onShowLineAlternatives:
                                  widget.onShowLineAlternatives,
                              alternateBackground: index.isOdd,
                            ),
                          if (widget.hasMore)
                            _TabletLoadMoreRow(
                              loading: widget.isLoadingMore,
                              onPressed: widget.onLoadMore,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TabletScrollHint extends StatelessWidget {
  const _TabletScrollHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: app_colors.AppColors.gold.withValues(alpha: .08),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_rounded, size: 16, color: app_colors.AppColors.gold),
          SizedBox(width: 7),
          Text(
            'SWIPE TABLE SIDEWAYS TO COMPARE EVERY COLUMN',
            style: TextStyle(
              color: app_colors.AppColors.gold,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _TabletColumns {
  // 960 logical pixels lets a landscape tablet show the complete grid while
  // keeping every action at a comfortable touch size. Portrait tablets can
  // swipe horizontally without changing the data or selection state.
  static const double player = 204;
  static const double market = 124;
  static const double line = 62;
  static const double model = 68;
  static const double edge = 72;
  static const double score = 76;
  static const double trend = 58;
  static const double bestLine = 112;
  static const double pick = 184;

  static const double total =
      player + market + line + model + edge + score + trend + bestLine + pick;
}

class _TabletTableHeader extends StatelessWidget {
  const _TabletTableHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('tablet-prop-table-header'),
      width: _TabletColumns.total,
      height: 48,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1C28), Color(0xFF08141E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(
            bottom: BorderSide(color: app_colors.AppColors.border),
          ),
        ),
        child: const Row(
          children: [
            _TabletHeaderCell(
              width: _TabletColumns.player,
              label: 'PLAYER / MATCHUP',
              alignment: Alignment.centerLeft,
            ),
            _TabletHeaderCell(width: _TabletColumns.market, label: 'MARKET'),
            _TabletHeaderCell(width: _TabletColumns.line, label: 'LINE'),
            _TabletHeaderCell(width: _TabletColumns.model, label: 'MODEL'),
            _TabletHeaderCell(width: _TabletColumns.edge, label: 'PI EDGE'),
            _TabletHeaderCell(
              width: _TabletColumns.score,
              label: 'PI SCORE',
              highlighted: true,
            ),
            _TabletHeaderCell(width: _TabletColumns.trend, label: 'TREND'),
            _TabletHeaderCell(
              width: _TabletColumns.bestLine,
              label: 'BEST LINE',
            ),
            _TabletHeaderCell(width: _TabletColumns.pick, label: 'PICK'),
          ],
        ),
      ),
    );
  }
}

class _TabletHeaderCell extends StatelessWidget {
  const _TabletHeaderCell({
    required this.width,
    required this.label,
    this.alignment = Alignment.center,
    this.highlighted = false,
  });

  final double width;
  final String label;
  final Alignment alignment;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: double.infinity,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlighted
                    ? app_colors.AppColors.gold
                    : app_colors.AppColors.silver,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .55,
              ),
            ),
          ),
          if (highlighted) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: app_colors.AppColors.gold,
            ),
          ],
        ],
      ),
    );
  }
}

class _TabletPropRow extends StatefulWidget {
  const _TabletPropRow({
    super.key,
    required this.group,
    required this.selections,
    required this.onSelect,
    required this.onOpenProp,
    required this.onShowLineAlternatives,
    required this.alternateBackground,
  });

  final PropBookGroup group;
  final List<SlipSelection> selections;
  final TabletPropSelectionCallback onSelect;
  final ValueChanged<PropData>? onOpenProp;
  final TabletLineOptionsCallback onShowLineAlternatives;
  final bool alternateBackground;

  @override
  State<_TabletPropRow> createState() => _TabletPropRowState();
}

class _TabletPropRowState extends State<_TabletPropRow> {
  bool _hovered = false;

  SlipSelection? get _selection {
    final ids = widget.group.variants.map((prop) => prop.id).toSet();
    for (final selection in widget.selections) {
      if (ids.contains(selection.prop.id)) return selection;
      if (widget.group.groupId.isNotEmpty &&
          selection.prop.propGroupId == widget.group.groupId) {
        return selection;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selection;
    final shown = selected?.prop ?? widget.group.representative;
    final selectedSide = selected?.side;
    final signedEdge = _signedEdge(shown);
    final score = _piScore(shown);
    final rowColor = selectedSide != null
        ? app_colors.AppColors.gold.withValues(alpha: .075)
        : _hovered
        ? const Color(0xFF0D2030)
        : widget.alternateBackground
        ? const Color(0xFF081722)
        : const Color(0xFF06131D);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        width: _TabletColumns.total,
        height: 88,
        decoration: BoxDecoration(
          color: rowColor,
          border: const Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
        ),
        foregroundDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: selectedSide == null
                  ? Colors.transparent
                  : app_colors.AppColors.gold,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            _PlayerCell(
              width: _TabletColumns.player,
              prop: shown,
              selected: selectedSide != null,
              onTap: widget.onOpenProp == null
                  ? null
                  : () => widget.onOpenProp!(shown),
            ),
            _TextCell(width: _TabletColumns.market, text: _marketLabel(shown)),
            _MetricCell(
              width: _TabletColumns.line,
              text: _formatNumber(_lineValue(shown)),
            ),
            _MetricCell(
              width: _TabletColumns.model,
              text: _formatNumber(shown.displayModelValue),
              secondary: shown.displayModelIsMarketBaseline ? 'BASE' : null,
            ),
            _MetricCell(
              width: _TabletColumns.edge,
              text: _formatSigned(signedEdge),
              foreground: signedEdge > 0
                  ? app_colors.AppColors.success
                  : signedEdge < 0
                  ? app_colors.AppColors.danger
                  : app_colors.AppColors.silver,
            ),
            _PiScoreCell(width: _TabletColumns.score, score: score),
            _TrendCell(width: _TabletColumns.trend, trend: _lineTrend(shown)),
            _BestLineCell(
              width: _TabletColumns.bestLine,
              group: widget.group,
              shown: shown,
              onShowLineAlternatives: widget.onShowLineAlternatives,
            ),
            _PickCell(
              width: _TabletColumns.pick,
              group: widget.group,
              shown: shown,
              selectedSide: selectedSide,
              onSelect: widget.onSelect,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCell extends StatelessWidget {
  const _PlayerCell({
    required this.width,
    required this.prop,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final PropData prop;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final team = _teamCode(prop.matchup);
    final content = Row(
      children: [
        SizedBox(
          width: 68,
          height: 68,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0D1B27),
                  border: Border.all(
                    color: selected
                        ? app_colors.AppColors.gold
                        : app_colors.AppColors.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: PlayerAvatarWidget(
                  imageUrl: prop.imagePath,
                  cacheIdentity: prop.canonicalPlayerId.trim().isNotEmpty
                      ? prop.canonicalPlayerId
                      : prop.playerId.trim().isNotEmpty
                      ? prop.playerId
                      : '${prop.sport}:${prop.player.toLowerCase()}',
                  player: prop.player,
                  sport: prop.sport,
                  radius: 30,
                  fallbackIcon: _sportIcon(prop.sport),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 1,
                child: Container(
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF091722),
                    border: Border.all(
                      color: app_colors.AppColors.gold.withValues(alpha: .75),
                    ),
                  ),
                  child: Text(
                    team,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      prop.player,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: app_colors.AppColors.gold,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                prop.matchup.trim().isEmpty ? prop.sport : prop.matchup,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: app_colors.AppColors.silver,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 11,
                    color: app_colors.AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      prop.localGameDateTimeDisplay.trim().isEmpty
                          ? 'TIME PENDING'
                          : prop.localGameDateTimeDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: app_colors.AppColors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return _CellFrame(
      width: width,
      alignment: Alignment.centerLeft,
      child: onTap == null
          ? content
          : Tooltip(
              message: 'Open ${prop.player} research',
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: content,
                ),
              ),
            ),
    );
  }
}

class _TextCell extends StatelessWidget {
  const _TextCell({required this.width, required this.text});

  final double width;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _CellFrame(
      width: width,
      child: Tooltip(
        message: text,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            height: 1.18,
          ),
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.width,
    required this.text,
    this.secondary,
    this.foreground = Colors.white,
  });

  final double width;
  final String text;
  final String? secondary;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return _CellFrame(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: foreground,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (secondary != null) ...[
            const SizedBox(height: 3),
            Text(
              secondary!,
              style: const TextStyle(
                color: app_colors.AppColors.textMuted,
                fontSize: 7,
                fontWeight: FontWeight.w900,
                letterSpacing: .35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PiScoreCell extends StatelessWidget {
  const _PiScoreCell({required this.width, required this.score});

  final double width;
  final int score;

  @override
  Widget build(BuildContext context) {
    return _CellFrame(
      width: width,
      child: Container(
        width: 54,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF0B1722),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: app_colors.AppColors.gold.withValues(alpha: .78),
          ),
          boxShadow: [
            BoxShadow(
              color: app_colors.AppColors.gold.withValues(alpha: .10),
              blurRadius: 9,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$score',
              style: const TextStyle(
                color: app_colors.AppColors.goldHighlight,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: .95,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'PI SCORE',
              style: TextStyle(
                color: app_colors.AppColors.gold,
                fontSize: 6.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TabletLineTrend { up, flat, down }

class _TrendCell extends StatelessWidget {
  const _TrendCell({required this.width, required this.trend});

  final double width;
  final _TabletLineTrend trend;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (trend) {
      _TabletLineTrend.up => (
        Icons.trending_up_rounded,
        app_colors.AppColors.success,
        'Line moved up',
      ),
      _TabletLineTrend.down => (
        Icons.trending_down_rounded,
        app_colors.AppColors.danger,
        'Line moved down',
      ),
      _TabletLineTrend.flat => (
        Icons.remove_rounded,
        app_colors.AppColors.gold,
        'Line unchanged',
      ),
    };

    return _CellFrame(
      width: width,
      child: Tooltip(
        message: label,
        child: Icon(icon, color: color, size: 27),
      ),
    );
  }
}

class _BestLineCell extends StatelessWidget {
  const _BestLineCell({
    required this.width,
    required this.group,
    required this.shown,
    required this.onShowLineAlternatives,
  });

  final double width;
  final PropBookGroup group;
  final PropData shown;
  final TabletLineOptionsCallback onShowLineAlternatives;

  @override
  Widget build(BuildContext context) {
    final advised = _advisedSide(shown) ?? PickSide.over;
    final best = _bestVariantForSide(group, advised);

    return _CellFrame(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatNumber(_lineValue(best)),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          _SportsbookBadge(sportsbook: best.sportsbook),
          if (group.hasAlternatives) ...[
            const SizedBox(height: 3),
            InkWell(
              key: ValueKey('tablet-line-options-${group.groupId}'),
              onTap: () async {
                await onShowLineAlternatives(group);
              },
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  '${group.bookCount} OPTIONS',
                  style: const TextStyle(
                    color: app_colors.AppColors.gold,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .25,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SportsbookBadge extends StatelessWidget {
  const _SportsbookBadge({required this.sportsbook});

  final String sportsbook;

  @override
  Widget build(BuildContext context) {
    final normalized = sportsbook.trim().toUpperCase();
    final (icon, color, label) = switch (normalized) {
      String value when value.contains('PRIZEPICKS') => (
        Icons.bolt_rounded,
        const Color(0xFF9A55FF),
        'PRIZEPICKS',
      ),
      String value when value.contains('FANDUEL') => (
        Icons.security_rounded,
        const Color(0xFF4AA8FF),
        'FANDUEL',
      ),
      String value
          when value.contains('DRAFTKINGS') || value.contains('PICK6') =>
        (
          Icons.emoji_events_rounded,
          const Color(0xFF55C65A),
          value.contains('PICK6') ? 'PICK6' : 'DRAFTKINGS',
        ),
      String value when value.contains('CAESARS') => (
        Icons.workspace_premium_rounded,
        app_colors.AppColors.gold,
        'CAESARS',
      ),
      String value when value.contains('UNDERDOG') => (
        Icons.pets_rounded,
        const Color(0xFFFFB247),
        'UNDERDOG',
      ),
      _ => (
        Icons.storefront_rounded,
        app_colors.AppColors.silver,
        normalized.isEmpty ? 'BOOK' : normalized,
      ),
    };

    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 82),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 7.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickCell extends StatelessWidget {
  const _PickCell({
    required this.width,
    required this.group,
    required this.shown,
    required this.selectedSide,
    required this.onSelect,
  });

  final double width;
  final PropBookGroup group;
  final PropData shown;
  final PickSide? selectedSide;
  final TabletPropSelectionCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final advisedSide = _advisedSide(shown);
    final underProp = _bestVariantForSide(group, PickSide.under);
    final overProp = _bestVariantForSide(group, PickSide.over);

    return _CellFrame(
      width: width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TabletPickButton(
            key: ValueKey('tablet-under-${shown.id}'),
            label: 'UNDER',
            odds: _formatOdds(underProp.underOdds),
            selected: selectedSide == PickSide.under,
            advised: advisedSide == PickSide.under,
            enabled: underProp.isSelectable && !underProp.dataStale,
            onPressed: () => onSelect(underProp, PickSide.under),
          ),
          const SizedBox(width: 7),
          _TabletPickButton(
            key: ValueKey('tablet-over-${shown.id}'),
            label: 'OVER',
            odds: _formatOdds(overProp.overOdds),
            selected: selectedSide == PickSide.over,
            advised: advisedSide == PickSide.over,
            enabled: overProp.isSelectable && !overProp.dataStale,
            onPressed: () => onSelect(overProp, PickSide.over),
          ),
        ],
      ),
    );
  }
}

class _TabletPickButton extends StatelessWidget {
  const _TabletPickButton({
    super.key,
    required this.label,
    required this.odds,
    required this.selected,
    required this.advised,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String odds;
  final bool selected;
  final bool advised;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? app_colors.AppColors.bgBase
        : enabled
        ? Colors.white
        : app_colors.AppColors.textMuted;

    return Tooltip(
      message: enabled ? '$label $odds' : 'Selection closed or line is stale',
      child: SizedBox(
        width: 76,
        height: 48,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            foregroundColor: foreground,
            backgroundColor: selected
                ? app_colors.AppColors.goldHighlight
                : advised
                ? app_colors.AppColors.gold.withValues(alpha: .10)
                : const Color(0xFF0A1722),
            disabledForegroundColor: app_colors.AppColors.textMuted,
            disabledBackgroundColor: const Color(0xFF08111A),
            side: BorderSide(
              color: selected
                  ? app_colors.AppColors.goldHighlight
                  : advised
                  ? app_colors.AppColors.gold
                  : app_colors.AppColors.border,
              width: selected || advised ? 1.25 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      odds,
                      maxLines: 1,
                      style: TextStyle(
                        color: foreground.withValues(alpha: .88),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 3),
                const Icon(Icons.check_circle_rounded, size: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CellFrame extends StatelessWidget {
  const _CellFrame({
    required this.width,
    required this.child,
    this.alignment = Alignment.center,
  });

  final double width;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: double.infinity,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: child,
    );
  }
}

class _TabletLoadMoreRow extends StatelessWidget {
  const _TabletLoadMoreRow({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _TabletColumns.total,
      height: 66,
      child: Center(
        child: OutlinedButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded),
          label: Text(loading ? 'LOADING MORE' : 'LOAD MORE PROPS'),
        ),
      ),
    );
  }
}

String _marketLabel(PropData prop) {
  final candidates = <String>[
    prop.displayMarket,
    prop.marketName,
    prop.statType,
    prop.category,
    prop.propType,
    prop.market,
  ];
  for (final candidate in candidates) {
    final value = candidate.trim();
    if (value.isNotEmpty &&
        value.toLowerCase() != 'other' &&
        value.toLowerCase() != 'unknown') {
      return value;
    }
  }
  return 'PLAYER PROP';
}

IconData _sportIcon(String sport) {
  final normalized = sport.trim().toUpperCase();
  if (normalized.contains('MLB') || normalized.contains('BASEBALL')) {
    return Icons.sports_baseball_rounded;
  }
  if (normalized.contains('NFL') || normalized.contains('FOOTBALL')) {
    return Icons.sports_football_rounded;
  }
  if (normalized.contains('NHL') || normalized.contains('HOCKEY')) {
    return Icons.sports_hockey_rounded;
  }
  if (normalized.contains('SOCCER')) return Icons.sports_soccer_rounded;
  if (normalized.contains('TENNIS')) return Icons.sports_tennis_rounded;
  if (normalized.contains('UFC') || normalized.contains('MMA')) {
    return Icons.sports_mma_rounded;
  }
  return Icons.sports_basketball_rounded;
}

String _teamCode(String matchup) {
  final parts = matchup
      .toUpperCase()
      .replaceAll('@', ' ')
      .replaceAll('VS.', ' ')
      .replaceAll('VS', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.length >= 2)
      .toList(growable: false);
  if (parts.isEmpty) return 'PI';
  final value = parts.first;
  return value.substring(0, value.length < 3 ? value.length : 3);
}

PickSide? _advisedSide(PropData prop) {
  final side = prop.proSuggestedSide?.trim().toUpperCase();
  if (side == 'OVER') return PickSide.over;
  if (side == 'UNDER') return PickSide.under;
  return null;
}

PropData _bestVariantForSide(PropBookGroup group, PickSide side) {
  if (group.variants.isEmpty) return group.representative;
  final current = group.variants
      .where((prop) => prop.isSelectable && !prop.dataStale)
      .toList(growable: true);
  final pool = current.isEmpty ? List<PropData>.from(group.variants) : current;
  pool.sort((left, right) {
    final lineOrder = side == PickSide.over
        ? _lineValue(left).compareTo(_lineValue(right))
        : _lineValue(right).compareTo(_lineValue(left));
    if (lineOrder != 0) return lineOrder;
    final leftPrice = side == PickSide.over ? left.overOdds : left.underOdds;
    final rightPrice = side == PickSide.over ? right.overOdds : right.underOdds;
    return _priceRank(rightPrice).compareTo(_priceRank(leftPrice));
  });
  return pool.first;
}

double _lineValue(PropData prop) =>
    prop.currentLine != 0 ? prop.currentLine : prop.line;

double _priceRank(double? raw) {
  if (raw == null) return double.negativeInfinity;
  if (raw > 1 && raw < 20) return raw;
  if (raw >= 100) return 1 + raw / 100;
  if (raw <= -100) return 1 + 100 / raw.abs();
  return raw;
}

double _signedEdge(PropData prop) {
  final modelDelta = prop.displayModelValue - _lineValue(prop);
  if (!prop.displayModelIsMarketBaseline && modelDelta.abs() > .0001) {
    return modelDelta;
  }
  final magnitude = prop.calculatedEdge ?? 0;
  return _advisedSide(prop) == PickSide.under ? -magnitude : magnitude;
}

int _piScore(PropData prop) {
  if (prop.piTrustScore > 0) {
    return prop.piTrustScore.clamp(0, 100).toInt();
  }
  return (prop.displayConfidenceRating ?? prop.confidence)
      .clamp(0, 100)
      .toInt();
}

_TabletLineTrend _lineTrend(PropData prop) {
  final opening = prop.openingLine;
  final current = _lineValue(prop);
  if (opening == 0 || (current - opening).abs() < .001) {
    return _TabletLineTrend.flat;
  }
  return current > opening ? _TabletLineTrend.up : _TabletLineTrend.down;
}

String _formatNumber(double value) {
  if (!value.isFinite) return '-';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _formatSigned(double value) {
  if (!value.isFinite || value.abs() < .001) return '0.0';
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}';
}

String _formatOdds(double? raw) {
  if (raw == null || !raw.isFinite || raw == 0) return '-110';
  int american;
  if (raw.abs() >= 100) {
    american = raw.round();
  } else if (raw > 1 && raw < 2) {
    american = (-100 / (raw - 1)).round();
  } else if (raw >= 2 && raw < 20) {
    american = ((raw - 1) * 100).round();
  } else {
    american = raw.round();
  }
  return american > 0 ? '+$american' : '$american';
}
