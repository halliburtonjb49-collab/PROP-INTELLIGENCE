import 'dart:async';

import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../models/slip_selection.dart';
import '../services/api_service.dart';
import '../services/player_image_resolver.dart';
import '../theme/app_colors.dart';
import '../widgets/player_image_widget.dart';

import '../theme/app_colors.dart' as brand_colors;

enum _StrikeoutView { all, over, under }

class StrikeoutProGoldScreen extends StatefulWidget {
  const StrikeoutProGoldScreen({
    super.key,
    required this.onSelect,
    this.onPropsRefreshed,
    this.onPropsExpired,
  });

  final void Function(PropData prop, PickSide side) onSelect;
  final Future<void> Function(List<PropData> props)? onPropsRefreshed;
  final Future<void> Function(Set<String> propIds)? onPropsExpired;

  @override
  State<StrikeoutProGoldScreen> createState() => _StrikeoutProGoldScreenState();
}

class _StrikeoutProGoldScreenState extends State<StrikeoutProGoldScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();
  var _view = _StrikeoutView.all;
  String? _selectedSite;
  var _loading = true;
  String? _error;
  List<PropData> _props = const [];
  final Map<String, PickSide> _selectedSides = {};
  Timer? _refreshTimer;
  Timer? _expiryTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_refreshLive()),
    );
    _expiryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final expired = {
        for (final prop in _props)
          if (!prop.isSelectable && prop.id.isNotEmpty) prop.id,
      };
      if (expired.isEmpty) return;
      setState(() {
        _props = _props
            .where((prop) => !expired.contains(prop.id))
            .toList(growable: false);
        _selectedSides.removeWhere((id, _) => expired.contains(id));
      });
      unawaited(widget.onPropsExpired?.call(expired));
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _refreshTimer?.cancel();
    _expiryTimer?.cancel();
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

  PickSide? _recommendedSide(PropData prop) {
    final side = prop.proSuggestedSide;
    if (side == 'OVER') return PickSide.over;
    if (side == 'UNDER') return PickSide.under;
    return null;
  }

  String _signalLabel(PropData prop, PickSide? side) {
    if (side == null) return 'SIGNAL';
    if (prop.proSuggestionUsesModel) return 'MODEL PICK';
    if (prop.proSuggestionUsesHistoricalStats) return 'STATS LEAN';
    return 'SYSTEM LEAN';
  }

  double _edge(PropData prop) => prop.calculatedEdge ?? prop.edge.abs();

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
      final expiredIds = {
        for (final prop in [..._props, ...strikeouts])
          if (!prop.isSelectable && prop.id.isNotEmpty) prop.id,
      };
      strikeouts = strikeouts
          .where((prop) => prop.isSelectable)
          .toList(growable: false);
      strikeouts.sort((a, b) {
        DateTime? start(PropData prop) => DateTime.tryParse(
          prop.startTimeUtc.isNotEmpty ? prop.startTimeUtc : prop.gameStartTime,
        );
        final left = start(a);
        final right = start(b);
        if (left == null && right == null) return a.player.compareTo(b.player);
        if (left == null) return 1;
        if (right == null) return -1;
        final time = left.compareTo(right);
        if (time != 0) return time;
        final confidence = b.confidence.compareTo(a.confidence);
        return confidence != 0 ? confidence : _edge(b).compareTo(_edge(a));
      });
      if (expiredIds.isNotEmpty) {
        await widget.onPropsExpired?.call(expiredIds);
      }
      if (mounted) {
        setState(() {
          _props = strikeouts;
          if (_selectedSite != null && !_sites.contains(_selectedSite)) {
            _selectedSite = null;
          }
        });
      }
      await widget.onPropsRefreshed?.call(strikeouts);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshLive() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _load();
    } finally {
      _refreshing = false;
    }
  }

  List<PropData> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _props
        .where((prop) {
          if (!prop.isSelectable) return false;
          final side = _recommendedSide(prop);
          final sideMatches =
              _view == _StrikeoutView.all ||
              (_view == _StrikeoutView.over && side == PickSide.over) ||
              (_view == _StrikeoutView.under && side == PickSide.under);
          final siteMatches =
              _selectedSite == null ||
              prop.sportsbook.trim().toUpperCase() == _selectedSite;
          final queryMatches =
              query.isEmpty ||
              '${prop.player} ${prop.matchup} ${prop.sportsbook}'
                  .toLowerCase()
                  .contains(query);
          return sideMatches && siteMatches && queryMatches;
        })
        .toList(growable: false);
  }

  List<String> get _sites {
    final sites = _props
        .map((prop) => prop.sportsbook.trim().toUpperCase())
        .where((site) => site.isNotEmpty)
        .toSet()
        .toList();
    sites.sort();
    return sites;
  }

  int _siteCount(String site) => _props
      .where((prop) => prop.sportsbook.trim().toUpperCase() == site)
      .length;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: _load,
      child: CustomScrollView(
        key: const ValueKey('strikeout-pro-gold'),
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverToBoxAdapter(child: _siteTabs()),
          SliverToBoxAdapter(child: _controls()),
          SliverToBoxAdapter(child: _methodology()),
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
                      mainAxisExtent: 410,
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
          onPressed: _refreshLive,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('REFRESH'),
        ),
      ],
    ),
  );

  Widget _siteTabs() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PROP SITES',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _siteTab(
                label: 'ALL STRIKEOUT PROPS',
                count: _props.length,
                selected: _selectedSite == null,
                onTap: () => setState(() => _selectedSite = null),
              ),
              for (final site in _sites) ...[
                const SizedBox(width: 8),
                _siteTab(
                  label: site,
                  count: _siteCount(site),
                  selected: _selectedSite == site,
                  onTap: () => setState(() => _selectedSite = site),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _siteTab({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) => OutlinedButton(
    key: ValueKey('strikeout-site-$label'),
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: selected
          ? brand_colors.AppColors.sidebar
          : AppColors.gold,
      backgroundColor: selected
          ? AppColors.gold
          : brand_colors.AppColors.sidebar,
      side: BorderSide(
        color: selected ? AppColors.gold : AppColors.borderGold,
        width: selected ? 1.5 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    child: Text(
      '$label  $count',
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );

  Widget _methodology() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
    child: Material(
      color: brand_colors.AppColors.sidebar,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ExpansionTile(
        key: const ValueKey('strikeout-model-methodology'),
        iconColor: AppColors.gold,
        collapsedIconColor: AppColors.gold,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        leading: const Icon(
          Icons.model_training_rounded,
          color: AppColors.gold,
        ),
        title: const Text(
          'MODEL METHODOLOGY & READINESS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: .5,
          ),
        ),
        subtitle: const Text(
          'How the research engine is being built, tested, and promoted to production',
          style: TextStyle(color: AppColors.textMuted, fontSize: 9),
        ),
        children: [
          const _MethodologyNotice(),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cardWidth = width >= 1000
                  ? (width - 36) / 4
                  : width >= 620
                  ? (width - 12) / 2
                  : width;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ModelCard(
                    width: cardWidth,
                    name: 'XGBOOST + LIGHTGBM',
                    status: 'CANDIDATE ENSEMBLE',
                    icon: Icons.account_tree_outlined,
                    description:
                        'Primary candidates for non-linear tabular relationships, missing-value tolerance, and auditable feature importance.',
                  ),
                  _ModelCard(
                    width: cardWidth,
                    name: 'POISSON / COUNT MODEL',
                    status: 'CANDIDATE DISTRIBUTION',
                    icon: Icons.functions_rounded,
                    description:
                        'Produces an exact strikeout-count distribution so each posted line can be evaluated as an Over or Under probability.',
                  ),
                  _ModelCard(
                    width: cardWidth,
                    name: 'RANDOM FOREST',
                    status: 'BASELINE CHALLENGER',
                    icon: Icons.park_outlined,
                    description:
                        'A durable baseline used to challenge boosted-tree results and expose overfitting before deployment.',
                  ),
                  _ModelCard(
                    width: cardWidth,
                    name: 'LSTM SEQUENCE MODEL',
                    status: 'RESEARCH ONLY',
                    icon: Icons.timeline_rounded,
                    description:
                        'A future sequential model for form, workload, and fatigue. It requires substantially more history and validation.',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 720;
              final features = _MethodologyPanel(
                icon: Icons.tune_rounded,
                title: 'FEATURE ENGINEERING — THE 80%',
                items: const [
                  'Rolling pitcher form: 3-game and 5-game K%, whiff rate, pitch count, and velocity movement',
                  'Opponent lineup strikeout rate versus pitcher handedness and projected plate appearances',
                  'Rest, travel, workload, park, weather, and confirmed lineup context',
                  'Home-plate umpire tendency and sportsbook line/price movement',
                ],
              );
              final stack = _MethodologyPanel(
                icon: Icons.code_rounded,
                title: 'PYTHON MODEL STACK',
                items: const [
                  'pandas for validated feature tables and reproducible transformations',
                  'scikit-learn for time-aware splits, baselines, calibration, and evaluation',
                  'xgboost / lightgbm for boosted-tree candidate models',
                  'statsmodels or PyMC for count distributions and uncertainty',
                  'TensorFlow or PyTorch only if an LSTM beats simpler models out of sample',
                ],
              );
              if (stacked) {
                return Column(
                  children: [features, const SizedBox(height: 12), stack],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: features),
                  const SizedBox(width: 12),
                  Expanded(child: stack),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _card(PropData prop) {
    final systemSide = _recommendedSide(prop);
    final selectedSide = _selectedSides[prop.id];
    final projection = prop.projection;
    final delta = projection == null ? null : projection - prop.line;
    final isExpired = !prop.isSelectable;
    final sideText = systemSide == null
        ? 'NO PICK'
        : systemSide == PickSide.over
        ? 'OVER'
        : 'UNDER';
    final signalColor = systemSide == null
        ? AppColors.textMuted
        : systemSide == PickSide.over
        ? brand_colors.AppColors.success
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
              Container(
                key: ValueKey('strikeout-player-photo-${prop.id}'),
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2B2100),
                  border: Border.all(color: AppColors.gold),
                ),
                child: PlayerAvatarWidget(
                  imageUrl: resolvePlayerImagePath(prop.imagePath),
                  radius: 26,
                  fallbackIcon: Icons.person_rounded,
                ),
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
              Container(
                key: const ValueKey('strikeout-pro-pick'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: signalColor.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: signalColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _signalLabel(prop, systemSide),
                      style: TextStyle(
                        color: signalColor,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sideText ${prop.line.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: signalColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      prop.proSuggestionUsesModel
                          ? 'VERIFIED MODEL'
                          : prop.proSuggestionUsesHistoricalStats
                          ? 'HISTORICAL BASELINE'
                          : prop.proSuggestionUsesMarket
                          ? 'SPORTSBOOK PRICING'
                          : 'LIVE FEED',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 6.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: AppColors.gold,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  prop.localGameDateTimeDisplay.isEmpty
                      ? 'GAME TIME PENDING'
                      : prop.localGameDateTimeDisplay,
                  key: ValueKey('strikeout-game-time-${prop.id}'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (prop.lastUpdatedLocalDisplay.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'UPDATED ${prop.lastUpdatedLocalDisplay}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 7,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.gold,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SPORT: ${prop.sport.trim().isEmpty ? 'MLB' : prop.sport.toUpperCase()}  •  '
                    'PROP SITE: ${prop.sportsbook.trim().isEmpty ? 'UNKNOWN' : prop.sportsbook.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _datum(
                  'MODEL',
                  prop.displayModelValue.toStringAsFixed(2),
                ),
              ),
              Expanded(child: _datum('LINE', prop.line.toStringAsFixed(1))),
              Expanded(child: _datum('CONFIDENCE', '${prop.confidence}%')),
              Expanded(
                child: _datum(
                  'EDGE',
                  delta == null
                      ? '--'
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
              _chip(
                prop.injuryStatus.trim().toLowerCase() == 'unknown'
                    ? 'INJURY REPORT UNAVAILABLE'
                    : 'INJURY ${prop.injuryStatus.toUpperCase()}',
              ),
              if (prop.displayModelIsMarketBaseline) _chip('MODEL: BASELINE'),
              if (prop.currentLine != 0 && prop.openingLine != 0)
                _chip('OPEN ${prop.openingLine.toStringAsFixed(1)}'),
            ],
          ),
          const Spacer(),
          if (isExpired)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: .5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock, color: Colors.red, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      prop.gameStatus.toLowerCase() == 'live' ||
                              prop.gameStatus.toLowerCase() == 'in progress'
                          ? 'GAME IS LIVE — No new selections allowed'
                          : 'GAME HAS STARTED — No new selections allowed',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              systemSide == null
                  ? 'No valid Over or Under signal is available for this line. The app will not manufacture a pick.'
                  : prop.proSuggestionUsesMarket
                  ? 'Informational market lean based on unequal Over and Under prices. This is not a model pick or claimed edge.'
                  : !prop.proSuggestionUsesModel
                  ? 'Informational stats lean based on recent historical results. It is not a validated top model pick.'
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
          if (!isExpired)
            Row(
              children: [
                Expanded(
                  child: _sideButton(
                    prop: prop,
                    side: PickSide.over,
                    selected: selectedSide == PickSide.over,
                    systemPick: systemSide == PickSide.over,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sideButton(
                    prop: prop,
                    side: PickSide.under,
                    selected: selectedSide == PickSide.under,
                    systemPick: systemSide == PickSide.under,
                  ),
                ),
              ],
            ),
          if (!isExpired) const SizedBox(height: 8),
          if (!isExpired)
            const Text(
              'Tap OVER or UNDER to add it to the active slip. Tap the selected side again to remove it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 8),
            ),
        ],
      ),
    );
  }

  Widget _sideButton({
    required PropData prop,
    required PickSide side,
    required bool selected,
    required bool systemPick,
  }) {
    final label = side == PickSide.over ? 'OVER' : 'UNDER';
    return OutlinedButton(
      key: ValueKey('strikeout-${side.name}-${prop.id}'),
      onPressed: () {
        setState(() {
          if (_selectedSides[prop.id] == side) {
            _selectedSides.remove(prop.id);
          } else {
            _selectedSides[prop.id] = side;
          }
        });
        widget.onSelect(prop, side);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: selected
            ? brand_colors.AppColors.sidebar
            : Colors.white,
        backgroundColor: selected ? AppColors.gold : Colors.transparent,
        side: BorderSide(color: selected ? AppColors.gold : AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      child: Text(
        systemPick ? '$label • SYSTEM PICK' : label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
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

class _MethodologyNotice extends StatelessWidget {
  const _MethodologyNotice();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.gold.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.gold.withValues(alpha: .45)),
    ),
    child: const Text(
      'REALITY CHECK  •  No model guarantees results. At standard -110 pricing, the mathematical break-even win rate is approximately 52.4% before other costs. Sustained performance above that threshold must be demonstrated with time-ordered, out-of-sample testing—not a small winning streak. Candidate models remain inactive until they beat the baseline, calibrate reliably, and survive leakage checks.',
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 9.5,
        height: 1.45,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.width,
    required this.name,
    required this.status,
    required this.icon,
    required this.description,
  });

  final double width;
  final String name;
  final String status;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1924),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.gold, size: 20),
          const SizedBox(height: 9),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            status,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 8.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MethodologyPanel extends StatelessWidget {
  const _MethodologyPanel({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF0A1924),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.gold, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(color: AppColors.gold)),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 8.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
