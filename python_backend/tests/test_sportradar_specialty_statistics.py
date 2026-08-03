from datetime import date

from providers.sportradar_specialty_statistics import (
    normalize_mma_summaries,
    normalize_golf_leaderboard,
    normalize_tennis_summaries,
)


def test_normalizes_completed_tennis_statistics() -> None:
    payload = {"summaries": [{
        "sport_event": {
            "id": "match-1",
            "sport_event_context": {"category": {"name": "ATP"}},
            "competitors": [
                {"id": "p1", "name": "Player One", "qualifier": "home"},
                {"id": "p2", "name": "Player Two", "qualifier": "away"},
            ],
        },
        "sport_event_status": {
            "status": "closed", "winner_id": "p1",
            "period_scores": [
                {"home_score": 6, "away_score": 4},
                {"home_score": 7, "away_score": 5},
            ],
        },
        "statistics": {"totals": {"competitors": [
            {"id": "p1", "statistics": {
                "aces": 8, "double_faults": 2, "breakpoints_won": 3,
            }},
            {"id": "p2", "statistics": {
                "aces": 4, "double_faults": 5, "breakpoints_won": 1,
            }},
        ]}},
    }]}
    rows = normalize_tennis_summaries(payload, target_date=date(2026, 8, 3))
    assert len(rows) == 2
    assert rows[0]["stats"] == {
        "sets_won": 2.0, "games_won": 13.0, "match_win": 1.0,
        "aces": 8.0, "double_faults": 2.0, "breakpoints_won": 3.0,
    }
    assert rows[1]["stats"]["games_won"] == 9.0


def test_normalizes_completed_ufc_statistics_and_fight_time() -> None:
    payload = {"summaries": [{
        "sport_event": {"id": "fight-1", "competitors": [
            {"id": "f1", "name": "Fighter One"},
            {"id": "f2", "name": "Fighter Two"},
        ]},
        "sport_event_status": {
            "status": "ended", "winner_id": "f2",
            "final_round": 2, "final_round_length": "1:30",
        },
        "statistics": {"totals": {"competitors": [{
            "id": "f1", "statistics": {
                "significant_strikes": 31, "total_strikes": 42,
                "takedowns": 2, "knockdowns": 1,
                "submission_attempts": 0,
            },
        }, {"id": "f2", "statistics": {"significant_strikes": 40}}]}},
    }]}
    rows = normalize_mma_summaries(payload, target_date=date(2026, 8, 3))
    assert len(rows) == 2
    assert rows[0]["stats"]["fight_time_seconds"] == 390.0
    assert rows[0]["stats"]["significant_strikes"] == 31.0
    assert rows[1]["stats"]["fight_win"] == 1.0


def test_normalizes_sportradar_golf_round_statistics() -> None:
    rows = normalize_golf_leaderboard({"leaderboard": [{
        "player": {"id": "g1", "first_name": "Test", "last_name": "Golfer"},
        "rounds": [{
            "sequence": 2, "strokes": 68, "birdies": 5,
            "bogeys": 1, "pars": 12, "eagles": 0,
        }],
    }]}, target_date=date(2026, 8, 3), tournament_id="tour-1", round_number=2)
    assert len(rows) == 1
    assert rows[0]["event_id"] == "tour-1-r2"
    assert rows[0]["stats"]["round_score"] == 68.0
    assert rows[0]["stats"]["birdies"] == 5.0
