"""Low-overhead process-memory checkpoints for long-running worker jobs."""

from __future__ import annotations

import gc
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

LOGGER = logging.getLogger(__name__)
_memory_alert_sent = False


def _linux_memory_value(label: str) -> int | None:
    try:
        for line in Path("/proc/self/status").read_text(encoding="utf-8").splitlines():
            if line.startswith(f"{label}:"):
                return int(line.split()[1]) * 1024
    except (OSError, ValueError, IndexError):
        return None
    return None


def _resource_peak_bytes() -> int | None:
    try:
        import resource

        value = int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
        return value if os.uname().sysname == "Darwin" else value * 1024
    except (AttributeError, ImportError, OSError, ValueError):
        return None


def process_memory_snapshot(stage: str) -> dict[str, object]:
    """Return actual and peak resident memory without adding a dependency."""

    rss_bytes = _linux_memory_value("VmRSS")
    peak_bytes = _linux_memory_value("VmHWM") or _resource_peak_bytes()
    return {
        "stage": str(stage),
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "rssMb": round(rss_bytes / 1_048_576, 2) if rss_bytes is not None else None,
        "peakRssMb": (
            round(peak_bytes / 1_048_576, 2)
            if peak_bytes is not None
            else None
        ),
        "gcCounts": list(gc.get_count()),
    }


def record_memory_checkpoint(stage: str) -> dict[str, object]:
    global _memory_alert_sent
    snapshot = process_memory_snapshot(stage)
    LOGGER.info(
        "memory_checkpoint stage=%s rss_mb=%s peak_rss_mb=%s gc=%s",
        snapshot["stage"],
        snapshot["rssMb"],
        snapshot["peakRssMb"],
        snapshot["gcCounts"],
    )
    limit_mb = max(1, int(os.getenv("PROCESS_MEMORY_LIMIT_MB", "2048")))
    rss_mb = snapshot.get("rssMb")
    if (
        isinstance(rss_mb, (int, float))
        and rss_mb >= limit_mb * 0.75
        and not _memory_alert_sent
    ):
        _memory_alert_sent = True
        try:
            from services.operations_notification_service import notify_operations_alert
            notify_operations_alert(
                kind="worker_memory_high",
                summary=f"Worker memory reached {rss_mb:.0f} MB",
                details={"stage": stage, "rssMb": rss_mb, "limitMb": limit_mb},
            )
        except Exception:
            LOGGER.exception("Unable to send worker memory alert")
    return snapshot
