"""Dependency-aware readiness checks for production traffic admission."""
from database.postgres import check_database_connection, database_is_configured
from services.distributed_cache_service import health as cache_health
from services.job_queue_service import health as queue_health
from services.slip_service import slip_storage_health


def runtime_readiness() -> dict[str, object]:
    checks: dict[str, dict[str, object]] = {}

    database_ok = False
    if database_is_configured():
        try:
            check_database_connection()
            database_ok = True
        except Exception:
            pass
    checks["database"] = {
        "configured": database_is_configured(),
        "available": database_ok,
    }

    cache = cache_health()
    cache_ok = cache.get("configured") is True and cache.get("available") is True
    checks["cache"] = {
        "configured": cache.get("configured") is True,
        "available": cache.get("available") is True,
        "mode": cache.get("mode", "unknown"),
    }

    queue = queue_health()
    queue_ok = queue.get("configured") is True and queue.get("available") is True
    checks["queue"] = {
        "configured": queue.get("configured") is True,
        "available": queue.get("available") is True,
        "mode": queue.get("mode", "unknown"),
    }

    tickets = slip_storage_health()
    ticket_ok = (
        tickets.get("status") == "ok"
        and tickets.get("mode") == "postgresql"
    )
    checks["ticketStorage"] = {
        "available": tickets.get("status") == "ok",
        "mode": tickets.get("mode", "unknown"),
    }

    ready = database_ok and cache_ok and queue_ok and ticket_ok
    return {
        "status": "ready" if ready else "not_ready",
        "ready": ready,
        "checks": checks,
    }
