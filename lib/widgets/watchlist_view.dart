import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/slip_manager.dart';
import '../theme/app_colors.dart';
import 'dashboard_panel.dart';
import 'elite_prop_card.dart';

class CloudWatchlistDashboardCanvas extends StatefulWidget {
  final List<dynamic> globalLiveProps;
  final bool isUserPremium;

  const CloudWatchlistDashboardCanvas({
    super.key,
    required this.globalLiveProps,
    required this.isUserPremium,
  });

  @override
  State<CloudWatchlistDashboardCanvas> createState() =>
      _CloudWatchlistDashboardCanvasState();
}

class _CloudWatchlistDashboardCanvasState
    extends State<CloudWatchlistDashboardCanvas> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<String> _savedPlayerNames = [];
  bool _isLoading = true;

  String _normalizePlayerName(String value) => value.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _fetchUserCloudWatchlist();
  }

  Future<void> _fetchUserCloudWatchlist() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savedPlayerNames = const [];
        _isLoading = false;
      });
      return;
    }

    try {
      final List<dynamic> data = await _supabase
          .from('user_watchlists')
          .select('player_name')
          .eq('user_id', user.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _savedPlayerNames = data
            .map((item) => item['player_name']?.toString() ?? '')
            .map(_normalizePlayerName)
            .where((name) => name.isNotEmpty)
            .toList(growable: false);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching cloud watchlists: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFFFFD700)),
        ),
      );
    }

    final watchlistedProps = widget.globalLiveProps
        .where((prop) {
          if (prop is! Map<String, dynamic>) {
            return false;
          }
          final playerName = _normalizePlayerName(
            (prop['player_name'] ?? '').toString(),
          );
          return _savedPlayerNames.contains(playerName);
        })
        .toList(growable: false);

    if (watchlistedProps.isEmpty) {
      return Center(
        child: DashboardPanel(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 30),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_outlined, color: AppColors.gold, size: 28),
              SizedBox(height: 12),
              Text(
                'No watched players',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Select the star on a player card to add them here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: watchlistedProps.length,
      itemBuilder: (context, index) {
        final prop = watchlistedProps[index] as Map<String, dynamic>;
        final oddsData = (prop['odds_data'] as List<dynamic>? ?? const []);
        final firstOdds = oddsData.isNotEmpty
            ? oddsData.first as Map<String, dynamic>
            : const <String, dynamic>{};

        return GestureDetector(
          onTap: () {
            final propId = (prop['id'] ?? prop['prop_id'] ?? '').toString();
            final selectionPayload = {
              'id': propId,
              'prop_id': propId,
              'player_name': (prop['player_name'] ?? '').toString(),
              'market_type': (prop['market_type'] ?? '').toString(),
              'line': (prop['line'] as num?) ?? 0,
              'sport': (prop['sport'] ?? '').toString(),
              'edge_percentage': (prop['edge_percentage'] as num?) ?? 0,
              'ai_projection': (prop['ai_projection'] as num?),
              'sportsbook': (firstOdds['bookmaker'] ?? 'sportsbook').toString(),
              'odds_data': oddsData,
            };
            SlipManager.togglePropSelection(selectionPayload);
          },
          child: ElitePropCard(
            playerName: (prop['player_name'] ?? '').toString(),
            propType: (prop['market_type'] ?? '').toString(),
            sportsbookLine: (prop['line'] as num?) ?? 0,
            americanOdds: ((firstOdds['over_odds'] as num?) ?? -110).toInt(),
            aiProjection: (prop['ai_projection'] as num?) ?? 0,
            edgePercentage: (prop['edge_percentage'] as num?) ?? 0,
            isUserPremium: widget.isUserPremium,
            initialIsFavorited: true,
            propData: prop,
          ),
        );
      },
    );
  }
}
