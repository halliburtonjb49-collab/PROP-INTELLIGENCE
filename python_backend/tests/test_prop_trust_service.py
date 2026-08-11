from datetime import datetime, timedelta, timezone

from services.prop_trust_service import build_prop_trust, build_research_capsule


def _row(now: datetime) -> dict[str, object]:
    return {
        "player": "Test Player", "sport": "NBA", "market": "Points",
        "line": 24.5, "currentLine": 24.5, "openingLine": 24.0,
        "sportsbook": "PrizePicks", "eventId": "event-1",
        "startTimeUtc": (now + timedelta(hours=4)).isoformat(),
        "lastUpdatedUtc": (now - timedelta(minutes=4)).isoformat(),
        "dataQualityScore": .96, "marketBookCount": 4,
        "verificationStatus": "verified", "playerIdentityConfidence": .98,
        "selectable": True, "projectionSampleSize": 1200,
        "projection": 26.1, "historicalHitRate": 62,
        "matchupContext": "Opponent allows above-average production to this role.",
        "projectedMinutes": 35, "usageMultiplier": 1.08,
        "injuryStatus": "healthy", "lineupStatus": "confirmed",
        "recommendationExplanation": "The projection clears the line with stable inputs.",
    }


def test_trust_score_rewards_fresh_complete_verified_multi_source_prop() -> None:
    now = datetime(2026, 8, 8, 18, tzinfo=timezone.utc)
    trust = build_prop_trust(_row(now), now_utc=now)
    assert trust["score"] >= 85
    assert trust["band"] == "EXCELLENT"
    assert trust["researchReady"] is True
    assert trust["confirmingSources"] == 4
    assert len(trust["factors"]) == 6


def test_trust_score_fails_closed_for_stale_unverified_single_source_prop() -> None:
    now = datetime(2026, 8, 8, 18, tzinfo=timezone.utc)
    row = _row(now)
    row.update({
        "lastUpdatedUtc": (now - timedelta(hours=5)).isoformat(),
        "dataStale": True, "dataQualityScore": .35, "marketBookCount": 1,
        "verificationStatus": "unverified", "playerIdentityConfidence": .1,
        "selectable": False, "projectionSampleSize": 0,
        "openingLine": 10, "currentLine": 24.5,
    })
    trust = build_prop_trust(row, now_utc=now)
    assert trust["score"] < 55
    assert trust["band"] == "LIMITED"
    assert trust["researchReady"] is False
    assert any("stale" in warning.lower() for warning in trust["warnings"])


def test_research_capsule_uses_only_available_evidence() -> None:
    now = datetime(2026, 8, 8, 18, tzinfo=timezone.utc)
    row = _row(now)
    trust = build_prop_trust(row, now_utc=now)
    capsule = build_research_capsule(row, trust)
    keys = {item["key"] for item in capsule["items"]}
    assert {"projection", "history", "matchup", "role", "movement"} <= keys
    assert capsule["trustScore"] == trust["score"]
    assert capsule["summary"] == row["recommendationExplanation"]


def test_wnba_capsule_surfaces_minutes_role_and_quality_warnings() -> None:
    now = datetime(2026, 8, 8, 18, tzinfo=timezone.utc)
    row = _row(now)
    row.update({
        "sport": "WNBA",
        "projectedMinutes": None,
        "projectedOpportunity": 32.5,
        "opportunityUnit": "MINUTES",
        "wnbaResearchScore": 72,
        "wnbaMinutesCertainty": 85,
        "wnbaRoleClarity": 65,
        "wnbaResearchWarnings": ["Wait for confirmed starters."],
    })
    capsule = build_research_capsule(row)
    quality = next(
        item for item in capsule["items"]
        if item["key"] == "wnba_research"
    )
    role = next(item for item in capsule["items"] if item["key"] == "role")
    assert quality["value"] == "72/100"
    assert "85/100" in quality["detail"]
    assert "32.5 projected minutes" in role["value"]
    assert "Wait for confirmed starters." in capsule["warnings"]

def test_research_capsule_does_not_invent_missing_history() -> None:
    row = {"line": 10, "player": "A", "sport": "MLB", "market": "Hits"}
    capsule = build_research_capsule(row)
    assert all(item["key"] != "history" for item in capsule["items"])