import 'package:flutter/material.dart';

import '../services/affiliate_router.dart';
import '../services/api_service.dart';
import '../services/slip_manager.dart';

class CurrentSlipPanelContainer extends StatefulWidget {
  const CurrentSlipPanelContainer({super.key});

  @override
  State<CurrentSlipPanelContainer> createState() =>
      _CurrentSlipPanelContainerState();
}

class _CurrentSlipPanelContainerState extends State<CurrentSlipPanelContainer> {
  final ApiService _apiService = ApiService();
  final TextEditingController _stakeController = TextEditingController(
    text: '20.00',
  );

  bool _refreshing = false;

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  Future<void> _refreshOdds() async {
    if (_refreshing) {
      return;
    }

    setState(() {
      _refreshing = true;
    });

    try {
      await _apiService.syncProps();
      await SlipManager.refreshSelectedProps(_apiService);
    } catch (_) {
      // Keep panel responsive even if refresh fails.
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryYellow = Color(0xFFFFC400);

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: SlipManager.selectedProps,
      builder: (context, activeProps, child) {
        if (activeProps.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            color: const Color(0xFF0F1115),
            child: Center(
              child: Text(
                'No props selected',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.32),
                  fontSize: 16,
                ),
              ),
            ),
          );
        }

        final riskAmount = double.tryParse(_stakeController.text) ?? 0.0;
        final calculatedPayout = activeProps.length == 1
            ? (riskAmount * 1.90)
            : (riskAmount * (activeProps.length * 3.0));

        return Container(
          color: const Color(0xFF0F1115),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current Slip (${activeProps.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _refreshing ? null : _refreshOdds,
                        icon: _refreshing
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 14),
                        label: const Text('REFRESH'),
                        style: TextButton.styleFrom(
                          foregroundColor: primaryYellow,
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: SlipManager.clearAllSlips,
                        child: const Text('RESET'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: activeProps.length,
                  itemBuilder: (context, index) {
                    final item = activeProps[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E222A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (item['player_name'] ?? item['player'] ?? '-')
                                      .toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item['market_type'] ?? item['market'] ?? ''} O/U ${item['line'] ?? '--'}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            onPressed: () {
                              final id = (item['id'] ?? item['prop_id'] ?? '')
                                  .toString();
                              SlipManager.removePropById(id);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(color: Colors.white10, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Risk Amount (\$):',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(
                    width: 100,
                    height: 35,
                    child: TextField(
                      controller: _stakeController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF1E222A),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white10),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: primaryYellow),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Est. Return / Win:',
                    style: TextStyle(color: Colors.grey),
                  ),
                  Text(
                    '\$${calculatedPayout.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: primaryYellow,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  onPressed: () {
                    final first = activeProps.first;
                    final oddsData =
                        (first['odds_data'] as List<dynamic>? ?? const []);
                    final firstOdds = oddsData.isNotEmpty
                        ? oddsData.first as Map<String, dynamic>
                        : const <String, dynamic>{};

                    SportsbookAffiliateRouter.routeUserToWagerSlip(
                      sportsbook:
                          (firstOdds['bookmaker'] ??
                                  first['sportsbook'] ??
                                  'FanDuel')
                              .toString(),
                      playerName:
                          (first['player_name'] ?? first['player'] ?? '')
                              .toString(),
                      marketType:
                          (first['market_type'] ?? first['market'] ?? '')
                              .toString(),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryYellow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'PLACE WAGER',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
