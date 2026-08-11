"""Redis Queue integration for durable, retryable background work."""

from __future__ import annotations

import logging
import os
from typing import Any

from redis import Redis
from rq import Queue, Retry, Worker
from rq.registry import FailedJobRegistry, StartedJobRegistry

REDIS_URL = os.getenv("REDIS_URL", "").strip()
QUEUE_NAME = os.getenv("BACKGROUND_QUEUE_NAME", "prop-intelligence")
LOGGER = logging.getLogger(__name__)


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


def enqueue(
    function_name: str,
    *,
    job_id: str | None = None,
    args: tuple[Any, ...] = (),
    kwargs: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    queue = _queue()
    if queue is None:
        return None
    try:
        job = queue.enqueue_call(
            func=function_name,
            args=args,
            kwargs=kwargs or {},
            job_id=job_id,
            timeout=1800,
            result_ttl=86400,
            failure_ttl=604800,
            retry=Retry(max=3, interval=[30, 120, 300]),
        )
        return {"id": job.id, "status": job.get_status(), "queue": QUEUE_NAME}
    except Exception as exc:
        if job_id:
            try:
                existing = queue.fetch_job(job_id)
                if existing is not None:
                    status = existing.get_status(refresh=True)
                    return {
                        "id": existing.id,
                        "status": getattr(status, "value", status),
                        "queue": QUEUE_NAME,
                        "deduplicated": True,
                    }
            except Exception:
                LOGGER.debug(
                    "Unable to inspect existing background job id=%s",
                    job_id,
                    exc_info=True,
                )
        LOGGER.warning(
            "Unable to enqueue background job function=%s job_id=%s error=%s: %s",
            function_name,
            job_id or "auto",
            type(exc).__name__,
            exc,
            exc_info=True,
        )
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
            "started": StartedJobRegistry(
                queue.name,
                connection=queue.connection,
            ).count,
            "failed": FailedJobRegistry(
                queue.name,
                connection=queue.connection,
            ).count,
            "workers": len(Worker.all(queue=queue)),
            "retryPolicy": {
                "maxAttempts": 4,
                "retryIntervalsSeconds": [30, 120, 300],
            },
        }
    except Exception as exc:
        return {
            "configured": True,
            "available": False,
            "mode": "in-process-fallback",
            "error": str(exc),
        }
