from datetime import datetime, timezone

from models.slip import SlipLeg, SlipResponse
from services import grading_review_service


def _leg(**overrides) -> SlipLeg:
    values = {
        "prop_id": "prop-1",
        "player": "Test Player",
        "sport": "NBA",
        "matchup": "A @ B",
        "sportsbook": "TEST",
        "market": "Points",
        "line": 20.5,
        "side": "OVER",
        "game_start_time": "2026-07-28T10:00:00+00:00",
    }
    values.update(overrides)
    return SlipLeg(**values)


def test_review_queue_flags_overdue_and_unverified_grades(monkeypatch) -> None:
    slip = SlipResponse(
        id="slip-1",
        status="active",
        stake=10,
        potential_payout=20,
        created_at="2026-07-28T09:00:00+00:00",
        legs=[
            _leg(),
            _leg(
                prop_id="prop-2",
                result_status="won",
                result_value=25,
                game_completed=True,
            ),
        ],
    )
    monkeypatch.setattr(grading_review_service, "get_slips", lambda: [slip])
    result = grading_review_service.grading_review_queue(
        now=datetime(2026, 7, 29, tzinfo=timezone.utc),
    )
    assert result["count"] == 2
    assert result["unsettledCount"] == 1
    assert result["questionableCount"] == 1
