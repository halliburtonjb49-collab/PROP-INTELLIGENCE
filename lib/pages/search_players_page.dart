import 'package:flutter/material.dart';

import '../models/prop_data.dart';
import '../theme/app_colors.dart';

class SearchPlayersPage extends StatefulWidget {
  const SearchPlayersPage({super.key, required this.props});

  final List<PropData> props;

  @override
  State<SearchPlayersPage> createState() => _SearchPlayersPageState();
}

class _SearchPlayersPageState extends State<SearchPlayersPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unique = <String, PropData>{};
    for (final prop in widget.props) {
      final key = prop.player.trim().toLowerCase();
      if (key.isNotEmpty) unique.putIfAbsent(key, () => prop);
    }
    final players = unique.values.toList()
      ..sort((left, right) => left.player.compareTo(right.player));
    final query = _searchController.text.trim().toLowerCase();
    final filtered = players
        .where((prop) {
          if (query.isEmpty) return true;
          return prop.player.toLowerCase().contains(query) ||
              prop.matchup.toLowerCase().contains(query) ||
              prop.market.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Players Directory',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1927),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.gold, width: 1.1),
                  ),
                  child: TextField(
                    key: const ValueKey('player-search-field'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search players, teams, or markets...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF8191A5),
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.gold,
                        size: 20,
                      ),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.white70,
                              ),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${filtered.length} of ${players.length} players',
            key: const ValueKey('player-search-count'),
            style: const TextStyle(
              color: Color(0xFF9DB0C4),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.sidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.chromeShadow),
              ),
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFF1D2B39)),
                itemBuilder: (context, index) {
                  final prop = filtered[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      prop.player,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${prop.matchup} \u2022 ${prop.market} \u2022 ${prop.sport}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9DB0C4),
                        fontSize: 10.5,
                      ),
                    ),
                    trailing: Text(
                      'PI ${prop.piTrustScore}',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
