from services.live_stats_service import (
    SPORT_CONFIG,
    _espn_snapshot_from_logs,
    _game_detail,
    _golf_round_value,
    _mlb_snapshot_from_feed,
    _mlb_statsapi_snapshot,
    extract_prop_value,
    find_player_match_in_boxscores,
)


def test_espn_completed_boxscore_grades_wnba_pra_by_matchup() -> None:
    snapshot = _espn_snapshot_from_logs(
        logs=[{
            "PLAYER_NAME": "Aliyah Boston",
            "GAME_ID": "401857107",
            "MATCHUP": "Indiana Fever at Minnesota Lynx",
            "PTS": 18,
            "REB": 9,
            "AST": 4,
        }],
        player_name="Aliyah Boston",
        prop_type="points rebounds assists",
        event_id="different-provider-id",
        matchup="Indiana Fever @ Minnesota Lynx",
    )

    assert snapshot.value == 31
    assert snapshot.completed is True
    assert snapshot.status == "Final"
    assert snapshot.source == "espn"


def test_espn_completed_boxscore_grades_combination_and_double_double() -> None:
    logs = [{
        "PLAYER_NAME": "Aliyah Boston",
        "GAME_ID": "401857107",
        "MATCHUP": "Indiana Fever at Minnesota Lynx",
        "PTS": 15,
        "REB": 11,
        "AST": 4,
        "STL": 1,
        "BLK": 2,
    }]
    points_rebounds = _espn_snapshot_from_logs(
        logs=logs,
        player_name="Aliyah Boston",
        prop_type="Player Points Rebounds",
        event_id="401857107",
    )
    double_double = _espn_snapshot_from_logs(
        logs=logs,
        player_name="Aliyah Boston",
        prop_type="Player Double Double",
        event_id="401857107",
    )

    assert points_rebounds.value == 26
    assert double_double.value == 1
    assert double_double.completed is True


def test_espn_in_progress_boxscore_updates_combo_market() -> None:
    snapshot = _espn_snapshot_from_logs(
        logs=[{
            "PLAYER_NAME": "Ariel Atkins",
            "GAME_ID": "live-game",
            "MATCHUP": "Golden State Valkyries at Los Angeles Sparks",
            "PTS": 8,
            "REB": 4,
            "AST": 2,
            "GAME_STATUS": "Live",
            "GAME_COMPLETED": False,
            "GAME_DETAIL": "Q3 • 4:21",
        }],
        player_name="Ariel Atkins",
        prop_type="Player Points Rebounds",
        event_id="live-game",
    )

    assert snapshot.value == 12
    assert snapshot.completed is False
    assert snapshot.status == "Live"
    assert snapshot.game_detail == "Q3 • 4:21"


def test_sportsdata_game_detail_normalizes_sport_periods() -> None:
    assert _game_detail({
        "Status": "InProgress",
        "Quarter": 3,
        "TimeRemainingMinutes": 4,
        "TimeRemainingSeconds": 7,
    }, "NFL") == "Q3 • 4:07"
    assert _game_detail({
        "Status": "InProgress",
        "Period": 2,
        "TimeRemaining": "8:15",
    }, "NHL") == "P2 • 8:15"
    assert _game_detail({
        "Status": "InProgress",
        "Inning": 6,
        "InningHalf": "Top",
    }, "MLB") == "TOP 6"


def test_live_boxscore_extracts_prefixed_basketball_markets() -> None:
    row = {"Points": 10, "Rebounds": 5, "Assists": 3}

    assert extract_prop_value(row, "Player Points") == 10
    assert extract_prop_value(row, "Player Points Rebounds") == 15
    assert extract_prop_value(row, "Player Points Assists") == 13
    assert extract_prop_value(row, "Player Rebounds Assists") == 8
    assert extract_prop_value(row, "Player Points Rebounds Assists") == 18
    assert extract_prop_value(row, "PTS+REBS+ASTS") == 18


def test_nfl_live_boxscores_are_configured() -> None:
    assert SPORT_CONFIG["NFL"]["live_boxscores_path"] == "/BoxScores/{date}"


def test_golf_round_markets_derive_from_holes() -> None:
    round_row = {
        "Holes": [
            {"Par": 4, "Score": 3},
            {"Par": 4, "Score": 4},
            {"Par": 3, "Score": 4},
        ]
    }
    assert _golf_round_value(round_row, "birdies") == 1
    assert _golf_round_value(round_row, "pars") == 1
    assert _golf_round_value(round_row, "bogeys") == 1
    assert _golf_round_value(round_row, "round score") == 11


