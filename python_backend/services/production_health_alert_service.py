"""Rate-limited alerts for silent prop and learning degradation."""

from __future__ import annotations

import os
import threading
from datetime import datetime, timezone

from services.model_learning_readiness_service import model_learning_readiness
from services.operations_notification_service import notify_operations_alert

_lock = threading.Lock()
_last_alert: dict[str, datetime] = {}


def _allowed(key: str, now: datetime) -> bool:
    cooldown = max(300, int(os.getenv("OPERATIONS_ALERT_COOLDOWN_SECONDS", "1800")))
    with _lock:
        previous = _last_alert.get(key)
        if previous and (now - previous).total_seconds() < cooldown:
            return False
        _last_alert[key] = now
        return True


def alert_prop_health(props: list[object], now: datetime | None = None) -> list[str]:
    current = now or datetime.now(timezone.utc)
    issues: list[str] = []
    if not props:
        issues.append("inventory_zero")
    else:
        stamps = [str(getattr(row, "lastUpdatedUtc", "") or "") for row in props]
        parsed: list[datetime] = []
        for stamp in stamps:
            try:
                parsed.append(datetime.fromisoformat(stamp.replace("Z", "+00:00")))
            except (TypeError, ValueError):
                continue
        stale_minutes = max(15, int(os.getenv("PROP_FEED_STALE_MINUTES", "180")))
        if not parsed or (current - max(parsed)).total_seconds() > stale_minutes * 60:
            issues.append("feed_stale")
    for issue in issues:
        if _allowed(issue, current):
            notify_operations_alert(
                kind=issue,
                summary=(
                    "Prop inventory dropped to zero"
                    if issue == "inventory_zero"
                    else "Prop feed exceeded its freshness limit"
                ),
                details={"inventory": len(props)},
            )
    return issues


def alert_model_learning(now: datetime | None = None) -> dict[str, object]:
    current = now or datetime.now(timezone.utc)
    readiness = model_learning_readiness()
    if readiness.get("status") != "ready" and _allowed("model_learning", current):
        notify_operations_alert(
            kind="model_learning",
            summary="Model learning is not fully ready",
            details={"status": readiness.get("status"), "checks": readiness.get("checks")},
        )
    return readiness
