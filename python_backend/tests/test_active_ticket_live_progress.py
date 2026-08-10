from types import SimpleNamespace

import main
from services.live_stats_service import LiveStatSnapshot


def test_active_ticket_uses_live_provider_status(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "get_live_player_stat_snapshot",
        lambda **_kwargs: LiveStatSnapshot(
            14.0, False, "InProgress", "espn", "Q3 • 4:21"
        ),
    )
    leg = SimpleNamespace(
        player="Test Player",
        market="Points",
        sport="NFL",
        event_id="game-1",
        matchup="AWAY @ HOME",
        game_start_time="2026-07-26T20:00:00Z",
        game_completed=False,
        game_status="scheduled",
        side="over",
        line=20.5,
        prop_id="prop-1",
        sportsbook="PrizePicks",
        odds=None,
    )

    rows = main._graded_slip_legs(
        SimpleNamespace(legs=[leg]),
        season="2026",
    )

    assert rows[0]["result_value"] == 14.0
    assert rows[0]["game_status"] == "Live"
    assert rows[0]["result_status"] == "live"
    assert rows[0]["live_stat_status"] == "InProgress"
    assert rows[0]["game_detail"] == "Q3 • 4:21"


def test_active_ticket_final_snapshot_grades_the_leg(monkeypatch) -> None:
    monkeypatch.setattr(
        main,
        "get_live_player_stat_snapshot",
        lambda **_kwargs: LiveStatSnapshot(24.0, True, "Final"),
    )
    leg = SimpleNamespace(
        player="Test Player",
        market="Points",
        sport="NBA",
        event_id="game-1",
        matchup="AWAY @ HOME",
        game_start_time="2026-07-26T20:00:00Z",
        game_completed=False,
        game_status="live",
        side="over",
        line=20.5,
        prop_id="prop-1",
        sportsbook="PrizePicks",
        odds=None,
    )

    rows = main._graded_slip_legs(
        SimpleNamespace(legs=[leg]),
        season="2026",
    )

    assert rows[0]["game_status"] == "Final"
    assert rows[0]["result_status"] == "win"


def test_active_ticket_reports_irreversible_over_win_before_final() -> None:
    assert main._grade_active_ticket_leg(
        side="over",
        current=6.0,
        line=5.5,
        game_status="Live",
    ) == "win"
    assert main._grade_active_ticket_leg(
        side="under",
        current=6.0,
        line=5.5,
        game_status="Live",
    ) == "loss"
