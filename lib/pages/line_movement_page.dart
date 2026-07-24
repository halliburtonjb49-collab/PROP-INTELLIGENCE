import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/prop_data.dart';
import '../services/api_service.dart';
import '../services/player_image_resolver.dart';
import '../theme/app_colors.dart';
import '../widgets/dashboard_panel.dart';
import '../widgets/context_help.dart';

class LineMovementPage extends StatefulWidget {
  const LineMovementPage({super.key, required this.selectedSport});

  final String selectedSport;

  @override
  State<LineMovementPage> createState() => _LineMovementPageState();
}

class _LineMovementPageState extends State<LineMovementPage> {
  final ApiService _apiService = ApiService();
  late Future<_LineMovementViewData> _movementFuture;
  String _tableSport = 'ALL SPORTS';
  bool _showAllMovements = false;
  bool _alertsEnabled = true;
  bool _criticalAlertsOnly = false;
  DateTime? _lastLoadedAt;

  @override
  void initState() {
    super.initState();
    _movementFuture = _loadMovementData(refresh: false);
  }

  @override
  void didUpdateWidget(covariant LineMovementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSport != widget.selectedSport) {
      _refresh();
    }
  }

  void _refresh() {
    setState(() {
      _movementFuture = _loadMovementData(refresh: true);
    });
  }

  Future<void> _showAlertSettings() async {
    var enabled = _alertsEnabled;
    var criticalOnly = _criticalAlertsOnly;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0B1822),
          title: const Text(
            'Line Movement Alerts',
            style: TextStyle(color: AppColors.white),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: enabled,
                  activeThumbColor: AppColors.gold,
                  title: const Text(
                    'Enable line alerts',
                    style: TextStyle(color: AppColors.white),
                  ),
                  subtitle: const Text(
                    'Show notifications when tracked lines move.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
                SwitchListTile(
                  value: criticalOnly,
                  activeThumbColor: AppColors.gold,
                  title: const Text(
                    'Critical movement only',
                    style: TextStyle(color: AppColors.white),
                  ),
                  onChanged: enabled
                      ? (value) => setDialogState(() => criticalOnly = value)
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      _alertsEnabled = enabled;
      _criticalAlertsOnly = criticalOnly;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? criticalOnly
                    ? 'Critical line-movement alerts enabled.'
                    : 'All line-movement alerts enabled.'
              : 'Line-movement alerts disabled.',
        ),
      ),
    );
  }

  Future<_LineMovementViewData> _loadMovementData({
    required bool refresh,
  }) async {
    final selectedSport = widget.selectedSport.trim().toUpperCase();
    // Real opening-vs-current line data already lives on every PropData
    // (tracked persistently by the sync pipeline - the same data the board
    // uses for its "Line X -> Y" display), so movement is computed directly
    // from what fetchProps() already returns. A refresh just re-fetches;
    // there's no separate "check lines" round trip needed or a stale
    // same-moment comparison to worry about.
    final allProps = await _apiService.fetchProps();
    final props = allProps.where((prop) {
      if (selectedSport.isEmpty || selectedSport == 'ALL') {
        return true;
      }
      return prop.sport.trim().toUpperCase() == selectedSport;
    }).toList();

    final items = props.map(_LineMovementItem.fromProp).toList()
      ..sort((a, b) => b.movementMagnitude.compareTo(a.movementMagnitude));
    _lastLoadedAt = DateTime.now();
    return _LineMovementViewData(items: items);
  }

  Widget _alertsTicker(List<String> alerts) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101D28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8B6813)),
      ),
      child: Row(
        children: [
          const Icon(Icons.feed, size: 18, color: Color(0xFFFFC400)),
          const SizedBox(width: 8),
          const Text(
            'LINE ALERTS',
            style: TextStyle(
              color: Color(0xFFFFC400),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: alerts
                    .map(
                      (alert) => Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Text(
                          alert,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 30,
            child: OutlinedButton(
              onPressed: _showAlertSettings,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: const BorderSide(color: AppColors.borderGold),
                padding: const EdgeInsets.symmetric(horizontal: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              child: const Text('Manage Alerts', style: TextStyle(fontSize: 9)),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'BETTER':
        return const Color(0xFF2ECC71);
      case 'WORSE':
        return const Color(0xFFE74C3C);
      case 'MOVED':
        return const Color(0xFFFFC400);
      case 'UNAVAILABLE':
        return const Color(0xFF94A3B8);
      default:
        return const Color(0xFF5C6B78);
    }
  }

  Widget _buildMovementSummaryCards({
    required int changedCount,
    required int totalTracked,
    required int significantMoves,
    required int sharpMoves,
    required double? marketConfidence,
    required DateTime? lastUpdate,
  }) {
    final lastUpdateLocal = lastUpdate?.toLocal();
    final lastUpdateText = lastUpdateLocal == null
        ? '--'
        : '${lastUpdateLocal.hour.toString().padLeft(2, '0')}:'
              '${lastUpdateLocal.minute.toString().padLeft(2, '0')}';
    final cards = <Widget>[
      _summaryCard(
        icon: Icons.shield_rounded,
        iconColor: AppColors.red,
        value: '$changedCount',
        label: 'LINES MOVED',
        detail: 'vs. opening line',
      ),
      _summaryCard(
        icon: Icons.campaign_rounded,
        iconColor: AppColors.gold,
        value: '$significantMoves',
        label: 'SIGNIFICANT MOVES',
        detail: '≥ 10%',
      ),
      _summaryCard(
        icon: Icons.radar_rounded,
        iconColor: AppColors.red,
        value: '$sharpMoves',
        label: 'SHARP MOVES',
        detail: '≥10% in last 15 min',
      ),
      _summaryCard(
        icon: Icons.trending_up_rounded,
        iconColor: AppColors.blue,
        value: marketConfidence == null
            ? '--'
            : '${marketConfidence.round()}%',
        label: 'FAVORABLE MOVEMENT',
        detail: marketConfidence == null
            ? 'No moved lines yet'
            : 'Moved toward the pick',
      ),
      _summaryCard(
        icon: Icons.schedule_rounded,
        iconColor: AppColors.gold,
        value: lastUpdateText,
        label: 'LAST MOVE SEEN',
        detail: '$totalTracked tracked',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required String detail,
  }) {
    return DashboardPanel(
      radius: 11,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconColor.withValues(alpha: 0.30)),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    final sportLabel = widget.selectedSport.trim().isEmpty
        ? 'ALL SPORTS'
        : widget.selectedSport.toUpperCase();

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
          ),
          child: const Icon(
            Icons.stacked_line_chart_rounded,
            color: AppColors.gold,
            size: 22,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LINE MOVEMENT',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Live market movement and prop-line intelligence • $sportLabel',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const ContextHelp(
          title: 'Line movement',
          message:
              'Line movement shows how a sportsbook number changed over time. A move can reflect new information, market demand, or risk management. Compare books and confirm the current line before acting.',
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('REFRESH'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.gold,
            side: const BorderSide(color: AppColors.borderGold),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _referenceHeader() => Row(
    children: [
      const Expanded(
        child: Text(
          'LINE MOVEMENT INTEL',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      ),
      OutlinedButton.icon(
        onPressed: _showAlertSettings,
        icon: const Icon(Icons.notifications_none_rounded, size: 16),
        label: const Text('Manage Alerts'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: const BorderSide(color: AppColors.borderGold),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    ],
  );

  String _relativeTime(DateTime? moment) {
    if (moment == null) return '--';
    final age = DateTime.now().toUtc().difference(moment.toUtc());
    if (age.isNegative || age.inMinutes < 1) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }

  Widget _playerPhoto(String player, String imagePath) {
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: resolvePlayerImagePath(imagePath),
        width: 22,
        height: 22,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        fadeInDuration: Duration.zero,
        memCacheWidth: 44,
        memCacheHeight: 44,
        placeholder: (_, _) => const ColoredBox(
          color: AppColors.panelLight,
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(Icons.person, size: 13, color: AppColors.textSecondary),
          ),
        ),
        errorWidget: (_, _, _) => const ColoredBox(
          color: AppColors.panelLight,
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(Icons.person, size: 13, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _bookBadge(String book, Color color) {
    final cleaned = book.trim().isEmpty ? 'Market' : book.trim();
    final key = cleaned.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final (label, brandColor) = switch (key) {
      'draftkings' || 'dk' => ('DK', const Color(0xFF53D337)),
      'fanduel' || 'fd' => ('FD', const Color(0xFF1685F8)),
      'betmgm' || 'mgm' => ('MGM', const Color(0xFFD6B557)),
      'caesars' || 'caesarssportsbook' => ('C', const Color(0xFFC9A75D)),
      'espnbet' || 'espn' => ('E', const Color(0xFFE21C2A)),
      'fanatics' || 'fanaticssportsbook' => ('F', const Color(0xFFE31837)),
      'prizepicks' || 'pp' => ('PP', const Color(0xFF7BEE4C)),
      'underdog' || 'underdogfantasy' => ('UD', const Color(0xFFFFC400)),
      _ => (
        cleaned
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .map((part) => part[0])
            .take(2)
            .join()
            .toUpperCase(),
        color,
      ),
    };
    return Tooltip(
      message: cleaned,
      child: Container(
        constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: brandColor.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: brandColor.withValues(alpha: .75)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: brandColor,
            fontSize: label.length > 2 ? 6 : 7,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _movementTable(List<_LineMovementItem> items) {
    const header = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 8,
      fontWeight: FontWeight.w800,
    );
    return DashboardPanel(
      padding: EdgeInsets.zero,
      radius: 10,
      child: Column(
        children: [
          SizedBox(
            height: 37,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children:
                  [
                    'ALL SPORTS',
                    'MLB',
                    'NBA',
                    'NFL',
                    'WNBA',
                    'NHL',
                    'UFC',
                    'PGA',
                    'TENNIS',
                    'SOCCER',
                  ].map((sport) {
                    final selected = sport == _tableSport;
                    return InkWell(
                      onTap: () => setState(() {
                        _tableSport = sport;
                        _showAllMovements = false;
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        child: Center(
                          child: Text(
                            sport,
                            style: TextStyle(
                              color: selected
                                  ? AppColors.gold
                                  : AppColors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          Container(height: 1, color: AppColors.border),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('PLAYER', style: header)),
                Expanded(flex: 3, child: Text('MARKET', style: header)),
                Expanded(child: Text('SPORT', style: header)),
                Expanded(flex: 2, child: Text('BOOK', style: header)),
                Expanded(flex: 3, child: Text('LINE MOVEMENT', style: header)),
                Expanded(flex: 2, child: Text('% CHANGE', style: header)),
                Expanded(child: Text('TIME', style: header)),
                SizedBox(width: 26),
              ],
            ),
          ),
          for (final p
              in items
                  .where(
                    (item) =>
                        _tableSport == 'ALL SPORTS' ||
                        item.sport.toUpperCase() == _tableSport,
                  )
                  .take(_showAllMovements ? items.length : 5))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border, width: .6),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        _playerPhoto(p.player, p.imagePath),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            p.player,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      p.market,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 8,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p.sport,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 8,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        _bookBadge(p.previousBook, AppColors.blue),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 3),
                          child: Icon(
                            Icons.arrow_forward,
                            color: AppColors.white,
                            size: 11,
                          ),
                        ),
                        _bookBadge(p.currentBook, AppColors.gold),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${p.previousLine?.toStringAsFixed(1) ?? '--'}   →   ${p.currentLine?.toStringAsFixed(1) ?? '--'}',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${p.percentChange >= 0 ? '+' : ''}${p.percentChange.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: _statusColor(p.status),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _relativeTime(p.movedAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 8,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 26,
                    child: Icon(
                      Icons.show_chart,
                      color: AppColors.gold,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _insights(List<_LineMovementItem> items) {
    // Real per-sport movement rate: how many of each sport's tracked props
    // have actually moved off their opening line, out of how many are
    // tracked for that sport. Replaces a purely decorative fixed-gradient
    // grid that had no relationship to the underlying data.
    final sportsToShow = ['MLB', 'NBA', 'NFL', 'WNBA', 'NHL', 'SOCCER'];
    final sportStats = <String, (int moved, int total)>{};
    for (final sport in sportsToShow) {
      final forSport = items
          .where((item) => item.sport.toUpperCase() == sport)
          .toList();
      if (forSport.isEmpty) continue;
      sportStats[sport] = (
        forSport.where((item) => item.hasMoved).length,
        forSport.length,
      );
    }

    final movedItems = items.where((item) => item.hasMoved).toList();
    final sharpMoves = movedItems
        .where(
          (item) =>
              item.percentChange >= 10 &&
              item.movedAt != null &&
              DateTime.now()
                      .toUtc()
                      .difference(item.movedAt!)
                      .inMinutes <=
                  15,
        )
        .length;
    final otherMoves = movedItems.length - sharpMoves;
    final noMovement = items.length - movedItems.length;
    final total = items.isEmpty ? 1 : items.length;
    String pct(int count) => '${(count / total * 100).round()}%';

    final favorable = movedItems.isEmpty
        ? null
        : movedItems.where((item) => item.status == 'BETTER').length /
              movedItems.length;

    return Row(
      children: [
        Expanded(
          child: DashboardPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MOVEMENT RATE BY SPORT',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                if (sportStats.isEmpty)
                  const Text(
                    'No tracked props yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                    ),
                  )
                else
                  for (final entry in sportStats.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 46,
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 8,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: entry.value.$1 / entry.value.$2,
                                minHeight: 14,
                                backgroundColor: const Color(0xFF19482B),
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.gold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 44,
                            child: Text(
                              '${entry.value.$1}/${entry.value.$2}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DashboardPanel(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  height: 78,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: favorable ?? 0,
                        strokeWidth: 10,
                        color: AppColors.blue,
                        backgroundColor: AppColors.border,
                      ),
                      Text(
                        favorable == null
                            ? '--'
                            : '${(favorable * 100).round()}%',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'MOVEMENT BREAKDOWN',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '■  Sharp Moves          $sharpMoves (${pct(sharpMoves)})',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '■  Other Moves          $otherMoves (${pct(otherMoves)})',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '■  No Movement        $noMovement (${pct(noMovement)})',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF050B11),
      padding: const EdgeInsets.all(12),
      child: FutureBuilder<_LineMovementViewData>(
        future: _movementFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.blue),
            );
          }
          const defaultAlerts = <String>[
            'Line movement monitor online',
            'Gold alerts update as data refreshes',
            'Interval set to 4 minutes',
          ];
          if (snapshot.hasError) {
            final message = snapshot.error.toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPageHeader(),
                const SizedBox(height: 14),
                _alertsTicker(defaultAlerts),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111B26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF8B6813)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LINE MOVEMENT FAILED TO LOAD',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message.length > 220
                            ? '${message.substring(0, 220)}...'
                            : message,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF96A4B2),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('TRY AGAIN'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final data = snapshot.data ?? const _LineMovementViewData(items: []);
          final top = data.items.toList();
          final movedItems = data.items.where((item) => item.hasMoved).toList();
          final changed = movedItems.length;
          final significantMoves = movedItems
              .where((item) => item.percentChange >= 10)
              .length;
          final now = DateTime.now().toUtc();
          final sharpMoves = movedItems
              .where(
                (item) =>
                    item.percentChange >= 10 &&
                    item.movedAt != null &&
                    now.difference(item.movedAt!).inMinutes <= 15,
              )
              .length;
          final marketConfidence = movedItems.isEmpty
              ? null
              : movedItems.where((item) => item.status == 'BETTER').length /
                    movedItems.length *
                    100;
          DateTime? lastUpdate;
          for (final item in data.items) {
            if (item.movedAt == null) continue;
            if (lastUpdate == null || item.movedAt!.isAfter(lastUpdate)) {
              lastUpdate = item.movedAt;
            }
          }
          final movementAlerts = <String>[
            if (movedItems.isNotEmpty)
              'Largest movement signal: ${top.first.player} (${top.first.movementMagnitude.toStringAsFixed(2)})'
            else
              'No significant line movement detected right now',
            'Changed lines detected: $changed',
            widget.selectedSport == 'ALL'
                ? 'Tracking all sports'
                : 'Tracking ${widget.selectedSport.toUpperCase()}',
            'Data source: opening vs. current line',
          ];

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPageHeader(),
                const SizedBox(height: 10),
                _alertsTicker(movementAlerts),
                const SizedBox(height: 9),
                _buildMovementSummaryCards(
                  changedCount: changed,
                  totalTracked: top.length,
                  significantMoves: significantMoves,
                  sharpMoves: sharpMoves,
                  marketConfidence: marketConfidence,
                  lastUpdate: lastUpdate,
                ),
                const SizedBox(height: 12),
                _movementTable(top),
                Align(
                  child: SizedBox(
                    width: 230,
                    height: 28,
                    child: OutlinedButton(
                      onPressed: () => setState(
                        () => _showAllMovements = !_showAllMovements,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gold,
                        side: const BorderSide(color: AppColors.borderGold),
                      ),
                      child: Text(
                        _showAllMovements
                            ? 'Show Top 5'
                            : 'View All Line Movement',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(height: 130, child: _insights(top)),
                const SizedBox(height: 6),
                _MovementStatusFooter(
                  alertsEnabled: _alertsEnabled,
                  lastUpdated: _relativeTime(_lastLoadedAt),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MovementStatusFooter extends StatelessWidget {
  final bool alertsEnabled;
  final String lastUpdated;

  const _MovementStatusFooter({
    required this.alertsEnabled,
    required this.lastUpdated,
  });

  @override
  Widget build(BuildContext context) {
    // This page has no auto-refresh timer - it only reloads on-demand (the
    // REFRESH button, or switching sports), so "Real-time"/a fixed interval
    // would be a false claim. "Manual" is the honest description.
    final items = [
      (Icons.shield_outlined, 'DATA SOURCES', 'Opening vs. current line'),
      (Icons.schedule_rounded, 'REFRESH', 'Manual'),
      (
        Icons.notifications_none_rounded,
        'ALERTS',
        alertsEnabled ? 'Active' : 'Disabled',
      ),
      (Icons.history_rounded, 'LAST UPDATED', lastUpdated),
    ];
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    items[i].$1,
                    color: i == 2 ? AppColors.blue : AppColors.textMuted,
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].$2,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].$3,
                        style: TextStyle(
                          color: i == 2 ? AppColors.blue : AppColors.white,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (i < items.length - 1)
              Container(width: 1, height: 34, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _LineMovementViewData {
  final List<_LineMovementItem> items;

  const _LineMovementViewData({required this.items});
}

class _LineMovementItem {
  final String player;
  final String imagePath;
  final String sport;
  final String market;
  final double? previousLine;
  final double? currentLine;
  final String previousBook;
  final String currentBook;
  final DateTime? movedAt;
  final String recommendedSide;

  const _LineMovementItem({
    required this.player,
    required this.imagePath,
    required this.sport,
    required this.market,
    required this.previousLine,
    required this.currentLine,
    required this.previousBook,
    required this.currentBook,
    required this.movedAt,
    required this.recommendedSide,
  });

  bool get hasMoved =>
      previousLine != null &&
      currentLine != null &&
      (currentLine! - previousLine!).abs() >= 0.01;

  double get movementMagnitude {
    if (!hasMoved) return 0;
    return (currentLine! - previousLine!).abs();
  }

  double get percentChange {
    if (!hasMoved || previousLine == 0) return 0;
    return (movementMagnitude / previousLine!.abs()) * 100;
  }

  /// BETTER/WORSE is relative to the model's recommended side: a lower line
  /// helps an OVER pick, a higher line helps an UNDER pick.
  String get status {
    if (!hasMoved) return 'UNCHANGED';
    final favorsUnder = recommendedSide.toUpperCase().contains('UNDER');
    final improved = favorsUnder
        ? currentLine! > previousLine!
        : currentLine! < previousLine!;
    return improved ? 'BETTER' : 'WORSE';
  }

  factory _LineMovementItem.fromProp(PropData p) {
    return _LineMovementItem(
      player: p.player,
      imagePath: p.imagePath,
      sport: p.sport,
      market: p.market,
      previousLine: p.openingLine == 0 ? null : p.openingLine,
      currentLine: p.currentLine == 0 ? null : p.currentLine,
      previousBook: p.sportsbook,
      currentBook: p.sportsbook,
      movedAt: DateTime.tryParse(p.lineMovedAtUtc),
      recommendedSide: p.recommendedSide,
    );
  }
}
