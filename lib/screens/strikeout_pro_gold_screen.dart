import 'dart:async';

import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../models/slip_selection.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/player_image_widget.dart';
import '../widgets/recommendation_explainability_block.dart';
import '../widgets/prop_research_assistant.dart';
import '../widgets/prop_trust_widgets.dart';

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
      const Duration(seconds: 20),
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
    if (prop.proSuggestionUsesHistoricalStats) return 'PI PICK';
    return 'MARKET LEAN';
  }

  double _edge(PropData prop) => prop.calculatedEdge ?? prop.edge.abs();

  Future<void> _load() async {
    setState(() {
      // Keep the current cards mounted during live/manual refreshes. Replacing
      // the grid with a loader discarded every cached headshot every 45s.
      _loading = _props.isEmpty;
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
        final trust = b.piTrustScore.compareTo(a.piTrustScore);
        return trust != 0 ? trust : _edge(b).compareTo(_edge(a));
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
    final visible = _visible;
    final providerSections = <String, List<PropData>>{};
    for (final prop in visible) {
      final provider = prop.sportsbook.trim().isEmpty
          ? 'OTHER PROVIDER'
          : prop.sportsbook.trim().toUpperCase();
      providerSections.putIfAbsent(provider, () => <PropData>[]).add(prop);
    }
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
          else if (visible.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No MLB pitcher strikeout lines are available right now.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else ...[
            for (final section in providerSections.entries) ...[
              SliverToBoxAdapter(
                child: _providerDivider(section.key, section.value.length),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
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
                        mainAxisExtent: 180,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final prop = section.value[index];
                        return KeyedSubtree(
                          key: ValueKey('strikeout-card-${prop.id}'),
                          child: _card(prop),
                        );
                      }, childCount: section.value.length),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _providerDivider(String provider, int count) => Container(
    margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: AppColors.gold.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.gold.withValues(alpha: .72)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.storefront_rounded,
          size: 16,
          color: AppColors.gold,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            provider,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
        ),
        Text(
          '$count ${count == 1 ? 'PROP' : 'PROPS'}',
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _header() {
    final modeled = _props.where((prop) => prop.projection != null).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF07141E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGold, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MLB  /  STRIKEOUT PRO GOLD  /  TOP PI PICKS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 18,
              runSpacing: 14,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const SizedBox(
                  width: 510,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHOOSE YOUR STRIKEOUT SITE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .3,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Start with the board you use. PI ranks every available MLB pitcher strikeout line by its current live signal.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: const [
                    _StrikeoutStep(number: '1', label: 'SELECT SITE', active: true),
                    _StrikeoutStep(number: '2', label: 'SELECT SIDE'),
                    _StrikeoutStep(number: '3', label: 'COMPARE PI PICKS'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              _metric('LIVE STRIKEOUT LINES', '${_props.length}'),
              _metric('MODELED', '$modeled'),
              _metric('REFRESH', '20 SEC'),
              _metric('ACCESS', 'PRO GOLD'),
            ],
          ),
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
        Text(
          _selectedSite == null
              ? 'CHOOSE YOUR PROP SITE'
              : 'TOP STRIKEOUT PICKS ON $_selectedSite',
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
                label: 'ALL SITES',
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
      minimumSize: const Size(170, 76),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? Icons.emoji_events_rounded : Icons.shield_outlined,
          size: 23,
          color: selected ? AppColors.gold : AppColors.silver,
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '$count strikeout props',
              style: TextStyle(
                color: selected
                    ? brand_colors.AppColors.sidebar.withValues(alpha: .72)
                    : AppColors.textMuted,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
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
                  'Home-plate umpire tendency and prop-site line/price movement',
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
    final projection = prop.projection?.toStringAsFixed(1) ?? '--';
    final learned = prop.probabilityCalibrationAdjustment.abs() >= .005;
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
    return Material(
      key: ValueKey('strikeout-card-${prop.id}'),
      color: const Color(0xFF081620),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showPiIntelligence(prop),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 112,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00081620), Color(0xFF0E2330)],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: PlayerImageWidget(
                              key: ValueKey('strikeout-photo-${prop.id}-${prop.imagePath}'),
                              imageUrl: prop.imagePath,
                              width: 108,
                              height: 116,
                              fit: BoxFit.contain,
                              fallbackIcon: Icons.person_rounded,
                              fallbackIconSize: 38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(prop.player, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          Text(prop.matchup, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                          const SizedBox(height: 5),
                          Row(children: [
                            const Icon(Icons.emoji_events_outlined, size: 12, color: AppColors.gold),
                            const SizedBox(width: 4),
                            Expanded(child: Text(prop.sportsbook.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900))),
                          ]),
                        ],
                      ),
                    ),
                    const VerticalDivider(color: AppColors.border, width: 18),
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_signalLabel(prop, systemSide), style: TextStyle(color: signalColor, fontSize: 7.5, fontWeight: FontWeight.w900)),
                          Text('$sideText ${prop.line.toStringAsFixed(1)}', style: TextStyle(color: signalColor, fontSize: 14, fontWeight: FontWeight.w900)),
                          const Text('PITCHER STRIKEOUTS', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textMuted, fontSize: 8, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    const VerticalDivider(color: AppColors.border, width: 18),
                    Expanded(
                      flex: 3,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PI TRUST', style: TextStyle(color: AppColors.textMuted, fontSize: 7.5, fontWeight: FontWeight.w800)),
                          Text('${prop.piTrustScore}', style: const TextStyle(color: brand_colors.AppColors.success, fontSize: 14, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 3),
                          const Text('PROJECTION', style: TextStyle(color: AppColors.textMuted, fontSize: 7, fontWeight: FontWeight.w800)),
                          Text(projection, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    const Icon(Icons.star_border_rounded, color: AppColors.gold, size: 20),
                  ],
                ),
              ),
              Row(
                children: [
                  if (learned)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(color: const Color(0xFF31245C), borderRadius: BorderRadius.circular(99)),
                      child: const Text('PI LEARNING ACTIVE', style: TextStyle(color: AppColors.silver, fontSize: 7, fontWeight: FontWeight.w900)),
                    ),
                  Expanded(
                    child: FilledButton.icon(
                      key: ValueKey('strikeout-pi-detail-${prop.id}'),
                      onPressed: () => _showPiIntelligence(prop),
                      icon: const Icon(Icons.psychology_alt_rounded, size: 14),
                      label: const Text('OPEN PI INTELLIGENCE'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.background, minimumSize: const Size(0, 34), textStyle: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _piLearningStatus(PropData prop) {
    final adjustment = prop.probabilityCalibrationAdjustment;
    final active = adjustment.abs() >= .005;
    final sample = prop.probabilityCalibrationSampleSize;
    final color = active ? brand_colors.AppColors.success : AppColors.gold;
    final direction = adjustment > 0
        ? 'STRENGTHENED'
        : adjustment < 0
        ? 'WEAKENED'
        : 'COLLECTING';
    final adjustmentLabel = active
        ? ' • ${(adjustment * 100).abs().toStringAsFixed(1)}% $direction'
        : '';
    return Container(
      key: ValueKey('strikeout-pi-learning-${prop.id}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.model_training_rounded : Icons.hourglass_top_rounded,
            color: color,
            size: 15,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${active ? 'PI LEARNING ACTIVE' : 'PI LEARNING COLLECTING'}$adjustmentLabel • $sample VERIFIED SAMPLES',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPiIntelligence(PropData prop) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF06111A),
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .88,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.psychology_alt_rounded,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${prop.player.toUpperCase()} • PI INTELLIGENCE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _piLearningStatus(prop),
              const SizedBox(height: 12),
              if (prop.isSelectable) ...[
                Row(
                  children: [
                    Expanded(
                      child: _sideButton(
                        prop: prop,
                        side: PickSide.under,
                        selected: _selectedSides[prop.id] == PickSide.under,
                        systemPick: _recommendedSide(prop) == PickSide.under,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _lineDisplay(prop),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _sideButton(
                        prop: prop,
                        side: PickSide.over,
                        selected: _selectedSides[prop.id] == PickSide.over,
                        systemPick: _recommendedSide(prop) == PickSide.over,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose OVER or UNDER to add this strikeout line to the active slip.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9),
                ),
                const SizedBox(height: 12),
              ],
              WhyThisPropCapsule(prop: prop),
              const SizedBox(height: 12),
              RecommendationExplainabilityBlock(
                prop: prop,
                title: 'STANDARDIZED EXPLAINABILITY',
              ),
              const SizedBox(height: 12),
              PropResearchAiButton(
                prop: prop,
                comparisonCandidates: _props,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _lineDisplay(PropData prop) {
    return Container(
      constraints: const BoxConstraints(minWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1622),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.gold.withValues(alpha: .28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'LINE',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            prop.line.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
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
        minimumSize: const Size(0, 54),
        foregroundColor: selected
            ? brand_colors.AppColors.sidebar
            : Colors.white,
        backgroundColor: selected
            ? AppColors.goldHighlight.withValues(alpha: .88)
            : const Color(0xFF1A2430),
        side: BorderSide(
          color: selected
              ? AppColors.goldHighlight
              : systemPick
              ? AppColors.gold.withValues(alpha: .85)
              : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Row(
        children: [
          if (side == PickSide.under)
            Text(
              '⌄',
              style: TextStyle(
                color: selected ? brand_colors.AppColors.sidebar : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          if (side == PickSide.under) const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: selected
                        ? brand_colors.AppColors.sidebar
                        : AppColors.gold,
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  prop.line.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: selected
                        ? brand_colors.AppColors.sidebar
                        : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (side == PickSide.over) const SizedBox(width: 7),
          if (side == PickSide.over)
            Text(
              '⌃',
              style: TextStyle(
                color: selected ? brand_colors.AppColors.sidebar : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          if (!selected && systemPick) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.auto_awesome_rounded,
              size: 12,
              color: AppColors.gold,
            ),
          ],
        ],
      ),
    );
  }

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

class _StrikeoutStep extends StatelessWidget {
  const _StrikeoutStep({
    required this.number,
    required this.label,
    this.active = false,
  });

  final String number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.gold : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.gold : AppColors.border,
          ),
        ),
        child: Text(
          number,
          style: TextStyle(
            color: active ? brand_colors.AppColors.sidebar : AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        label,
        style: TextStyle(
          color: active ? AppColors.gold : AppColors.textMuted,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .35,
        ),
      ),
    ],
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
