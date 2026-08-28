from datetime import datetime, timedelta, timezone

from services import provider_availability_monitor_service as monitor


def test_records_per_sport_provider_health_and_alerts(monkeypatch) -> None:
    stored = {}
    monkeypatch.setattr(monitor, "get_json", lambda _key: None)
    monkeypatch.setattr(
        monitor,
        "set_json",
        lambda key, value, *, ttl_seconds: stored.update(
            {"key": key, "value": value, "ttl": ttl_seconds}
        )
        or True,
    )
    observed = datetime(2026, 8, 11, 14, 0, tzinfo=timezone.utc)

    snapshot = monitor.record_provider_availability(
        [
            {
                "provider": "sportradar-wnba-pregame",
                "games": 3,
                "attempted": 1,
                "observations": 12,
                "confirmedPlayers": 10,
                "confirmedStarters": 5,
                "created": 8,
            },
            {
                "provider": "sportradar-nba-pregame",
                "games": 0,
                "attempted": 0,
                "observations": 0,
                "created": 0,
            },
            {
                "provider": "sportradar-nfl-pregame",
                "created": 0,
                "skipped": "not entitled (403)",
            },
        ],
        observed_at=observed,
    )

    by_sport = {row["sport"]: row for row in snapshot["sports"]}
    assert by_sport["WNBA"]["status"] == "HEALTHY"
    assert by_sport["WNBA"]["gamesChecked"] == 1
    assert by_sport["WNBA"]["playersConfirmed"] == 10
    assert by_sport["WNBA"]["startersConfirmed"] == 5
    assert by_sport["WNBA"]["observationsCreated"] == 8
    assert by_sport["NBA"]["status"] == "HEALTHY"
    assert "No games" in by_sport["NBA"]["detail"]
    assert by_sport["NFL"]["status"] == "OPTIONAL"
    assert snapshot["overallStatus"] == "ATTENTION"
    assert stored["value"] == snapshot


def test_games_without_confirmed_players_are_partial(monkeypatch) -> None:
    monkeypatch.setattr(monitor, "get_json", lambda _key: None)
    monkeypatch.setattr(monitor, "set_json", lambda *_args, **_kwargs: True)

    snapshot = monitor.record_provider_availability(
        [{
            "provider": "sportradar-nhl-pregame",
            "games": 2,
            "attempted": 1,
            "observations": 0,
            "created": 0,
        }]
    )

    nhl = next(row for row in snapshot["sports"] if row["sport"] == "NHL")
    assert nhl["status"] == "PARTIAL"
    assert "no players are confirmed" in nhl["missingData"][0]


def test_failed_game_request_marks_partial_without_erasing_confirmations(monkeypatch) -> None:
    monkeypatch.setattr(monitor, "get_json", lambda _key: None)
    monkeypatch.setattr(monitor, "set_json", lambda *_args, **_kwargs: True)

    snapshot = monitor.record_provider_availability([{
        "provider": "sportradar-wnba-pregame",
        "games": 3,
        "attempted": 3,
        "confirmedPlayers": 10,
        "confirmedStarters": 5,
        "failedEvents": 1,
    }])

    wnba = next(row for row in snapshot["sports"] if row["sport"] == "WNBA")
    assert wnba["status"] == "PARTIAL"
    assert wnba["playersConfirmed"] == 10
    assert wnba["failedEvents"] == 1


def test_read_marks_old_snapshot_stale(monkeypatch) -> None:
    observed = datetime(2026, 8, 11, 14, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(monitor, "get_json", lambda _key: None)
    monkeypatch.setattr(monitor, "set_json", lambda *_args, **_kwargs: True)
    monitor.record_provider_availability(
        [{"provider": "sportradar-nba-pregame", "games": 0, "created": 0}],
        observed_at=observed,
    )

    snapshot = monitor.provider_availability_snapshot(
        now=observed + timedelta(minutes=26),
    )
    nba = next(row for row in snapshot["sports"] if row["sport"] == "NBA")
    assert nba["stale"] is True
    assert nba["status"] == "UNAVAILABLE"
    assert "stale" in nba["missingData"][-1]


def test_read_uses_database_when_shared_cache_is_empty(monkeypatch) -> None:
    observed = datetime(2026, 8, 11, 14, 0, tzinfo=timezone.utc)
    persisted = {
        "generatedAt": observed.isoformat(),
        "refreshIntervalMinutes": 10,
        "staleAfterMinutes": 25,
        "overallStatus": "HEALTHY",
        "sports": [{
            "sport": "MLB",
            "provider": "MLB Stats API / SportsDataIO",
            "status": "HEALTHY",
            "authorizationStatus": "AUTHORIZED",
            "lastAttemptAt": observed.isoformat(),
            "missingData": [],
            "stale": False,
        }],
        "alerts": [],
    }
    monkeypatch.setattr(monitor, "get_json", lambda _key: None)
    monkeypatch.setattr(monitor, "_read_persisted_snapshot", lambda: persisted)
    monkeypatch.setattr(monitor, "_LOCAL_SNAPSHOT", None)

    snapshot = monitor.provider_availability_snapshot(now=observed)

    assert snapshot["overallStatus"] == "HEALTHY"
    assert snapshot["sports"][0]["sport"] == "MLB"


def test_record_reports_when_no_shared_storage_accepts_snapshot(monkeypatch) -> None:
    monkeypatch.setattr(monitor, "set_json", lambda *_args, **_kwargs: False)
    monkeypatch.setattr(monitor, "_persist_snapshot", lambda _snapshot: False)

    snapshot = monitor.record_provider_availability([])

    assert snapshot["storage"] == {
        "redis": False,
        "database": False,
        "durable": False,
    }
