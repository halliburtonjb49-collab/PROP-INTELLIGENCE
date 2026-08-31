import 'package:flutter/material.dart';

import '../theme/app_colors.dart' as app_colors;

/// High-fidelity tablet controls for the PROP INTELLIGENCE market board.
///
/// The dashboard owns every filter and callback. This widget only arranges
/// those existing controls to match the wide tablet design.
class TabletMarketToolbar extends StatelessWidget {
  const TabletMarketToolbar({
    super.key,
    required this.selectedSport,
    required this.onSelectSport,
    required this.selectedSite,
    required this.sitePropCount,
    required this.onChangeSite,
    required this.searchController,
    required this.onSearchChanged,
    required this.onOpenFilters,
    required this.selectedQuickFilter,
    required this.onSelectQuickFilter,
    required this.playablePropCount,
    required this.bestPiScore,
  });

  final String selectedSport;
  final ValueChanged<String> onSelectSport;
  final String selectedSite;
  final int sitePropCount;
  final VoidCallback onChangeSite;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenFilters;
  final String selectedQuickFilter;
  final ValueChanged<String> onSelectQuickFilter;
  final int playablePropCount;
  final int bestPiScore;

  static const List<String> sports = <String>[
    'ALL',
    'MLB',
    'NFL',
    'WNBA',
    'NBA',
  ];

