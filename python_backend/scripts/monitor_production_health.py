"""External production sentinel for API, publication, and Redis health."""

from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from redis import Redis

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.distributed_cache_service import health as cache_health
from services.operations_notification_service import notify_operations_alert


def _alert(kind: str, summary: str, details: dict[str, object]) -> None:
    redis_url = os.getenv("REDIS_URL", "").strip()
    if redis_url:
        try:
            client = Redis.from_url(redis_url, decode_responses=True, socket_timeout=2)
            allowed = client.set(
                f"alert:production-monitor:{kind}",
                datetime.now(timezone.utc).isoformat(),
                nx=True,
                ex=max(300, int(os.getenv("OPERATIONS_ALERT_COOLDOWN_SECONDS", "1800"))),
            )
            if not allowed:
                return
        except Exception:
            # The condition itself may be Redis failure; delivery must still
            # be attempted when the cooldown store cannot be reached.
            pass
    notify_operations_alert(kind=kind, summary=summary, details=details)


def main() -> int:
    base = os.getenv("API_BASE_URL", "https://api.propsintell.com").rstrip("/")
    failures: list[str] = []
    try:
        response = requests.get(f"{base}/ready", timeout=10)
        if response.status_code != 200:
            failures.append(f"ready_http_{response.status_code}")
    except requests.RequestException as exc:
        failures.append(f"ready_{type(exc).__name__}")
    if failures:
        _alert("api_unavailable", "Production API readiness check failed", {"failures": failures})

    try:
        response = requests.get(f"{base}/api/props/readiness", timeout=15)
        response.raise_for_status()
        feed = response.json()
        count = int(feed.get("count") or 0)
        published = str(feed.get("catalogPublishedAt") or "")
        if count <= 0 or feed.get("catalogPublicationStatus") == "failed":
            _alert("catalog_publication_failed", "Prop catalog is unavailable", {
                "count": count,
                "status": feed.get("catalogPublicationStatus"),
                "error": feed.get("catalogPublicationError"),
            })
        if published:
            stamp = datetime.fromisoformat(published.replace("Z", "+00:00"))
            if stamp.tzinfo is None:
                stamp = stamp.replace(tzinfo=timezone.utc)
            age_minutes = (datetime.now(timezone.utc) - stamp).total_seconds() / 60
            if age_minutes > int(os.getenv("FEED_STALE_ALERT_MINUTES", "45")):
                _alert("feed_stale", "Prop publication is stale", {
                    "ageMinutes": round(age_minutes), "count": count,
                })
    except Exception as exc:
        _alert("catalog_check_failed", "Catalog readiness check failed", {
            "error": type(exc).__name__,
        })

    cache = cache_health()
    utilization = cache.get("memoryUtilization")
    if isinstance(utilization, (int, float)) and utilization >= 0.70:
        _alert("redis_memory_high", "Redis memory exceeded 70%", {
            "utilizationPercent": round(utilization * 100, 1),
            "usedMemoryBytes": cache.get("usedMemoryBytes"),
            "maxMemoryBytes": cache.get("maxMemoryBytes"),
        })
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
