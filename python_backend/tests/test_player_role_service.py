from types import SimpleNamespace

from services.player_role_service import build_player_role


def prop(sport: str, **values):
    base = {
        "sport": sport,
        "player": "Test Player",
        "playerId": "player-1",
        "injuryStatus": "healthy",
    }
    base.update(values)
    return SimpleNamespace(**base)


def observation(*, status="PROJECTED_STARTER", confirmed=False, payload=None):
    return {
        "status": status,
        "confirmed": confirmed,
        "provider": "NFLVERSE",
        "team": "TEST",
        "payload": payload or {},
        "observedAt": "2026-08-18T12:00:00+00:00",
    }


def test_nfl_expected_role_uses_depth_snaps_routes_and_opportunity():
    role = build_player_role(
        prop("NFL"),
        observations=[observation(payload={
            "position": "WR",
            "role": "WR2",
            "depthRank": 2,
            "expectedSnapPct": 88,
            "routeParticipation": 91,
            "targetShare": 24,
            "redZoneShare": 28,
        })],
    )

    assert role["status"] == "PROJECTED"
    assert role["confirmed"] is False
    assert role["role"] == "WR2"
    assert role["nflExpectedRole"]["expectedSnapPct"] == 88
    assert role["nflExpectedRole"]["routeParticipation"] == 91
    assert 0 < role["nflExpectedRole"]["roleScore"] < 100


def test_nfl_inactive_player_is_unavailable_even_with_strong_usage():
    role = build_player_role(
        prop("NFL", injuryStatus="inactive"),
        observations=[observation(
            status="INACTIVE",
            confirmed=True,
            payload={"depthRank": 1, "expectedSnapPct": 100},
        )],
    )

    assert role["status"] == "UNAVAILABLE"
    assert role["starterProbability"] == 0
    assert role["nflExpectedRole"]["roleScore"] == 0


def test_nhl_opportunity_tracks_line_power_play_and_toi():
    role = build_player_role(
        prop("NHL"),
        observations=[observation(payload={
            "role": "LINE_1",
            "lineNumber": 1,
            "powerPlayUnit": 1,
            "expectedToi": 21,
            "shotRate": .8,
            "teamUsage": .75,
            "opponentFactor": .6,
        })],
    )

    opportunity = role["nhlOpportunity"]
    assert opportunity["lineNumber"] == 1
    assert opportunity["powerPlayUnit"] == 1
    assert opportunity["expectedToi"] == 21
    assert opportunity["opportunityScore"] >= 80
