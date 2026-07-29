"""Process-local, secret-safe scoreboard latency telemetry."""

from __future__ import annotations

from collections import deque
from datetime import datetime, timezone
from threading import Lock

_lock = Lock()
_samples: deque[float] = deque(maxlen=120)
_errors = 0
_last_recorded_at: str | None = None
_last_succeeded: bool | None = None


def record_scoreboard_request(duration_ms: float, *, succeeded: bool) -> None:
    global _errors, _last_recorded_at, _last_succeeded
    with _lock:
        _samples.append(max(0.0, float(duration_ms)))
        if not succeeded:
            _errors += 1
        _last_recorded_at = datetime.now(timezone.utc).isoformat()
        _last_succeeded = succeeded


def scoreboard_latency_snapshot() -> dict[str, object]:
    with _lock:
        raw_samples = list(_samples)
        errors = _errors
        last_recorded_at = _last_recorded_at
        last_succeeded = _last_succeeded
    if not raw_samples:
        return {
            "status": "not_checked",
            "sampleCount": 0,
            "lastMs": None,
            "averageMs": None,
            "p95Ms": None,
            "errors": errors,
            "lastRecordedAt": last_recorded_at,
        }
    samples = sorted(raw_samples)
    p95_index = min(len(samples) - 1, int((len(samples) - 1) * 0.95))
    last_ms = raw_samples[-1]
    return {
        "status": (
            "degraded"
            if last_succeeded is False or last_ms >= 3000
            else "ok"
        ),
        "sampleCount": len(samples),
        "lastMs": round(last_ms, 1),
        "averageMs": round(sum(samples) / len(samples), 1),
        "p95Ms": round(samples[p95_index], 1),
        "errors": errors,
        "lastRecordedAt": last_recorded_at,
    }
