from datetime import date

from services.context_research_service import analyze_context_rows


def test_stat_slam_and_rest_splits_use_completed_game_rows() -> None:
    rows = [
        {"game_date": date(2026, 1, 1), "matchup": "A @ B", "points": 10, "rebounds": 5, "assists": 4},
        {"game_date": date(2026, 1, 2), "matchup": "A @ C", "points": 15, "rebounds": 6, "assists": 5},
        {"game_date": date(2026, 1, 5), "matchup": "A vs D", "points": 20, "rebounds": 7, "assists": 6},
    ]

    result = analyze_context_rows(rows, ["points", "rebounds", "assists"], 25)

    assert result["sampleSize"] == 3
    assert result["hits"] == 2
    assert result["hitRate"] == 0.6667
    assert result["games"][0]["value"] == 33
    assert result["restSplits"][0] == {
        "label": "0 DAYS", "games": 1, "average": 26.0, "hitRate": 1.0
    }
    assert result["restSplits"][2] == {
        "label": "2+ DAYS", "games": 1, "average": 33.0, "hitRate": 1.0
    }
