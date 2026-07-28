"""Optional shared Redis cache with a no-outage local fallback."""

from __future__ import annotations

import json
import logging
import os
from functools import lru_cache
from typing import Any

from redis import Redis

LOGGER = logging.getLogger(__name__)
REDIS_URL = os.getenv("REDIS_URL", "").strip()


@lru_cache(maxsize=1)
def _client() -> Redis | None:
    if not REDIS_URL:
        return None
    return Redis.from_url(
        REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
        health_check_interval=30,
    )


def get_json(key: str) -> Any | None:
    client = _client()
    if client is None:
        return None
    try:
        value = client.get(key)
        return json.loads(value) if value else None
    except Exception as exc:
        LOGGER.warning("Redis read failed key=%s error=%s", key, exc)
        return None


def set_json(key: str, value: Any, *, ttl_seconds: int) -> bool:
    client = _client()
    if client is None:
        return False
    try:
        client.setex(key, max(1, ttl_seconds), json.dumps(value, default=str))
        return True
    except Exception as exc:
        LOGGER.warning("Redis write failed key=%s error=%s", key, exc)
        return False


def delete(key: str) -> None:
    client = _client()
    if client is None:
        return
    try:
        client.delete(key)
    except Exception as exc:
        LOGGER.warning("Redis delete failed key=%s error=%s", key, exc)


def health() -> dict[str, object]:
    client = _client()
    if client is None:
        return {"configured": False, "available": False, "mode": "local"}
    try:
        return {
            "configured": True,
            "available": bool(client.ping()),
            "mode": "redis",
        }
    except Exception as exc:
        return {
            "configured": True,
            "available": False,
            "mode": "local-fallback",
            "error": str(exc),
        }
