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

  Widget _methodology() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
    child: Material(
      color: const Color(0xFF07131D),
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
