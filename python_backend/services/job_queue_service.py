"""Redis Queue integration for durable, retryable background work."""

from __future__ import annotations

import logging
import os
import uuid
from typing import Any

from redis import Redis
from rq import Queue, Retry, Worker
from rq.registry import FailedJobRegistry, StartedJobRegistry

REDIS_URL = os.getenv("REDIS_URL", "").strip()
QUEUE_NAME = os.getenv("BACKGROUND_QUEUE_NAME", "prop-intelligence")
LOGGER = logging.getLogger(__name__)
SYNC_LOCK_KEY = "lock:prop-intelligence:global-sync"
SYNC_LOCK_TTL_SECONDS = 1800


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


def acquire_global_sync_lock() -> str | None:
    """Acquire the cross-process sync lock and return its ownership token.

    RQ job ids prevent duplicates only inside one scheduling window. A full
    provider run can extend beyond that window, so the worker also needs a
    distributed lock to stop a newer job from overlapping post-processing.
    """
    if not REDIS_URL:
        return "local-no-redis"
    token = uuid.uuid4().hex
    try:
        connection = Redis.from_url(
            REDIS_URL,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
            health_check_interval=30,
        )
        acquired = connection.set(
            SYNC_LOCK_KEY,
            token,
            nx=True,
            ex=SYNC_LOCK_TTL_SECONDS,
        )
        return token if acquired else None
    except Exception as exc:
        # The queue already requires Redis in production. If Redis has a brief
        # read failure, keep the job retryable rather than silently allowing
        # concurrent high-memory syncs.
        LOGGER.warning("Unable to acquire global sync lock error=%s", exc)
        return None


def release_global_sync_lock(token: str) -> None:
    """Release the distributed lock only when this worker still owns it."""
    if not REDIS_URL or token == "local-no-redis":
        return
    try:
        connection = Redis.from_url(
            REDIS_URL,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
            health_check_interval=30,
        )
        connection.eval(
            """
            if redis.call('get', KEYS[1]) == ARGV[1] then
              return redis.call('del', KEYS[1])
            end
            return 0
            """,
            1,
            SYNC_LOCK_KEY,
            token,
        )
    except Exception as exc:
        LOGGER.warning("Unable to release global sync lock error=%s", exc)


def _rq_safe_job_id(job_id: str | None) -> str | None:
    """Normalize application IDs for RQ, which reserves colons for Redis keys."""
    if job_id is None:
        return None
    return job_id.replace(":", "-")


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
    job_id = _rq_safe_job_id(job_id)
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
