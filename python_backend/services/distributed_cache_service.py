"""Optional shared Redis cache with a no-outage local fallback."""

from __future__ import annotations

import json
import hashlib
import logging
import os
import time
import uuid
import zlib
from datetime import datetime, timezone
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
                transform(value), separators=(",", ":"), default=str
            )
            fragment = encoded if first else f",{encoded}"
            first = False
            buffer.append(fragment)
            buffer_size += len(fragment)
            if buffer_size >= chunk_chars:
                chunk = compressor.compress("".join(buffer).encode("utf-8"))
                if chunk:
                    client.append(temporary_key, chunk)
                buffer.clear()
                buffer_size = 0
        tail = compressor.compress(("".join(buffer) + "]").encode("utf-8"))
        tail += compressor.flush()
        if tail:
            client.append(temporary_key, tail)
        client.expire(temporary_key, max(1, ttl_seconds))
        client.rename(temporary_key, key)
        _LAST_WRITE_ERROR.pop(key, None)
        return True
    except Exception as exc:
        _LAST_WRITE_ERROR[key] = f"{type(exc).__name__}: {exc}"
        LOGGER.warning(
            "Redis compressed streaming write failed key=%s error=%s", key, exc
        )
        try:
            client.delete(temporary_key)
        except Exception:
            pass
        return False


_PUBLISH_CATALOG_LUA = """
local accepted = tonumber(redis.call('GET', KEYS[4]) or '-1')
local incoming = tonumber(ARGV[1])
if accepted >= incoming then
  redis.call('DEL', KEYS[1])
  return 0
end
redis.call('RENAME', KEYS[1], KEYS[2])
redis.call('SETEX', KEYS[3], ARGV[2], ARGV[3])
redis.call('SETEX', KEYS[4], ARGV[2], ARGV[1])
return 1
"""


def publish_compressed_catalog_with_manifest(
    key: str,
    values: Iterable[Any],
    *,
    manifest_key: str,
    sequence_key: str,
    accepted_sequence_key: str,
    ttl_seconds: int,
    source_updated_at: str | None,
    encode_item: Callable[[Any], Any] | None = None,
    chunk_chars: int = 512 * 1024,
) -> dict[str, Any] | None:
    """Atomically promote a complete snapshot and its small revision manifest.

    Sequence allocation happens before serialization. The Lua comparison at
    promotion time prevents a slower, older publisher from replacing a newer
    accepted snapshot. Readers therefore never observe a manifest referring
    to a snapshot that was not promoted in the same Redis operation.
    """

    started_at = time.perf_counter()
    client = _binary_streaming_client()
    if client is None:
        _LAST_WRITE_ERROR[key] = "REDIS_URL is not configured"
        return None
    temporary_key = f"{key}:building:{uuid.uuid4().hex}"
    transform = encode_item or (lambda item: item)
    compressor = zlib.compressobj(6)
    digest = hashlib.sha256()
    count = 0
    try:
        sequence = int(client.incr(sequence_key))
        epoch = client.get(f"{sequence_key}:epoch")
        if isinstance(epoch, bytes):
            epoch = epoch.decode("utf-8")
        if not epoch:
            proposed_epoch = uuid.uuid4().hex
            client.setnx(f"{sequence_key}:epoch", proposed_epoch)
            epoch = client.get(f"{sequence_key}:epoch") or proposed_epoch
            if isinstance(epoch, bytes):
                epoch = epoch.decode("utf-8")
        _reclaim_abandoned_builders(client, key)
        opening = b"["
        digest.update(opening)
        client.set(
            temporary_key,
            compressor.compress(opening),
            ex=max(1, ttl_seconds),
        )
        buffer: list[str] = []
        buffer_size = 0
        first = True
        for value in values:
            encoded = json.dumps(
                transform(value), separators=(",", ":"), default=str
            )
            fragment = encoded if first else f",{encoded}"
            first = False
            count += 1
            digest.update(fragment.encode("utf-8"))
            buffer.append(fragment)
            buffer_size += len(fragment)
            if buffer_size >= chunk_chars:
                chunk = compressor.compress("".join(buffer).encode("utf-8"))
                if chunk:
                    client.append(temporary_key, chunk)
                buffer.clear()
                buffer_size = 0
        closing = ("".join(buffer) + "]").encode("utf-8")
        digest.update(closing)
        tail = compressor.compress(closing) + compressor.flush()
        if tail:
            client.append(temporary_key, tail)
        client.expire(temporary_key, max(1, ttl_seconds))
        published_at = datetime.now(timezone.utc).isoformat()
        manifest: dict[str, Any] = {
            "schemaVersion": 1,
            "epoch": str(epoch),
            "sequence": sequence,
            "contentRevision": f"{epoch}:{sequence}",
            "contentDigest": digest.hexdigest(),
            "snapshotKey": key,
            "count": count,
            "sourceUpdatedAt": source_updated_at,
            "publishedAt": published_at,
            "publicationDurationMs": int(
                (time.perf_counter() - started_at) * 1000
            ),
        }
        accepted = int(
            client.eval(
                _PUBLISH_CATALOG_LUA,
                4,
                temporary_key,
                key,
                manifest_key,
                accepted_sequence_key,
                sequence,
                max(1, ttl_seconds),
                json.dumps(manifest, separators=(",", ":")),
            )
        )
        _LAST_WRITE_ERROR.pop(key, None)
        if accepted:
            return {**manifest, "acceptedPublication": True}
        current = client.get(manifest_key)
        if isinstance(current, bytes):
            current = current.decode("utf-8")
        if not current:
            return None
        return {**json.loads(current), "acceptedPublication": False}
    except Exception as exc:
        _LAST_WRITE_ERROR[key] = f"{type(exc).__name__}: {exc}"
        LOGGER.warning("Redis manifest catalog publication failed key=%s error=%s", key, exc)
        try:
            client.delete(temporary_key)
        except Exception:
            pass
        return None


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
        memory = client.info("memory")
        used = int(memory.get("used_memory") or 0)
        maximum = int(memory.get("maxmemory") or 0)
        return {
            "configured": True,
            "available": bool(client.ping()),
            "mode": "redis",
            "usedMemoryBytes": used,
            "maxMemoryBytes": maximum,
            "memoryUtilization": round(used / maximum, 4) if maximum else None,
        }
    except Exception as exc:
        return {
            "configured": True,
            "available": False,
            "mode": "local-fallback",
            "error": str(exc),
        }
