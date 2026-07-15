MARKET_ALIASES = {
    "player_points": "points",
    "points": "points",
    "player points": "points",
    "player_assists": "assists",
    "assists": "assists",
    "player assists": "assists",
    "player_rebounds": "rebounds",
    "rebounds": "rebounds",
    "player rebounds": "rebounds",
    "player_blocks": "blocks",
    "blocks": "blocks",
    "player blocks": "blocks",
    "player_steals": "steals",
    "steals": "steals",
    "player steals": "steals",
    "player threes": "three_pointers_made",
    "player_threes": "three_pointers_made",
    "player_3_pointers_made": "three_pointers_made",
    "3 pointers made": "three_pointers_made",
    "three pointers made": "three_pointers_made",
    "player_points_rebounds_assists": "pra",
    "points rebounds assists": "pra",
    "player points rebounds assists": "pra",
    "pra": "pra",
    "batter_hits": "hits",
    "hits": "hits",
    "batter_total_bases": "total_bases",
    "total bases": "total_bases",
    "pitcher_strikeouts": "pitcher_strikeouts",
    "pitcher strikeouts": "pitcher_strikeouts",
}


def normalize_market(value: str) -> str:
    key = value.strip().lower().replace("-", " ").replace("_", " ")
    key = " ".join(key.split())
    return MARKET_ALIASES.get(
        value.strip().lower(),
        MARKET_ALIASES.get(key, key.replace(" ", "_")),
    )
