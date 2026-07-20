import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../models/slip_selection.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

enum _StrikeoutView { all, over, under }

class StrikeoutProGoldScreen extends StatefulWidget {
  const StrikeoutProGoldScreen({super.key, required this.onSelect});

  final void Function(PropData prop, PickSide side) onSelect;

  @override
  State<StrikeoutProGoldScreen> createState() => _StrikeoutProGoldScreenState();
}

class _StrikeoutProGoldScreenState extends State<StrikeoutProGoldScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();
  var _view = _StrikeoutView.all;
  var _loading = true;
  String? _error;
  List<PropData> _props = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isStrikeout(PropData prop) {
    final value = [
      prop.market,
      prop.marketName,
      prop.statType,
      prop.category,
      prop.propType,
      prop.displayMarket,
      prop.marketKey,
    ].join(' ').toLowerCase();
    return prop.sport.toUpperCase() == 'MLB' &&
        (value.contains('strikeout') ||
            value.contains('pitcher k') ||
            value.trim() == 'ks');
  }

  PickSide _recommendedSide(PropData prop) {
    if (prop.projection != null && prop.line > 0) {
      return prop.projection! >= prop.line ? PickSide.over : PickSide.under;
    }
    final text = '${prop.recommendedSide} ${prop.pick} ${prop.pickText}'
        .toLowerCase();
    return text.contains('under') || text.contains('less')
        ? PickSide.under
        : PickSide.over;
  }

  double _edge(PropData prop) => prop.projection == null
      ? prop.edge.abs()
      : (prop.projection! - prop.line).abs();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final props = await _api.fetchProps(
        selectedSport: 'MLB',
        selectedCategory: 'strikeouts',
        sortBy: 'confidence',
        limit: 300,
      );
      var strikeouts = props.where(_isStrikeout).toList(growable: false);
      if (strikeouts.isEmpty) {
        final fallback = await _api.fetchProps(
          selectedSport: 'MLB',
          search: 'strikeout',
          sortBy: 'confidence',
          limit: 300,
        );
        strikeouts = fallback.where(_isStrikeout).toList(growable: false);
      }
      strikeouts.sort((a, b) {
        final confidence = b.confidence.compareTo(a.confidence);
        return confidence != 0 ? confidence : _edge(b).compareTo(_edge(a));
      });
      if (mounted) setState(() => _props = strikeouts);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PropData> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _props
        .where((prop) {
          final side = _recommendedSide(prop);
          final sideMatches =
              _view == _StrikeoutView.all ||
              (_view == _StrikeoutView.over && side == PickSide.over) ||
              (_view == _StrikeoutView.under && side == PickSide.under);
          final queryMatches =
              query.isEmpty ||
              '${prop.player} ${prop.matchup} ${prop.sportsbook}'
                  .toLowerCase()
                  .contains(query);
          return sideMatches && queryMatches;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _load,
      child: CustomScrollView(
        key: const ValueKey('strikeout-pro-gold'),
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverToBoxAdapter(child: _controls()),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(child: _errorState())
          else if (_visible.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No MLB pitcher strikeout lines are available right now.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = width >= 1050
                      ? 3
                      : width >= 650
                      ? 2
                      : 1;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 294,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _card(_visible[index]),
                      childCount: _visible.length,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    final modeled = _props.where((prop) => prop.projection != null).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2B2100), Color(0xFF0A1721)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold, width: 1.2),
      ),
      child: Wrap(
        spacing: 22,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sports_baseball, color: AppColors.gold),
                    SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        'STRIKEOUT PRO GOLD',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 7),
                Text(
                  'MLB pitcher strikeout over/under research ranked by the current live signal. Numeric model projections are shown only when supplied—never invented.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          _metric('LIVE LINES', '${_props.length}'),
          _metric('MODELED', '$modeled'),
          _metric('PRO ACCESS', 'GOLD'),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.gold,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );

  Widget _controls() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final view in _StrikeoutView.values)
          ChoiceChip(
            selected: _view == view,
            onSelected: (_) => setState(() => _view = view),
            label: Text(view.name.toUpperCase()),
          ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Pitcher, matchup, or book',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('REFRESH'),
        ),
      ],
    ),
  );

  Widget _card(PropData prop) {
    final side = _recommendedSide(prop);
    final projection = prop.projection;
    final delta = projection == null ? null : projection - prop.line;
    final sideText = side == PickSide.over ? 'OVER' : 'UNDER';
    final signalColor = side == PickSide.over
        ? const Color(0xFF56D38A)
        : const Color(0xFF6DB8FF);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08151F),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.borderGold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF2B2100),
                child: Icon(Icons.sports_baseball, color: AppColors.gold),
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
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${prop.matchup} • ${prop.sportsbook}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$sideText ${prop.line.toStringAsFixed(1)}',
                style: TextStyle(
                  color: signalColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _datum(
                  'MODEL',
                  projection == null
                      ? 'UNAVAILABLE'
                      : projection.toStringAsFixed(2),
                ),
              ),
              Expanded(child: _datum('LINE', prop.line.toStringAsFixed(1))),
              Expanded(child: _datum('CONFIDENCE', '${prop.confidence}%')),
              Expanded(
                child: _datum(
                  'EDGE',
                  delta == null
                      ? '${prop.edge.toStringAsFixed(1)}%'
                      : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} K',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('LINEUP ${prop.lineupStatus.toUpperCase()}'),
              _chip('INJURY ${prop.injuryStatus.toUpperCase()}'),
              if (prop.currentLine != 0 && prop.openingLine != 0)
                _chip('OPEN ${prop.openingLine.toStringAsFixed(1)}'),
            ],
          ),
          const Spacer(),
          Text(
            projection == null
                ? 'The feed has not supplied a numeric projection. The displayed side comes from the live recommendation and should be independently verified.'
                : 'Projection is ${delta!.abs().toStringAsFixed(2)} strikeouts ${delta >= 0 ? 'above' : 'below'} the posted line. Verify lineup and price before selecting.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => widget.onSelect(prop, side),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text('ADD $sideText TO ACTIVE SLIP'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _datum(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 7,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.gold.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 7,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.gold, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Unable to load strikeout lines.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: _load, child: const Text('RETRY')),
        ],
      ),
    ),
  );
}
