from datetime import datetime, timezone
from types import SimpleNamespace

from services.daily_briefing_service import MAX_LEAD_PLAYS, build_briefing


def _prop(decision="PASS", *, confidence=50, projection=6.9, sport="MLB", **over):
    base = dict(
        id=f"p-{decision}-{confidence}",
        player="Drew Romo",
        sport=sport,
        market="Batter Hits",
        line=6.5,
        sportsbook="PrizePicks",
        projection=projection,
        evPercentage=4.0,
        verdict={
            "decision": decision,
            "side": "OVER",
            "headline": f"{decision} OVER",
            "reason": "reason",
            "confidence": confidence,
        },
    )
    base.update(over)
    return SimpleNamespace(**base)


def test_a_quiet_day_is_reported_as_a_result() -> None:
    """The failure mode this exists to prevent.

    A briefing that always produces picks teaches people to bet the best of
    nothing. Saying the slate is empty is the more useful answer.
    """

    briefing = build_briefing([_prop("PASS"), _prop("PASS")])

    assert briefing["quietDay"] is True
    assert briefing["actionable"] == 0
    assert briefing["leadPlays"] == []
    assert "not a gap" in briefing["summary"]


def test_plays_lead_over_shops_and_leans() -> None:
    briefing = build_briefing([
        _prop("LEAN", confidence=90),
        _prop("PLAY_NOW", confidence=60),
        _prop("SHOP", confidence=88),
    ])
    order = [play["decision"] for play in briefing["leadPlays"]]

    # A play outranks a shop even when the shop is more confident: the
    # decision is the stronger statement.
    assert order == ["PLAY_NOW", "SHOP", "LEAN"]


def test_confidence_orders_within_one_decision() -> None:
    briefing = build_briefing([
        _prop("PLAY_NOW", confidence=61),
        _prop("PLAY_NOW", confidence=74),
    ])

    assert [play["confidence"] for play in briefing["leadPlays"]] == [74, 61]


def test_the_briefing_stops_listing_and_starts_summarising() -> None:
    # A briefing that lists forty picks is the board with extra steps.
    briefing = build_briefing(
        [_prop("PLAY_NOW", confidence=60 + index) for index in range(20)]
    )

    assert len(briefing["leadPlays"]) == MAX_LEAD_PLAYS
    assert briefing["actionable"] == 20


def test_waiting_props_are_counted_and_explained() -> None:
    briefing = build_briefing([_prop("WAIT"), _prop("WAIT"), _prop("PASS")])

    assert briefing["verdictCounts"]["WAIT"] == 2
    assert any("unresolved" in caveat for caveat in briefing["caveats"])


def test_props_without_a_projection_are_named_not_hidden() -> None:
    briefing = build_briefing([_prop("PASS", projection=None)])

    assert any("no model projection" in caveat for caveat in briefing["caveats"])


def test_an_empty_sport_is_stated_rather_than_left_to_inference() -> None:
    # A sport missing from the board is invisible; a sport named as missing
    # is a fact the reader can act on.
    briefing = build_briefing([_prop("PASS")], empty_sports=["NHL", "NFL"])

    assert "No NFL props are available on today's board." in briefing["caveats"]
    assert "No NHL props are available on today's board." in briefing["caveats"]


def test_an_empty_board_does_not_crash() -> None:
    briefing = build_briefing([])

    assert briefing["propsOnBoard"] == 0
    assert briefing["quietDay"] is True
    assert briefing["sportsCovered"] == []


def test_a_prop_with_no_verdict_is_counted_rather_than_dropped() -> None:
    # Older payloads carry no verdict. They still occupy the board and the
    # count must say so.
    briefing = build_briefing([SimpleNamespace(id="x", sport="MLB", projection=1.0)])

    assert briefing["propsOnBoard"] == 1
    assert briefing["verdictCounts"]["UNJUDGED"] == 1
    assert briefing["actionable"] == 0


def test_the_briefing_is_timestamped() -> None:
    stamp = datetime(2026, 8, 8, 12, 0, tzinfo=timezone.utc)
    briefing = build_briefing([_prop("PASS")], generated_at=stamp)

    assert briefing["generatedAt"] == stamp.isoformat()


def test_sports_covered_are_listed_for_the_reader() -> None:
    briefing = build_briefing([_prop("PASS", sport="MLB"), _prop("PASS", sport="WNBA")])

    assert briefing["sportsCovered"] == ["MLB", "WNBA"]
