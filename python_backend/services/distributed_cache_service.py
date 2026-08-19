"""Optional shared Redis cache with a no-outage local fallback."""

from __future__ import annotations

import json
import logging
import os
import uuid
import zlib
from functools import lru_cache
from typing import Any, Callable, Iterable

from redis import Redis

LOGGER = logging.getLogger(__name__)
REDIS_URL = os.getenv("REDIS_URL", "").strip()
_LAST_WRITE_ERROR: dict[str, str] = {}


def last_write_error(key: str) -> str:
    """Return why the most recent write to ``key`` failed.

    A boolean return told callers that publication failed but never why, so
    the cron surfaced "could not be published to Redis" with the real cause
    (unconfigured URL, timeout, out-of-memory) stranded in a warning line on
    a different service's log stream.
    """

    return _LAST_WRITE_ERROR.get(key, "")


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


@lru_cache(maxsize=1)
def _streaming_client() -> Redis | None:
    """Redis client sized for multi-megabyte catalog publication.

    The shared client's two second socket timeout is right for the small
    reads on the request path, but the catalog publisher issues a series of
    half-megabyte appends followed by a rename. On a busy Key Value instance
    a single one of those round trips can exceed two seconds, which aborted
    the whole publication and left the API serving the previous catalog.
    """

    if not REDIS_URL:
        return None
    return Redis.from_url(
        REDIS_URL,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=30,
        health_check_interval=30,
    )


@lru_cache(maxsize=1)
def _binary_streaming_client() -> Redis | None:
    """Binary client for compressed multi-megabyte publication."""

    if not REDIS_URL:
        return None
    return Redis.from_url(
        REDIS_URL,
        decode_responses=False,
        socket_connect_timeout=5,
        socket_timeout=30,
        health_check_interval=30,
    )


