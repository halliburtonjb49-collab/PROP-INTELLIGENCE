from models.prop_builder import (
    PropBuilderLeg,
    PropBuilderRequest,
)
from services.prop_builder_service import (
    _merge_locked_and_new_legs,
)


def _leg(
    prop_id: str,
    position: int = 0,
) -> PropBuilderLeg:
    return PropBuilderLeg(
        prop_id=prop_id,
        event_id=f"event-{prop_id}",
        player=f"Player {prop_id}",
        sport="WNBA",
        matchup="A vs B",
        prop_site="PrizePicks",
        market="points",
        line=15.5,
        side="OVER",
        odds=-110,
        edge=65,
        confidence=70,
        game_time="",
        builder_position=position,
    )


def test_request_defaults() -> None:
    request = PropBuilderRequest(
        sports=["WNBA"],
        prop_sites=["PrizePicks"],
        leg_count=3,
        minimum_edge=60,
        minimum_confidence=65,
        same_game_allowed=False,
        build_mode="SAME_SPORT",
        side_preference="ANY",
    )
    assert request.risk_mode == "BALANCED"
    assert request.correlation_guard_enabled is True
    assert request.markets == []


def test_locked_positions_are_preserved() -> None:
    locked = [
        _leg("locked-1", position=1),
    ]
    new = [
        _leg("new-1"),
        _leg("new-2"),
    ]
    merged = _merge_locked_and_new_legs(
        locked_legs=locked,
        new_legs=new,
        total_count=3,
    )
    assert len(merged) == 3
    assert merged[1].prop_id == "locked-1"


def test_leg_line_snapshot_defaults() -> None:
    leg = _leg("one")
    assert leg.movement_status == "UNCHANGED"
    assert leg.result_status == "pending"
