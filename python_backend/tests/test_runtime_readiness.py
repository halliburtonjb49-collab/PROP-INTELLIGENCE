from services import runtime_readiness_service


def test_readiness_requires_database_cache_queue_and_postgres_tickets(
    monkeypatch,
) -> None:
    monkeypatch.setattr(runtime_readiness_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(runtime_readiness_service, "check_database_connection", lambda: None)
    monkeypatch.setattr(
        runtime_readiness_service,
        "cache_health",
        lambda: {"configured": True, "available": True, "mode": "redis"},
    )
    monkeypatch.setattr(
        runtime_readiness_service,
        "queue_health",
        lambda: {"configured": True, "available": True, "mode": "rq"},
    )
    monkeypatch.setattr(
        runtime_readiness_service,
        "slip_storage_health",
        lambda: {"status": "ok", "mode": "postgresql"},
    )
    result = runtime_readiness_service.runtime_readiness()
    assert result["ready"] is True
    assert result["status"] == "ready"


def test_readiness_fails_closed_when_redis_is_unavailable(monkeypatch) -> None:
    monkeypatch.setattr(runtime_readiness_service, "database_is_configured", lambda: True)
    monkeypatch.setattr(runtime_readiness_service, "check_database_connection", lambda: None)
    monkeypatch.setattr(
        runtime_readiness_service,
        "cache_health",
        lambda: {"configured": True, "available": False, "mode": "local-fallback"},
    )
    monkeypatch.setattr(
        runtime_readiness_service,
        "queue_health",
        lambda: {"configured": True, "available": True, "mode": "rq"},
    )
    monkeypatch.setattr(
        runtime_readiness_service,
        "slip_storage_health",
        lambda: {"status": "ok", "mode": "postgresql"},
    )
    result = runtime_readiness_service.runtime_readiness()
    assert result["ready"] is False
    assert result["status"] == "not_ready"
