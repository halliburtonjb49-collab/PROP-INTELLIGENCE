from datetime import datetime, timezone

import pytest

from services import owner_command_center_service as command_center


@pytest.fixture(autouse=True)
def _disable_external_owner_action_storage(monkeypatch) -> None:
    monkeypatch.setattr(
        command_center,
        "owner_action_snapshot",
        lambda: {
            "available": False,
            "quarantines": {},
            "acknowledgements": {},
            "history": [],
        },
    )


def test_command_center_windows_are_bounded() -> None:
    now = datetime(2026, 8, 11, 15, 0, tzinfo=timezone.utc)
    start, end, label = command_center.command_center_window("yesterday", now=now)

    assert start.isoformat() == "2026-08-10T00:00:00+00:00"
    assert end.isoformat() == "2026-08-11T00:00:00+00:00"
    assert label == "Yesterday"

    with pytest.raises(ValueError):
        command_center.command_center_window(
            "custom",
            now=now,
            start="2026-08-11T15:00:00Z",
            end="2026-08-10T15:00:00Z",
        )


def test_command_center_combines_truthful_metrics_and_service_health(monkeypatch) -> None:
    monkeypatch.setattr(
        command_center,
        "_database_metrics",
        lambda _start, _end: {
            "available": True,
            "activeUsers": 4,
            "newUsers": 2,
            "totalUsers": 100,
            "coreSubscribers": 12,
            "proSubscribers": 8,
            "predictionsGenerated": 40,
            "apiRequests": 300,
            "mrr": None,
            "mrrAvailable": False,
            "mrrNote": "Billing periods are not connected.",
        },
    )
    monkeypatch.setattr(
        command_center._PROP_CACHE,
        "load_props",
        lambda: [
            {
                "sport": "WNBA",
                "game_status": "live",
                "game_id": "game-1",
                "confidence": .72,
                "prediction": "OVER",
            },
            {
                "sport": "NFL",
                "game_status": "scheduled",
                "game_id": "game-2",
                "confidence": 68,
                "prediction": "WAIT",
            },
        ],
    )
    monkeypatch.setattr(command_center, "cache_health", lambda: {"available": True, "mode": "redis"})
    monkeypatch.setattr(command_center, "queue_health", lambda: {"available": True, "workers": 2, "queued": 0, "failed": 0})
    monkeypatch.setattr(command_center, "scoreboard_latency_snapshot", lambda: {"status": "ok", "lastMs": 210, "sampleCount": 4})
    monkeypatch.setattr(command_center, "recent_pipeline_runs", lambda _limit: [])
    monkeypatch.setattr(command_center, "summarize_pipeline_health", lambda _runs: {"healthy": True, "activeFailures": []})
    monkeypatch.setattr(
        command_center,
        "provider_availability_snapshot",
        lambda now=None: {
            "sports": [{
                "sport": "WNBA",
                "status": "HEALTHY",
                "lastSuccessfulSync": "2026-08-11T14:55:00Z",
                "observationsFound": 20,
                "missingData": [],
            }],
            "alerts": [],
        },
    )

    result = command_center.owner_command_center_snapshot(
        "today",
        now=datetime(2026, 8, 11, 15, 0, tzinfo=timezone.utc),
    )
    metrics = {item["key"]: item for item in result["overview"]}

    assert metrics["activeUsers"]["value"] == 4
    assert metrics["coreSubscribers"]["value"] == 12
    assert metrics["proSubscribers"]["value"] == 8
    assert metrics["propsAvailable"]["value"] == 2
    assert metrics["gamesLive"]["value"] == 1
    assert metrics["averageConfidence"]["value"] == .7
    assert metrics["mrr"]["value"] is None
    assert metrics["mrr"]["status"] == "unavailable"
    assert any(row["service"] == "WNBA availability" for row in result["services"])


def test_inventory_flags_stale_duplicates_conflicts_and_rolls_up_providers() -> None:
    now = datetime(2026, 8, 11, 15, 0, tzinfo=timezone.utc)
    base = {
        "game_id": "game-1",
        "player_name": "Test Player",
        "prop_type": "Points",
        "sport": "WNBA",
        "home_team": "Home",
        "away_team": "Away",
        "prediction": "OVER",
        "confidence": .72,
        "game_status": "scheduled",
        "opening_line": 18.5,
    }
    inventory = command_center._inventory_snapshot(
        [
            {**base, "bookmaker": "PrizePicks", "current_line": 18.5,
             "line_updated_at": "2026-08-11T14:55:00Z"},
            {**base, "bookmaker": "PrizePicks", "current_line": 18.5,
             "line_updated_at": "2026-08-11T14:55:00Z"},
            {**base, "bookmaker": "Underdog", "current_line": 25.5,
             "prediction": "", "confidence": None,
             "line_updated_at": "2026-08-11T12:00:00Z"},
        ],
        now=now,
    )

    assert inventory["total"] == 3
    assert inventory["flagged"] == 3
    alerts = {row["key"]: row["count"] for row in inventory["alerts"]}
    assert alerts["duplicate"] == 2
    assert alerts["provider_conflict"] == 3
    assert alerts["stale_line"] == 1
    assert alerts["missing_projection"] == 1
    providers = {row["provider"]: row for row in inventory["providers"]}
    assert providers["PrizePicks"]["props"] == 2
    assert providers["Underdog"]["status"] == "PARTIAL"
    assert inventory["facets"]["sports"] == ["WNBA"]