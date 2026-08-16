from datetime import date, datetime, timezone
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
        piTrustScore=confidence,
        piTrustBand="STRONG",
        selectable=True,
        dataStale=False,
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


def test_pi_trust_orders_within_one_decision() -> None:
    briefing = build_briefing([
        _prop("PLAY_NOW", confidence=61),
        _prop("PLAY_NOW", confidence=74),
    ])

    assert [play["piTrustScore"] for play in briefing["leadPlays"]] == [74, 61]
    assert all("confidence" not in play for play in briefing["leadPlays"])


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


def test_sports_to_research_rank_real_playable_opportunities() -> None:
    briefing = build_briefing([
        _prop("LEAN", sport="WNBA", confidence=91),
        _prop("PLAY_NOW", sport="MLB", confidence=78),
        _prop("SHOP", sport="MLB", confidence=74),
        _prop("PASS", sport="NFL", confidence=99),
    ])

    sports = briefing["sportsToResearch"]
    assert [row["sport"] for row in sports] == ["MLB", "WNBA"]
    assert sports[0]["playable"] == 2
    assert sports[0]["playNow"] == 1
    assert sports[0]["averagePiTrust"] == 76


def test_unselectable_prop_is_not_presented_as_playable() -> None:
    briefing = build_briefing([
        _prop("PLAY_NOW", sport="MLB", selectable=False),
    ])

    assert briefing["actionable"] == 0
    assert briefing["leadPlays"] == []
    assert briefing["sportsToResearch"] == []


def test_today_filter_excludes_started_future_and_stale_rows() -> None:
    now = datetime(2026, 8, 16, 16, 0, tzinfo=timezone.utc)
    fresh = (now.replace(minute=55) if now.minute >= 55 else now).isoformat()
    briefing = build_briefing([
        _prop("PLAY_NOW", id="today", startTimeUtc="2026-08-16T20:00:00Z", lastUpdatedUtc=fresh),
        _prop("PLAY_NOW", id="started", startTimeUtc="2026-08-16T15:00:00Z", lastUpdatedUtc=fresh),
        _prop("PLAY_NOW", id="tomorrow", startTimeUtc="2026-08-17T20:00:00Z", lastUpdatedUtc=fresh),
        _prop("PLAY_NOW", id="stale", startTimeUtc="2026-08-16T21:00:00Z", lastUpdatedUtc="2026-08-16T10:00:00Z"),
    ], target_date=date(2026, 8, 16), now=now, stale_after_minutes=180)

    assert briefing["propsOnBoard"] == 1
    assert [play["propId"] for play in briefing["leadPlays"]] == ["today"]
    assert briefing["boardDate"] == "2026-08-16"
