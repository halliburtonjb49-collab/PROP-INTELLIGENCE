"""Privacy-safe publication-to-client applied timing for owner diagnostics."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Mapping

from services.distributed_cache_service import get_json, set_json

_KEY = "operations:prop-client-delivery:v1"
_TTL_SECONDS = 172_800


def _instant(value: object) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed.astimezone(timezone.utc) if parsed.tzinfo else parsed.replace(
            tzinfo=timezone.utc
        )
    except (TypeError, ValueError):
        return None


def record_client_apply(
    *, revision: str, published_at: str, applied_at: str
) -> dict[str, object]:
    published = _instant(published_at)
    applied = _instant(applied_at)
    clean_revision = revision.strip()[:160]
    if not clean_revision or published is None or applied is None:
        raise ValueError("A valid revision and timestamps are required")
    latency_ms = int((applied - published).total_seconds() * 1000)
    if latency_ms < 0 or latency_ms > 3_600_000:
        raise ValueError("Client delivery timing is outside the accepted range")
    previous = get_json(_KEY)
    previous = dict(previous) if isinstance(previous, Mapping) else {}
    count = min(1_000_000, int(previous.get("sampleCount") or 0) + 1)
    average = previous.get("averageMs")
    average_ms = latency_ms if average is None else round(
        ((float(average) * (count - 1)) + latency_ms) / count, 1
    )
    snapshot: dict[str, object] = {
        "scope": "authenticated-clients",
        "sampleCount": count,
        "lastMs": latency_ms,
        "averageMs": average_ms,
        "lastRevision": clean_revision,
        "lastAppliedAt": applied.isoformat(),
    }
    set_json(_KEY, snapshot, ttl_seconds=_TTL_SECONDS)
    return snapshot


def client_delivery_snapshot() -> dict[str, object]:
    snapshot = get_json(_KEY)
    return dict(snapshot) if isinstance(snapshot, Mapping) else {
        "scope": "authenticated-clients",
        "sampleCount": 0,
    }