  static const List<String> quickFilters = <String>[
    'TOP PI PICKS',
    'TRENDING',
    'NEW LINES',
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        return Container(
          key: const ValueKey('tablet-market-toolbar'),
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            color: const Color(0xF207111B),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: app_colors.AppColors.borderGold),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SportTabs(
                selectedSport: selectedSport,
                onSelectSport: onSelectSport,
                compact: compact,
              ),
              SizedBox(height: compact ? 9 : 11),
              if (compact) ...[
                _ProviderSelector(
                  site: selectedSite,
                  propCount: sitePropCount,
                  onPressed: onChangeSite,
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _SearchField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                      ),
                    ),
                    const SizedBox(width: 9),
                    _FilterButton(compact: true, onPressed: onOpenFilters),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      flex: 8,
                      child: _ProviderSelector(
                        site: selectedSite,
                        propCount: sitePropCount,
                        onPressed: onChangeSite,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      flex: 11,
                      child: _SearchField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                      ),
                    ),
                    const SizedBox(width: 11),
                    _FilterButton(compact: false, onPressed: onOpenFilters),
                  ],
                ),
              SizedBox(height: compact ? 9 : 11),
              if (compact) ...[
                _QuickFilterTabs(
                  selected: selectedQuickFilter,
                  onSelected: onSelectQuickFilter,
                  compact: true,
                ),
                const SizedBox(height: 9),
                _BoardStats(
                  playablePropCount: playablePropCount,
                  bestPiScore: bestPiScore,
                  compact: true,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      flex: 11,
                      child: _QuickFilterTabs(
                        selected: selectedQuickFilter,
                        onSelected: onSelectQuickFilter,
                        compact: false,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      flex: 9,
                      child: _BoardStats(
                        playablePropCount: playablePropCount,
                        bestPiScore: bestPiScore,
                        compact: false,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SportTabs extends StatelessWidget {
  const _SportTabs({
    required this.selectedSport,
    required this.onSelectSport,
    required this.compact,
  });

  final String selectedSport;
  final ValueChanged<String> onSelectSport;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalized = selectedSport.trim().toUpperCase();
    return SizedBox(
      height: compact ? 48 : 54,
      child: Row(
        children: [
          for (
            var index = 0;
            index < TabletMarketToolbar.sports.length;
            index++
          ) ...[
            if (index > 0) SizedBox(width: compact ? 7 : 10),
            Expanded(
              child: _SportTab(
                label: TabletMarketToolbar.sports[index],
                selected: normalized == TabletMarketToolbar.sports[index],
                onPressed: () =>
                    onSelectSport(TabletMarketToolbar.sports[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SportTab extends StatelessWidget {
  const _SportTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label sport',
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? app_colors.AppColors.goldHighlight
                : app_colors.AppColors.border,
          ),
        ),
        child: InkWell(
          key: ValueKey('tablet-sport-$label'),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [Color(0xFFFFE89D), Color(0xFFD4AF37)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFF101D29), Color(0xFF07131D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? app_colors.AppColors.bgBase
                      : app_colors.AppColors.silver,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .45,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderSelector extends StatelessWidget {
  const _ProviderSelector({
    required this.site,
    required this.propCount,
    required this.onPressed,
  });

  final String site;
  final int propCount;
  final VoidCallback onPressed;

  String get displayName {
    final value = site.trim().toUpperCase();
    return switch (value) {
      'ALL' => 'ALL PROP SITES',
      'PICK6' => 'DRAFTKINGS PICK6',
      'HARDROCKBET' => 'HARD ROCK BET',
      _ => value.isEmpty ? 'SELECT PROP SITE' : value,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF081620),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: app_colors.AppColors.gold.withValues(alpha: .58),
        ),
      ),
      child: InkWell(
        key: const ValueKey('tablet-provider-selector'),
        onTap: onPressed,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _ProviderMark(site: site),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .35,
                        ),
                      ),
                      if (propCount > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '$propCount LIVE PROPS',
                          style: const TextStyle(
                            color: app_colors.AppColors.textMuted,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'CHANGE',
                  style: TextStyle(
                    color: app_colors.AppColors.gold,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: app_colors.AppColors.gold,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderMark extends StatelessWidget {
  const _ProviderMark({required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    final normalized = site.trim().toUpperCase();
    final (letter, color, icon) = switch (normalized) {
      'PRIZEPICKS' => ('P', const Color(0xFF8F45FF), Icons.bolt_rounded),
      'UNDERDOG' => ('U', const Color(0xFFFFA23A), Icons.pets_rounded),
      'FANDUEL' => ('F', const Color(0xFF4AA8FF), Icons.security_rounded),
      'PICK6' || 'DRAFTKINGS' => (
        'D',
        const Color(0xFF58C95B),
        Icons.emoji_events_rounded,
      ),
      'CAESARS' => (
        'C',
        app_colors.AppColors.gold,
        Icons.workspace_premium_rounded,
      ),
      _ => ('PI', app_colors.AppColors.silver, Icons.storefront_rounded),
    };

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: .95), color.withValues(alpha: .45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .24), blurRadius: 10),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: .28), size: 29),
          Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF081620),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      alignment: Alignment.center,
      child: TextField(
        key: const ValueKey('tablet-search-field'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 7, right: 7),
            child: Icon(
              Icons.search_rounded,
              color: app_colors.AppColors.silver,
              size: 27,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 52),
          hintText: 'Search player or market',
          hintStyle: const TextStyle(
            color: app_colors.AppColors.textMuted,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: app_colors.AppColors.textMuted,
                    size: 19,
                  ),
                ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 64 : 116,
      height: 64,
      child: OutlinedButton(
        key: const ValueKey('tablet-filter-button'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: app_colors.AppColors.gold,
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12),
          side: const BorderSide(color: app_colors.AppColors.gold, width: 1.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: compact
            ? const Icon(Icons.tune_rounded, size: 24)
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune_rounded, size: 21),
                  SizedBox(width: 8),
                  Text(
                    'FILTERS',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .45,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _QuickFilterTabs extends StatelessWidget {
  const _QuickFilterTabs({
    required this.selected,
    required this.onSelected,
    required this.compact,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalized = selected.trim().toUpperCase();
    return Container(
      height: compact ? 56 : 60,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF081620),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: app_colors.AppColors.border),
      ),
      child: Row(
        children: [
          for (
            var index = 0;
            index < TabletMarketToolbar.quickFilters.length;
            index++
          )
            Expanded(
              child: _QuickFilterTab(
                label: TabletMarketToolbar.quickFilters[index],
                selected: normalized == TabletMarketToolbar.quickFilters[index],
                last: index == TabletMarketToolbar.quickFilters.length - 1,
                onPressed: () =>
                    onSelected(TabletMarketToolbar.quickFilters[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickFilterTab extends StatelessWidget {
  const _QuickFilterTab({
    required this.label,
    required this.selected,
    required this.last,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool last;
  final VoidCallback onPressed;

  IconData get icon => switch (label) {
    'TOP PI PICKS' => Icons.star_rounded,
    'TRENDING' => Icons.trending_up_rounded,
    _ => Icons.article_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? app_colors.AppColors.gold : Colors.transparent,
        child: InkWell(
          key: ValueKey('tablet-quick-filter-$label'),
          onTap: onPressed,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: last
                    ? BorderSide.none
                    : const BorderSide(color: app_colors.AppColors.border),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? app_colors.AppColors.bgBase
                      : app_colors.AppColors.silver,
                  size: 19,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: selected
                            ? app_colors.AppColors.bgBase
                            : app_colors.AppColors.silver,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardStats extends StatelessWidget {
  const _BoardStats({
    required this.playablePropCount,
    required this.bestPiScore,
    required this.compact,
  });

  final int playablePropCount;
  final int bestPiScore;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 56 : 60,
      padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 15),
      decoration: BoxDecoration(
        color: const Color(0xFF081620),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: app_colors.AppColors.gold.withValues(alpha: .42),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.bar_chart_rounded,
            color: app_colors.AppColors.silver,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            '$playablePropCount',
            style: const TextStyle(
              color: app_colors.AppColors.goldHighlight,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'PLAYABLE PROPS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: app_colors.AppColors.silver,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: .45,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: app_colors.AppColors.gold.withValues(alpha: .35),
          ),
          const Icon(
            Icons.adjust_rounded,
            color: app_colors.AppColors.silver,
            size: 22,
          ),
          const SizedBox(width: 7),
          const Flexible(
            child: Text(
              'BEST PI SCORE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: app_colors.AppColors.silver,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: .4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$bestPiScore',
            style: const TextStyle(
              color: app_colors.AppColors.goldHighlight,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
