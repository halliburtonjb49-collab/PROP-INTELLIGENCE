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
    "player_blocks_steals": "blocks + steals",
    "player_turnovers": "turnovers",
    "player_points_rebounds": "points + rebounds",
    "player_points_assists": "points + assists",
    "player_rebounds_assists": "rebounds + assists",
    "player_field_goals": "field goals",
    "player_fantasy_points": "fantasy points",
    "player_double_double": "double-double",
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
    "batter_hits_runs_rbis": "hits + runs + rbis",
    "batter_singles": "singles",
    "batter_doubles": "doubles",
    "batter_triples": "triples",
    "batter_walks": "batter walks",
    "batter_strikeouts": "batter strikeouts",
    "batter_stolen_bases": "stolen bases",
    "pitcher_hits_allowed": "hits allowed",
    "pitcher_walks": "pitcher walks",
    "pitcher_earned_runs": "earned runs",
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
    "player_pass_attempts": "pass attempts",
    "player_pass_completions": "completions",
    "player_pass_interceptions": "passing interceptions",
    "player_pass_rush_yds": "pass + rush yards",
    "player_reception_longest": "longest reception",
    "player_reception_tds": "receiving touchdowns",
    "player_rush_attempts": "rushing attempts",
    "player_rush_longest": "longest rush",
    "player_rush_reception_yds": "rush + receiving yards",
    "player_rush_tds": "rushing touchdowns",
    "player_sacks": "sacks",
    "player_solo_tackles": "solo tackles",
    "player_tackles_assists": "tackles + assists",
    "player_anytime_td": "anytime touchdown",

    # NHL
    "player_power_play_points": "power play points",
    "player_blocked_shots": "blocked shots",
    "player_shots_on_goal": "shots on goal",
    "player_goals": "goals",
    "player_total_saves": "goalie saves",

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
    "player_shots": "shots",
    "player_shots_on_target": "shots on target",
    "player_goal_scorer_anytime": "anytime goalscorer",
    "player_first_goal_scorer": "first goalscorer",
    "player_last_goal_scorer": "last goalscorer",
    "player_to_receive_card": "player card",
    "player_to_receive_red_card": "player red card",

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
        "icehockey_nhl": "NHL",
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
    return f"/player-images/{filename}.png"
