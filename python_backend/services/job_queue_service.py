"""Redis Queue integration for durable, retryable background work."""

from __future__ import annotations

import os
from typing import Any

from redis import Redis
from rq import Queue, Retry

REDIS_URL = os.getenv("REDIS_URL", "").strip()
QUEUE_NAME = os.getenv("BACKGROUND_QUEUE_NAME", "prop-intelligence")


def _queue() -> Queue | None:
    if not REDIS_URL:
        return None
    connection = Redis.from_url(
        REDIS_URL,
        socket_connect_timeout=2,
        socket_timeout=2,
        health_check_interval=30,
    )
    return Queue(QUEUE_NAME, connection=connection)


def enqueue(function_name: str, *, job_id: str | None = None) -> dict[str, Any] | None:
    queue = _queue()
    if queue is None:
        return None
    try:
        job = queue.enqueue(
            function_name,
            job_id=job_id,
            job_timeout=1800,
            result_ttl=86400,
            failure_ttl=604800,
            retry=Retry(max=3, interval=[30, 120, 300]),
        )
        return {"id": job.id, "status": job.get_status(), "queue": QUEUE_NAME}
    except Exception:
        return None


def health() -> dict[str, object]:
    queue = _queue()
    if queue is None:
        return {"configured": False, "available": False, "mode": "in-process"}
    try:
        queue.connection.ping()
        return {
            "configured": True,
            "available": True,
            "mode": "rq",
            "queue": QUEUE_NAME,
            "queued": queue.count,
        }
    except Exception as exc:
        return {
            "configured": True,
            "available": False,
            "mode": "in-process-fallback",
            "error": str(exc),
        }
