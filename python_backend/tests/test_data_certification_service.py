from datetime import datetime, timedelta, timezone

from services.data_certification_service import production_data_certification


def _row(
    *,
    now: datetime,
    provider: str,
    day: int,
    category: str = "player_points",
    opening: float = 20.5,
    current: float = 21.5,
) -> dict[str, object]:
    return {
        "game_id": f"game-{day}",
        "sport": "basketball_wnba",
        "bookmaker": provider,
        "prop_type": category,
        "opening_line": opening,
        "current_line": current,
        "updated_at": (now - timedelta(minutes=5)).isoformat(),
        "commence_time": (now + timedelta(days=day, hours=2)).isoformat(),
    }


def test_certification_passes_complete_fresh_four_date_catalog() -> None:
    now = datetime(2026, 8, 9, 12, tzinfo=timezone.utc)
    rows = [
        _row(now=now, provider=provider, day=day, category=category)
        for day in range(4)
        for provider in ("prizepicks", "underdog")
        for category in ("player_points", "player_rebounds")
    ]

    report = production_data_certification(
        rows,
        expected_providers=("prizepicks", "underdog"),
        now_utc=now,
    )

    assert report["status"] == "PASS"
    assert report["score"] == 100
    assert report["failureCount"] == 0
    assert {check["key"] for check in report["checks"]} == {
        "catalog", "freshness", "providers", "parity", "slate", "lines",
    }


def test_certification_exposes_missing_provider_stale_data_and_line_gaps() -> None:
    now = datetime(2026, 8, 9, 12, tzinfo=timezone.utc)
    row = _row(now=now, provider="prizepicks", day=0, opening=0, current=21.5)
    row["updated_at"] = (now - timedelta(hours=3)).isoformat()

    report = production_data_certification(
        [row],
        expected_providers=("prizepicks", "underdog", "pick6"),
        now_utc=now,
    )

    assert report["status"] == "FAIL"
    by_key = {check["key"]: check for check in report["checks"]}
    assert by_key["freshness"]["status"] == "FAIL"
    assert by_key["providers"]["status"] == "FAIL"
    assert by_key["lines"]["status"] == "FAIL"
    assert report["days"][0]["status"] == "PASS"
    assert report["days"][1]["status"] == "WARN"
