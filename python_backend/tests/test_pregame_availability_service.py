from types import SimpleNamespace

import pytest

from services.pregame_availability_service import assess_pregame_availability


def prop(sport: str, market: str = "Points", **values):
    base = dict(
        sport=sport,
        market=market,
        marketKey=market,
        category=market,
        injuryStatus="healthy",
        roleChange="UNKNOWN",
    )
    base.update(values)
    return SimpleNamespace(**base)


def observation(
    *,
    entity: str = "LINEUP",
    status: str = "CONFIRMED_STARTER",
    confirmed: bool = True,
    payload: dict | None = None,
):
    return {
        "entityType": entity,
        "status": status,
        "confirmed": confirmed,
        "provider": "TEST_PROVIDER",
        "payload": payload or {},
        "observedAt": "2026-08-11T01:00:00+00:00",
    }


@pytest.mark.parametrize("sport", ["WNBA", "NBA"])
def test_basketball_requires_a_confirmed_rotation_role(sport):
    waiting = assess_pregame_availability(prop(sport))
    assert waiting["priority"] == 1
    assert waiting["status"] == "WAIT"
    assert "Starter or bench role" in waiting["warnings"][0]

    ready = assess_pregame_availability(
        prop(sport), observations=[observation()]
    )
    assert ready["status"] == "READY"
    assert ready["ready"] is True


def test_basketball_minutes_restriction_blocks_readiness():
    result = assess_pregame_availability(
        prop("WNBA"),
        observations=[observation(payload={"minutesRestriction": "24-minute cap"})],
    )
    assert result["status"] == "WAIT"
    assert any(factor["key"] == "minutes_restriction" and factor["status"] == "RESTRICTED" for factor in result["factors"])


def test_mlb_hitter_needs_confirmed_batting_order():
    projected = assess_pregame_availability(
        prop("MLB", "Hits"),
        observations=[observation(status="PROJECTED_STARTER", confirmed=False, payload={"battingOrder": 2})],
    )
    assert projected["priority"] == 2
    assert projected["status"] == "WAIT"

    confirmed = assess_pregame_availability(
        prop("MLB", "Hits"),
        observations=[observation(payload={"battingOrder": 2})],
    )
    assert confirmed["status"] == "READY"


def test_mlb_pitcher_needs_official_starter_not_probable_only():
    result = assess_pregame_availability(
        prop("MLB", "Pitcher Strikeouts"),
        observations=[observation(status="PROJECTED_STARTER", confirmed=False, payload={"role": "PROBABLE_PITCHER"})],
    )
    assert result["status"] == "WAIT"
    assert result["factors"][1]["key"] == "starting_pitcher"


def test_mlb_scratch_is_unavailable():
    result = assess_pregame_availability(
        prop("MLB", "Hits"),
        observations=[observation(status="SCRATCHED", payload={"battingOrder": 1})],
    )
    assert result["status"] == "UNAVAILABLE"
    assert result["score"] == 0


def test_nfl_qb_requires_active_status_and_confirmed_start():
    active_only = assess_pregame_availability(
        prop("NFL", "Passing Yards"),
        observations=[observation(status="ACTIVE", payload={"position": "QB"})],
    )
    assert active_only["priority"] == 3
    assert active_only["status"] == "WAIT"

    starter = assess_pregame_availability(
        prop("NFL", "Passing Yards"),
        observations=[observation(payload={"position": "QB"})],
    )
    assert starter["status"] == "READY"


def test_nfl_snap_restriction_blocks_readiness():
    result = assess_pregame_availability(
        prop("NFL", "Receiving Yards"),
        observations=[observation(payload={"snapRestriction": "limited package"})],
    )
    assert result["status"] == "WAIT"
    assert any(factor["key"] == "snap_restriction" and factor["status"] == "RESTRICTED" for factor in result["factors"])


def test_nfl_assessment_exposes_universal_expected_role():
    result = assess_pregame_availability(
        prop("NFL", "Receiving Yards"),
        observations=[observation(
            status="ACTIVE",
            payload={
                "position": "WR",
                "role": "WR2",
                "depthRank": 2,
                "expectedSnapPct": 88,
                "routeParticipation": 91,
                "targetShare": 24,
            },
        )],
    )
    assert result["playerRole"]["role"] == "WR2"
    assert result["playerRole"]["nflExpectedRole"]["routeParticipation"] == 91


def test_nhl_goalie_does_not_require_a_skater_line_combination():
    result = assess_pregame_availability(
        prop("NHL", "Goalie Saves"),
        observations=[observation(payload={"role": "STARTING_GOALIE", "position": "GOALIE"})],
    )
    assert result["priority"] == 4
    assert result["status"] == "READY"


def test_nhl_skater_requires_line_combination():
    rows = [observation()]
    waiting = assess_pregame_availability(prop("NHL", "Shots on Goal"), observations=rows)
    assert waiting["status"] == "WAIT"

    rows.append(observation(entity="LINE_COMBINATION", status="LINE_1", payload={"line": 1}))
    ready = assess_pregame_availability(prop("NHL", "Shots on Goal"), observations=rows)
    assert ready["status"] == "READY"


def test_soccer_requires_official_team_sheet_and_formation():
    sheet = observation(entity="TEAM_SHEET", status="STARTING_XI")
    waiting = assess_pregame_availability(prop("SOCCER", "Shots"), observations=[sheet])
    assert waiting["status"] == "WAIT"

    formation = observation(entity="TEAM_SHEET", status="TEAM_CONFIRMED", payload={"formation": "4-3-3"})
    ready = assess_pregame_availability(
        prop("SOCCER", "Shots"),
        observations=[sheet],
        event_observations=[formation],
    )
    assert ready["status"] == "READY"


def test_unresolved_injury_blocks_every_sport():
    result = assess_pregame_availability(
        prop("NBA", injuryStatus="questionable"),
        observations=[observation()],
    )
    assert result["status"] == "WAIT"
    assert result["factors"][0]["status"] == "UNSETTLED"


def test_official_role_confirms_participation_without_separate_injury_row():
    result = assess_pregame_availability(
        prop("SOCCER", "Shots", injuryStatus="unknown"),
        observations=[observation(entity="TEAM_SHEET", status="STARTING_XI")],
        event_observations=[observation(entity="TEAM_SHEET", status="TEAM_CONFIRMED", payload={"formation": "4-3-3"})],
    )
    assert result["status"] == "READY"
    assert result["factors"][0]["detail"].startswith("Official game-role")

def test_non_target_sports_do_not_receive_a_generic_assessment():
    assert assess_pregame_availability(prop("CRICKET")) == {}
