from pathlib import Path
import re

MARKET_LABELS = {
    "POINTS": "Points",
    "REBOUNDS": "Rebounds",
    "ASSISTS": "Assists",
    "THREES": "3-Pointers",
    "PASS_YDS": "Pass Yards",
    "PASS_TDS": "Pass TDs",
    "RUSH_YDS": "Rush Yards",
    "RUSH_ATTEMPTS": "Rush Attempts",
    "RECEPTION_YDS": "Receiving Yards",
    "COMPLETIONS": "Completions",
    "HITS": "Hits",
    "HOME_RUNS": "Home Runs",
    "TOTAL_BASES": "Total Bases",
    "RBIS": "RBIs",
    "STRIKEOUTS": "Strikeouts",
    "BATTER_HITS": "Hits",
    "BATTER_HOME_RUNS": "Home Runs",
    "BATTER_TOTAL_BASES": "Total Bases",
    "BATTER_RBIS": "RBIs",
    "PITCHER_STRIKEOUTS": "Pitcher Strikeouts",
    "PITCHER_WALKS": "Pitcher Walks",
    "ACES": "Aces",
    "DOUBLE_FAULTS": "Double Faults",
    "BIRDIES": "Birdies",
    "STROKES": "Strokes",
    "GOALS": "Goals",
    "SHOTS": "Shots",
    "SHOTS_ON_TARGET": "Shots on Target",
}

CATEGORY_LABELS = {
    # NBA / WNBA
    "player_points": "points",
    "points": "points",
    "player_rebounds": "rebounds",
    "rebounds": "rebounds",
    "player_assists": "assists",
    "assists": "assists",
    "player_points_rebounds_assists": "pra",
    "pra": "pra",
    "player_blocks": "blocks",
    "blocks": "blocks",
    "player_steals": "steals",
    "steals": "steals",
    "player_threes": "3-pointers",
    "player_3_pointers_made": "3-pointers",
    "threes": "3-pointers",

    # MLB
    "batter_hits": "hits",
    "hits": "hits",
    "batter_home_runs": "home runs",
    "home_runs": "home runs",
    "batter_rbis": "rbis",
    "rbis": "rbis",
    "batter_runs_scored": "runs",
    "batter_total_bases": "total bases",
    "total_bases": "total bases",
    "pitcher_strikeouts": "strikeouts",
    "strikeouts": "strikeouts",
    "pitcher_outs": "outs recorded",
    "outs_recorded": "outs recorded",
    "hits_allowed": "hits allowed",

    # NFL
    "player_pass_yds": "passing yards",
    "player_passing_yards": "passing yards",
    "pass_yds": "passing yards",
    "player_rush_yds": "rushing yards",
    "player_rushing_yards": "rushing yards",
    "rush_yds": "rushing yards",
    "player_reception_yds": "receiving yards",
    "player_receiving_yards": "receiving yards",
    "reception_yds": "receiving yards",
    "player_receptions": "receptions",
    "receptions": "receptions",
    "player_touchdowns": "touchdowns",
    "pass_tds": "touchdowns",
    "rush_attempts": "rushing attempts",
    "completions": "completions",

    # Tennis
    "player_aces": "aces",
    "aces": "aces",
    "player_double_faults": "double faults",
    "double_faults": "double faults",
    "player_games_won": "games won",
    "player_sets_won": "sets won",

    # PGA
    "player_birdies": "birdies",
    "birdies": "birdies",
    "player_bogeys": "bogeys",
    "player_pars": "pars",
    "player_fairways_hit": "fairways",
    "player_greens_in_regulation": "greens",
    "strokes": "strokes",

    # Soccer
    "goals": "goals",
    "shots": "shots",
    "shots_on_target": "shots on target",

    # UFC
    "fighter_significant_strikes": "significant strikes",
    "fighter_takedowns": "takedowns",
    "fighter_knockdowns": "knockdowns",
    "fighter_submission_attempts": "submissions",
    "fighter_fight_time": "fight time",
}


def format_market_label(prop_type: str) -> str:
    normalized = prop_type.upper().strip()
    return MARKET_LABELS.get(
        normalized,
        normalized.replace("_", " ").title(),
    )


def market_to_category(market: str) -> str:
    normalized = (market or "").strip().lower()
    if not normalized:
        return ""

    return CATEGORY_LABELS.get(
        normalized,
        normalized
        .replace("player_", "")
        .replace("batter_", "")
        .replace("pitcher_", "")
        .replace("fighter_", "")
        .replace("_", " "),
    )


def format_sport_label(sport_key: str) -> str:
    mappings = {
        "basketball_nba": "NBA",
        "basketball_wnba": "WNBA",
        "americanfootball_nfl": "NFL",
        "baseball_mlb": "MLB",
    }

    if sport_key in mappings:
        return mappings[sport_key]
    if sport_key.startswith("tennis_"):
        return "TENNIS"
    if sport_key.startswith("golf_"):
        return "PGA"
    if sport_key.startswith("soccer_"):
        return "SOCCER"
    return sport_key.upper()


def player_image_path(player_name: str) -> str:
    filename = re.sub(
        r"[^a-z0-9]+",
        "_",
        player_name.lower(),
    ).strip("_")
    return f"assets/players/{filename}.png"