@lru_cache(maxsize=1)
def _binary_client() -> Redis | None:
    """Binary Redis client for compact internal cache payloads."""

    if not REDIS_URL:
        return None
    return Redis.from_url(
        REDIS_URL,
        decode_responses=False,
        socket_connect_timeout=2,
        socket_timeout=5,
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
        _LAST_WRITE_ERROR[key] = "REDIS_URL is not configured"
        return False
    try:
        client.setex(key, max(1, ttl_seconds), json.dumps(value, default=str))
        _LAST_WRITE_ERROR.pop(key, None)
        return True
    except Exception as exc:
        _LAST_WRITE_ERROR[key] = f"{type(exc).__name__}: {exc}"
        LOGGER.warning("Redis write failed key=%s error=%s", key, exc)
        return False


def get_compressed_json(key: str) -> Any | None:
    """Read an internal JSON payload stored with zlib compression."""

    client = _binary_client()
    if client is None:
        return None
    try:
        value = client.get(key)
        if not value:
            return None
        return json.loads(zlib.decompress(value).decode("utf-8"))
    except Exception as exc:
        LOGGER.warning("Redis compressed read failed key=%s error=%s", key, exc)
        return None


def set_compressed_json(key: str, value: Any, *, ttl_seconds: int) -> bool:
    """Write a compact JSON payload for large, read-mostly internal data."""

    client = _binary_client()
    if client is None:
        return False
    try:
        encoded = json.dumps(
            value,
            separators=(",", ":"),
            default=str,
        ).encode("utf-8")
        client.setex(
            key,
            max(1, ttl_seconds),
            zlib.compress(encoded, level=6),
        )
        return True
    except Exception as exc:
        LOGGER.warning("Redis compressed write failed key=%s error=%s", key, exc)
        return False


def _reclaim_abandoned_builders(client: Redis, key: str) -> int:
    """Delete builder keys left behind by a killed publisher.

    Every live publication now carries a TTL from its first write, so a
    builder with no expiry can only be the residue of a process that died
    mid-write. Those are pure waste holding a full catalog each, and enough
    of them exhaust the instance -- at which point every subsequent write
    fails and the catalog silently stops publishing while reads keep serving
    the previous copy.
    """

    reclaimed = 0
    try:
        for candidate in client.scan_iter(
            match=f"{key}:building:*", count=100
        ):
            if client.ttl(candidate) == -1:
                client.delete(candidate)
                reclaimed += 1
    except Exception as exc:
        LOGGER.warning(
            "Redis builder reclaim failed key=%s error=%s", key, exc
        )
        return reclaimed
    if reclaimed:
        LOGGER.warning(
            "Reclaimed %s abandoned Redis builder key(s) for %s",
            reclaimed,
            key,
        )
    return reclaimed


def set_json_streaming_list(
    key: str,
    values: Iterable[Any],
    *,
    ttl_seconds: int,
    encode_item: Callable[[Any], Any] | None = None,
    chunk_chars: int = 512 * 1024,
) -> bool:
    """Atomically publish a large JSON list without one giant JSON copy.

    Building the entire serialized catalog beside thousands of Pydantic
    models exceeded the background worker's memory limit. A temporary Redis
    key receives bounded chunks and is renamed only after the closing bracket,
    so readers continue seeing the previous complete catalog during a rebuild.
    """
    client = _streaming_client()
    if client is None:
        _LAST_WRITE_ERROR[key] = "REDIS_URL is not configured"
        return False
    temporary_key = f"{key}:building:{uuid.uuid4().hex}"
    transform = encode_item or (lambda item: item)
    try:
        _reclaim_abandoned_builders(client, key)
        # The expiry has to be attached at creation, not after the final
        # append. A publisher killed mid-write -- a deploy restart, an
        # out-of-memory kill -- otherwise leaves a multi-megabyte builder key
        # with no TTL at all, and under maxmemory-policy noeviction nothing
        # ever reclaims it. APPEND preserves an existing TTL and RENAME
        # carries it to the destination, so the success path is unchanged.
        client.set(temporary_key, "[", ex=max(1, ttl_seconds))
        buffer: list[str] = []
        buffer_size = 0
        first = True
        for value in values:
            encoded = json.dumps(
                transform(value),
                separators=(",", ":"),
                default=str,
            )
            fragment = encoded if first else f",{encoded}"
            first = False
            buffer.append(fragment)
            buffer_size += len(fragment)
            if buffer_size >= chunk_chars:
                client.append(temporary_key, "".join(buffer))
                buffer.clear()
                buffer_size = 0
        if buffer:
            client.append(temporary_key, "".join(buffer))
        client.append(temporary_key, "]")
        client.expire(temporary_key, max(1, ttl_seconds))
        client.rename(temporary_key, key)
        _LAST_WRITE_ERROR.pop(key, None)
        return True
    except Exception as exc:
        _LAST_WRITE_ERROR[key] = f"{type(exc).__name__}: {exc}"
        LOGGER.warning("Redis streaming write failed key=%s error=%s", key, exc)
        try:
            client.delete(temporary_key)
        except Exception:
            pass
        return False


def set_compressed_json_streaming_list(
    key: str,
    values: Iterable[Any],
    *,
    ttl_seconds: int,
    encode_item: Callable[[Any], Any] | None = None,
    chunk_chars: int = 512 * 1024,
) -> bool:
    """Publish a large JSON list as a single compressed payload.

    The plain catalog occupied roughly 112 MiB in Redis, and the atomic
    rename necessarily holds the previous copy beside its replacement, so one
    publication needed about 224 MiB of a 256 MiB instance -- twelve percent
    headroom, and an OutOfMemoryError the moment anything grew. Compressing
    while walking the list keeps the worker's own memory bounded, which is
    the reason this path streams at all, and cuts what Redis must hold by
    several fold. Strings grown by APPEND also over-allocate, so the smaller
    payload compounds twice over.
    """

    client = _binary_streaming_client()
    if client is None:
        _LAST_WRITE_ERROR[key] = "REDIS_URL is not configured"
        return False
    temporary_key = f"{key}:building:{uuid.uuid4().hex}"
    transform = encode_item or (lambda item: item)
    compressor = zlib.compressobj(6)
    try:
        _reclaim_abandoned_builders(client, key)
        client.set(
            temporary_key,
            compressor.compress(b"["),
            ex=max(1, ttl_seconds),
        )
        buffer: list[str] = []
        buffer_size = 0
        first = True
        for value in values:
            encoded = json.dumps(
                transform(value),
                separators=(",", ":"),
                default=str,
            )
            fragment = encoded if first else f",{encoded}"
            first = False
            buffer.append(fragment)
            buffer_size += len(fragment)
            if buffer_size >= chunk_chars:
                chunk = compressor.compress(
                    "".join(buffer).encode("utf-8")
                )
                if chunk:
                    client.append(temporary_key, chunk)
                buffer.clear()
                buffer_size = 0
        tail = compressor.compress(
            ("".join(buffer) + "]").encode("utf-8")
        ) + compressor.flush()
        if tail:
            client.append(temporary_key, tail)
        client.expire(temporary_key, max(1, ttl_seconds))
        client.rename(temporary_key, key)
        _LAST_WRITE_ERROR.pop(key, None)
        return True
    except Exception as exc:
        _LAST_WRITE_ERROR[key] = f"{type(exc).__name__}: {exc}"
        LOGGER.warning(
            "Redis compressed streaming write failed key=%s error=%s",
            key,
            exc,
        )
        try:
            client.delete(temporary_key)
        except Exception:
            pass
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
