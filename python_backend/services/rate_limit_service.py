"""Distributed token-bucket protection for high-value API responses."""

from __future__ import annotations

import hashlib
import os
import time
from threading import Lock

from redis import Redis

REDIS_URL = os.getenv("REDIS_URL", "").strip()
ANONYMOUS_REQUESTS_PER_MINUTE = max(
    1, int(os.getenv("ANONYMOUS_REQUESTS_PER_MINUTE", "20"))
)
AUTHENTICATED_REQUESTS_PER_MINUTE = max(
    1, int(os.getenv("AUTHENTICATED_REQUESTS_PER_MINUTE", "120"))
)

_BUCKET_SCRIPT = """
local key = KEYS[1]
local now = tonumber(ARGV[1])
local rate = tonumber(ARGV[2])
local capacity = tonumber(ARGV[3])
local ttl = tonumber(ARGV[4])
local values = redis.call('HMGET', key, 'tokens', 'updated')
local tokens = tonumber(values[1]) or capacity
local updated = tonumber(values[2]) or now
tokens = math.min(capacity, tokens + math.max(0, now - updated) * rate)
local allowed = tokens >= 1
if allowed then tokens = tokens - 1 end
redis.call('HMSET', key, 'tokens', tokens, 'updated', now)
redis.call('EXPIRE', key, ttl)
return {allowed and 1 or 0, math.floor(tokens)}
"""

_memory_lock = Lock()
_memory_buckets: dict[str, tuple[float, float]] = {}


def _identity_key(identity: str) -> str:
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()
    return f"rate-limit:v1:{digest}"


def _redis() -> Redis | None:
    if not REDIS_URL:
        return None
    return Redis.from_url(
        REDIS_URL,
        socket_connect_timeout=1,
        socket_timeout=1,
        health_check_interval=30,
    )


def _memory_allow(key: str, *, limit: int, now: float) -> tuple[bool, int]:
    refill_rate = limit / 60.0
    with _memory_lock:
        tokens, updated = _memory_buckets.get(key, (float(limit), now))
        tokens = min(float(limit), tokens + max(0.0, now - updated) * refill_rate)
        allowed = tokens >= 1.0
        if allowed:
            tokens -= 1.0
        _memory_buckets[key] = (tokens, now)
        return allowed, max(0, int(tokens))


def allow_request(
    identity: str,
    *,
    authenticated: bool,
    now: float | None = None,
) -> tuple[bool, int, int]:
    """Return allowed, remaining tokens, and the configured per-minute limit."""
    limit = (
        AUTHENTICATED_REQUESTS_PER_MINUTE
        if authenticated
        else ANONYMOUS_REQUESTS_PER_MINUTE
    )
    timestamp = time.time() if now is None else now
    key = _identity_key(identity)
    client = _redis()
    if client is not None:
        try:
            result = client.eval(
                _BUCKET_SCRIPT,
                1,
                key,
                timestamp,
                limit / 60.0,
                limit,
                120,
            )
            return bool(int(result[0])), int(result[1]), limit
        except Exception:
            # Security protection remains active during a brief Redis outage.
            pass
    allowed, remaining = _memory_allow(key, limit=limit, now=timestamp)
    return allowed, remaining, limit
