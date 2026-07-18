from services.matchup_profile_service import build_matchup_profiles


def test_matchup_profiles_are_bounded_and_disclosed() -> None:
    handlers = [{"TEAM_ID": 1, "TEAM_NAME": "Defense", "PPP": .72, "POSS": 150, "POSS_PCT": .4}]
    rollers = [{"TEAM_ID": 1, "TEAM_NAME": "Defense", "PPP": .85, "POSS": 100}]
    profiles = build_matchup_profiles(handlers, rollers, "NBA", "2025-26")
    profile = profiles[0]
    assert 0 <= profile["pickRollPressureProxy"] <= 1
    assert 0 <= profile["switchRateProxy"] <= 1
    assert -1 <= profile["defenderDifficulty"] <= 1
    assert "not observed" in profile["source"]


def test_matchup_profiles_handle_missing_rows() -> None:
    assert build_matchup_profiles([], [], "WNBA", "2026") == []
