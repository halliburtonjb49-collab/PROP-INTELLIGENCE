"""Bounded, process-local API delivery measurements for owner diagnostics."""

from __future__ import annotations

from collections import deque
from threading import Lock
from typing import MutableMapping


PROP_METRICS_LOCK = Lock()
PROP_METRICS: dict[str, object] = {
    "requests": 0,
    "errors": 0,
    "emptyResponses": 0,
    "lastDurationMs": 0,
    "lastPayloadBytes": 0,
    "lastServedAt": None,
    "lastTotalCount": 0,
    "lastDataUpdatedAt": None,
    "lastRequestSucceeded": None,
    "cacheHits": 0,
}
_LATENCY_SAMPLES: deque[int] = deque(maxlen=250)
_PAYLOAD_SAMPLES: deque[int] = deque(maxlen=250)


def record_sample(duration_ms: int, payload_bytes: int) -> None:
    """Record only measurements already computed by the protected endpoint."""

    with PROP_METRICS_LOCK:
        _LATENCY_SAMPLES.append(max(0, int(duration_ms)))
        _PAYLOAD_SAMPLES.append(max(0, int(payload_bytes)))


def _percentile(values: list[int], percentile: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    index = round((len(ordered) - 1) * percentile)
    return ordered[max(0, min(index, len(ordered) - 1))]


def delivery_metrics_snapshot(
    metrics: MutableMapping[str, object] | None = None,
) -> dict[str, object]:
    """Return bounded measurements without account, query, or credential data."""

    with PROP_METRICS_LOCK:
        source = dict(metrics or PROP_METRICS)
        latencies = list(_LATENCY_SAMPLES)
        payloads = list(_PAYLOAD_SAMPLES)
    requests = max(0, int(source.get("requests") or 0))
    hits = max(0, int(source.get("cacheHits") or 0))
    return {
        "scope": "this-api-instance",
        "sampleCount": len(latencies),
        "requestCount": requests,
        "errorCount": max(0, int(source.get("errors") or 0)),
        "cacheHitRatio": round(hits / requests, 4) if requests else None,
        "latencyMs": {
            "last": source.get("lastDurationMs"),
            "p50": _percentile(latencies, 0.50),
            "p95": _percentile(latencies, 0.95),
        },
        "responseBytes": {
            "last": source.get("lastPayloadBytes"),
            "p50": _percentile(payloads, 0.50),
            "p95": _percentile(payloads, 0.95),
        },
        "lastServedAt": source.get("lastServedAt"),
    }
