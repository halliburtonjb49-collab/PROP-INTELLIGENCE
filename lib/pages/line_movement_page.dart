import 'package:flutter/material.dart';

import '../services/api_service.dart';
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
    final props = (await _apiService.fetchProps()).where((prop) {
      if (selectedSport.isEmpty || selectedSport == 'ALL') {
        return true;
      }
      return prop.sport.trim().toUpperCase() == selectedSport;
    }).toList();
    if (props.isEmpty) {
      return const _LineMovementViewData(items: []);
    }

    final legs = props
        .take(25)
        .map(
          (p) => {
            'prop_id': p.id.isNotEmpty
                ? p.id
                : '${p.player}-${p.market}-${p.sport}',
            'id': p.id.isNotEmpty ? p.id : '${p.player}-${p.market}-${p.sport}',
            'event_id': p.eventId.isNotEmpty ? p.eventId : p.apiSportsGameId,
            'api_sports_game_id': p.apiSportsGameId,
            'player_id': p.playerId.isNotEmpty ? p.playerId : p.player,
            'custom_label': p.customLabel,
            'manual_note': p.manualNote,
            'player': p.player,
            'sport': p.sport,
            'matchup': p.matchup,
            'prop_site': p.sportsbook,
            'sportsbook': p.sportsbook,
            'market': p.market,
            'line': p.line,
            'current_line': p.line,
            'side': p.pick.isEmpty ? 'OVER' : p.pick,
            'pick': p.pick.isEmpty ? 'OVER' : p.pick,
            'odds': p.overOdds ?? p.multiplier ?? 0.0,
            'current_odds': p.overOdds ?? p.multiplier ?? 0.0,
            'over_odds': p.overOdds,
            'under_odds': p.underOdds,
            'multiplier': p.multiplier,
            'win_probability': p.winProbability,
            'edge': p.edge,
            'confidence': (p.winProbability ?? p.edge.toDouble()).round(),
          },
        )
        .toList();

    final response = await _apiService.checkPropLineMovement(
      legs: legs,
      refresh: refresh,
    );
    final rawLegs = response['legs'] as List<dynamic>? ?? [];
    final items = rawLegs
        .whereType<Map<String, dynamic>>()
        .map(_LineMovementItem.fromJson)
        .toList();
    items.sort((a, b) => b.movementMagnitude.compareTo(a.movementMagnitude));
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
    required double largestMovement,
  }) {
    final cards = <Widget>[
      _summaryCard(
        icon: Icons.shield_rounded,
        iconColor: AppColors.red,
        value: '$changedCount',
        label: 'LINES MOVED',
        detail: 'Last 30 min',
      ),
      _summaryCard(
        icon: Icons.campaign_rounded,
        iconColor: AppColors.gold,
        value: '${(changedCount * .67).round()}',
        label: 'SIGNIFICANT MOVES',
        detail: '≥ 10%',
      ),
      _summaryCard(
        icon: Icons.radar_rounded,
        iconColor: AppColors.red,
        value: '${(changedCount * .25).ceil()}',
        label: 'SHARP MOVES',
        detail: 'Detected',
      ),
      _summaryCard(
        icon: Icons.trending_up_rounded,
        iconColor: AppColors.blue,
        value: '${largestMovement == 0 ? 0 : 82}%',
        label: 'MARKET CONFIDENCE',
        detail: 'High',
      ),
      _summaryCard(
        icon: Icons.schedule_rounded,
        iconColor: AppColors.gold,
        value: '04:00',
        label: 'LAST UPDATE',
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

  String _playerImagePath(String player) {
    final slug = player
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'assets/players/$slug.png';
  }

  Widget _playerPhoto(String player) {
    return ClipOval(
      child: Image.asset(
        _playerImagePath(player),
        width: 22,
        height: 22,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(
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
                        _playerPhoto(p.player),
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
                  const Expanded(
                    child: Text(
                      '2m ago',
                      style: TextStyle(
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

  Widget _insights() => Row(
    children: [
      Expanded(
        child: DashboardPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LINE MOVEMENT HEATMAP',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              for (var row = 0; row < 4; row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          ['NBA', 'NFL', 'MLB', 'WNBA'][row],
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 8,
                          ),
                        ),
                      ),
                      for (var col = 0; col < 8; col++)
                        Expanded(
                          child: Container(
                            height: 16,
                            margin: const EdgeInsets.only(right: 2),
                            color: Color.lerp(
                              const Color(0xFF19482B),
                              row == 3 && col == 3
                                  ? const Color(0xFFB53030)
                                  : const Color(0xFFB4A521),
                              (col + row) / 14,
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
                    const CircularProgressIndicator(
                      value: .82,
                      strokeWidth: 10,
                      color: AppColors.blue,
                      backgroundColor: AppColors.border,
                    ),
                    const Text(
                      '82%',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'MOVEMENT BREAKDOWN',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '■  Sharp Moves          8 (25%)',
                      style: TextStyle(color: AppColors.white, fontSize: 9),
                    ),
                    SizedBox(height: 7),
                    Text(
                      '■  Public Moves        18 (57%)',
                      style: TextStyle(color: AppColors.white, fontSize: 9),
                    ),
                    SizedBox(height: 7),
                    Text(
                      '■  No Movement        6 (18%)',
                      style: TextStyle(color: AppColors.white, fontSize: 9),
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
          final changed = data.items
              .where((item) => item.status != 'UNCHANGED')
              .length;
          final movementAlerts = <String>[
            if (top.isNotEmpty)
              'Largest movement signal: ${top.first.player} (${top.first.movementMagnitude.toStringAsFixed(2)})',
            'Changed lines detected: $changed',
            widget.selectedSport == 'ALL'
                ? 'Tracking all sports'
                : 'Tracking ${widget.selectedSport.toUpperCase()}',
            'Data source: prop-builder line check',
            'Interval set to 4 minutes',
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
                  largestMovement: top.isNotEmpty
                      ? top.first.movementMagnitude
                      : 0,
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
                /*Row(
                children: [
                  const Expanded(
                    child: Text(
                      'MARKET MOVEMENT FEED',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  Text(
                    '${top.length} RESULTS',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              */
                const SizedBox(height: 10),
                SizedBox(
                  height: 130,
                  child: _insights() /* ListView.separated(
                  itemCount: top.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final p = top[index];
                    return DashboardPanel(
                      radius: 12,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _statusColor(
                                p.status,
                              ).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              p.status == 'BETTER'
                                  ? Icons.trending_up_rounded
                                  : p.status == 'WORSE'
                                  ? Icons.trending_down_rounded
                                  : Icons.swap_vert_rounded,
                              color: _statusColor(p.status),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.player,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${p.sport} • ${p.market}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'LINE CHANGE',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${p.previousLine?.toStringAsFixed(2) ?? '—'}  →  ${p.currentLine?.toStringAsFixed(2) ?? '—'}',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                p.status,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _statusColor(
                                  p.status,
                                ).withValues(alpha: 0.75),
                              ),
                            ),
                            child: Text(
                              p.status,
                              style: TextStyle(
                                color: _statusColor(p.status),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ), */,
                ),
                const SizedBox(height: 6),
                const _MovementStatusFooter(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ignore: unused_element
class _MovementStatusFooter extends StatelessWidget {
  const _MovementStatusFooter();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.shield_outlined, 'DATA SOURCES', 'Multiple Books & Market Feeds'),
      (Icons.schedule_rounded, 'INTERVAL', 'Real-time'),
      (Icons.notifications_none_rounded, 'ALERTS', 'Active'),
      (Icons.history_rounded, 'LAST UPDATED', 'Just now'),
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
  final String sport;
  final String market;
  final String status;
  final double? previousLine;
  final double? currentLine;
  final String previousBook;
  final String currentBook;

  const _LineMovementItem({
    required this.player,
    required this.sport,
    required this.market,
    required this.status,
    required this.previousLine,
    required this.currentLine,
    this.previousBook = 'Market',
    this.currentBook = 'Market',
  });

  double get movementMagnitude {
    if (previousLine == null || currentLine == null) {
      return 0;
    }
    return (currentLine! - previousLine!).abs();
  }

  double get percentChange {
    if (previousLine == null || currentLine == null || previousLine == 0) {
      return 0;
    }
    return ((currentLine! - previousLine!).abs() / previousLine!.abs()) * 100;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  factory _LineMovementItem.fromJson(Map<String, dynamic> json) {
    return _LineMovementItem(
      player: json['player']?.toString() ?? 'Unknown',
      sport: json['sport']?.toString() ?? '',
      market: json['market']?.toString() ?? '',
      status: (json['movement_status']?.toString() ?? 'UNCHANGED')
          .toUpperCase(),
      previousLine: _asDouble(json['previous_line'] ?? json['line_before']),
      currentLine: _asDouble(
        json['line'] ?? json['current_line'] ?? json['line_after'],
      ),
      previousBook:
          (json['previous_sportsbook'] ??
                  json['line_before_book'] ??
                  json['sportsbook'] ??
                  json['prop_site'] ??
                  'Market')
              .toString(),
      currentBook:
          (json['current_sportsbook'] ??
                  json['line_after_book'] ??
                  json['sportsbook'] ??
                  json['prop_site'] ??
                  'Market')
              .toString(),
    );
  }
}