def test_boxscore_player_is_scoped_to_matchup() -> None:
    games = [
        {
            "Game": {"AwayTeam": "NY", "HomeTeam": "LA"},
            "PlayerGames": [{"Name": "Alex Smith", "Team": "NY", "Points": 10}],
        },
        {
            "Game": {"AwayTeam": "CHI", "HomeTeam": "DAL"},
            "PlayerGames": [{"Name": "Alex Smith", "Team": "CHI", "Points": 20}],
        },
    ]
    match = find_player_match_in_boxscores(
        boxscores=games,
        player_name="Alex Smith",
        matchup="CHI @ DAL",
    )
    assert match is not None
    assert match[0]["Points"] == 20


def test_ambiguous_player_without_event_context_stays_unresolved() -> None:
    games = [
        {"PlayerGames": [{"Name": "Alex Smith", "Points": 10}]},
        {"PlayerGames": [{"Name": "Alex Smith", "Points": 20}]},
    ]
    assert find_player_match_in_boxscores(
        boxscores=games,
        player_name="Alex Smith",
    ) is None


def test_mlb_official_live_feed_updates_pitcher_strikeouts() -> None:
    snapshot = _mlb_snapshot_from_feed(
        feed={
            "gameData": {
                "status": {
                    "abstractGameState": "Live",
                    "detailedState": "In Progress",
                }
            },
            "liveData": {
                "linescore": {
                    "currentInningOrdinal": "6th",
                    "inningHalf": "Top",
                },
                "boxscore": {
                    "teams": {
                        "away": {"players": {}},
                        "home": {
                            "players": {
                                "ID123": {
                                    "person": {"fullName": "Brandon Young"},
                                    "stats": {
                                        "pitching": {"strikeOuts": 6},
                                        "batting": {},
                                    },
                                }
                            }
                        },
                    }
                },
            },
        },
        player_name="Brandon Young",
        prop_type="Pitcher Strikeouts",
    )

    assert snapshot.value == 6
    assert snapshot.completed is False
    assert snapshot.status == "Live"
    assert snapshot.source == "mlb-statsapi"
    assert snapshot.game_detail == "TOP 6th"


def test_mlb_official_feed_does_not_turn_missing_player_into_zero() -> None:
    snapshot = _mlb_snapshot_from_feed(
        feed={
            "gameData": {"status": {"abstractGameState": "Live"}},
            "liveData": {
                "boxscore": {
                    "teams": {
                        "away": {"players": {}},
                        "home": {"players": {}},
                    }
                }
            },
        },
        player_name="Missing Player",
        prop_type="Pitcher Strikeouts",
    )

    assert snapshot.value is None
    assert snapshot.status == "mlb_player_not_found"


def test_mlb_series_match_uses_game_closest_to_prop_start(monkeypatch) -> None:
    schedule = {
        "dates": [{
            "games": [
                {
                    "gamePk": 100,
                    "gameDate": "2026-08-16T17:40:00Z",
                    "teams": {
                        "away": {"team": {"name": "St. Louis Cardinals"}},
                        "home": {"team": {"name": "Cincinnati Reds"}},
                    },
                },
                {
                    "gamePk": 101,
                    "gameDate": "2026-08-17T17:41:00Z",
                    "teams": {
                        "away": {"team": {"name": "St. Louis Cardinals"}},
                        "home": {"team": {"name": "Cincinnati Reds"}},
                    },
                },
            ]
        }]
    }
    feed = {
        "gameData": {"status": {"abstractGameState": "Live"}},
        "liveData": {
            "boxscore": {
                "teams": {
                    "away": {
                        "players": {
                            "ID1": {
                                "person": {"fullName": "Quinn Mathews"},
                                "stats": {"pitching": {"strikeOuts": 7}},
                            }
                        }
                    },
                    "home": {"players": {}},
                }
            }
        },
    }

    def fake_cached_json(**kwargs):
        if str(kwargs["key"]).startswith("schedule:"):
            return schedule
        assert kwargs["key"] == "feed:101"
        return feed

    monkeypatch.setattr(
        "services.live_stats_service._cached_json",
        fake_cached_json,
    )
    snapshot = _mlb_statsapi_snapshot(
        player_name="Quinn Mathews",
        prop_type="Pitcher Strikeouts",
        matchup="St. Louis Cardinals @ Cincinnati Reds",
        game_start_time="2026-08-17T17:41:00Z",
    )

    assert snapshot.value == 7
    assert snapshot.status == "Live"
