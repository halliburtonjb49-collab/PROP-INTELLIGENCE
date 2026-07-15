SPORT_MARKETS = {
    "basketball_nba": [
        "player_points",
        "player_rebounds",
        "player_assists",
        "player_points_rebounds_assists",
        "player_blocks",
        "player_steals",
        "player_threes",
    ],
    "basketball_wnba": [
        "player_points",
        "player_rebounds",
        "player_assists",
        "player_points_rebounds_assists",
        "player_blocks",
        "player_steals",
        "player_threes",
    ],
    "baseball_mlb": [
        "batter_hits",
        "batter_total_bases",
        "batter_home_runs",
        "batter_rbis",
        "pitcher_strikeouts",
        "pitcher_walks",
    ],
    "americanfootball_nfl": [
        "player_pass_yds",
        "player_pass_tds",
        "player_rush_yds",
        "player_reception_yds",
        "player_receptions",
    ],
}


def markets_for_sport(sport_key: str) -> list[str]:
    return SPORT_MARKETS.get(sport_key, [])
