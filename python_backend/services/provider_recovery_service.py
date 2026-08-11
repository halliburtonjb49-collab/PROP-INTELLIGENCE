"""Owner-safe provider recovery orchestration with durable deduplication."""

from __future__ import annotations

from datetime import datetime, timezone
import os
import time
from typing import Mapping

from services.distributed_cache_service import get_json, set_json
from services.job_queue_service import enqueue, health as queue_health
from services.provider_availability_monitor_service import provider_availability_snapshot

_SYNC_STATE_KEY = "sync:global:state:v2"
_ACTION_KEY = "operations:provider-recovery:v1"
_ACTION_TTL_SECONDS = 86_400
_RECOVERY_BUCKET_SECONDS = 900
_ACTIVE_JOB_STATUSES = {"queued", "started", "deferred", "scheduled"}


def _utc(value: datetime | None = None) -> datetime:
    current = value or datetime.now(timezone.utc)
    return current.astimezone(timezone.utc) if current.tzinfo else current.replace(tzinfo=timezone.utc)


def _parse_time(value: object) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed.astimezone(timezone.utc) if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _status(value: object) -> str:
    text = str(value or "").strip().lower()
    return text.rsplit(".", 1)[-1]


def _sync_active(sync: Mapping[str, object]) -> bool:
    return any(
        _status(sync.get(key)) == "running"
        for key in ("status", "coverageStatus", "sportsGameOddsStatus", "postProcessingStatus")
    )


def _sport_actions(availability: Mapping[str, object]) -> list[dict[str, object]]:
    actions: list[dict[str, object]] = []
    for raw in availability.get("sports", []):
        if not isinstance(raw, Mapping):
            continue
        sport = str(raw.get("sport") or "UNKNOWN").upper()
        status = str(raw.get("status") or "UNAVAILABLE").upper()
        authorization = str(raw.get("authorizationStatus") or "UNKNOWN").upper()
        stale = bool(raw.get("stale"))
        needs_recovery = stale or status in {"PARTIAL", "UNAVAILABLE"}
        configured = authorization == "AUTHORIZED"
        if not configured:
            reason = (
                "Provider plan does not include this sport."
                if authorization == "NOT_ENTITLED"
                else "Provider credentials or authorization require configuration."
            )
        elif not needs_recovery:
            reason = "Latest availability check is healthy."
        else:
            reason = str(
                next(iter(raw.get("missingData") or []), "Availability data needs recovery.")
            )
        actions.append({
            "sport": sport,
            "status": status,
            "authorizationStatus": authorization,
            "stale": stale,
            "needsRecovery": needs_recovery,
            "canRecover": configured and needs_recovery,
            "reason": reason,
        })
    return actions


def provider_recovery_snapshot(*, now: datetime | None = None) -> dict[str, object]:
    current = _utc(now)
    availability = provider_availability_snapshot(now=current)
    sync = get_json(_SYNC_STATE_KEY)
    sync = dict(sync) if isinstance(sync, Mapping) else {}
    queue = queue_health()
    latest = get_json(_ACTION_KEY)
    latest = dict(latest) if isinstance(latest, Mapping) else {}
    actions = _sport_actions(availability)
    actionable = [row["sport"] for row in actions if row["canRecover"]]
    active = _sync_active(sync)
    requested_at = _parse_time(latest.get("requestedAt"))
    finished_at = _parse_time(sync.get("finishedAt"))
    job_status = _status((latest.get("job") or {}).get("status") if isinstance(latest.get("job"), Mapping) else None)

    state = "IDLE"
    message = "No provider recovery is currently required."
    if active:
        state = "RUNNING"
        message = "Provider recovery is running. Live progress is shown below."
    elif requested_at and finished_at and finished_at >= requested_at:
        failed = _status(sync.get("status")) == "failed" or any(
            _status(sync.get(key)) == "failed"
            for key in ("coverageStatus", "sportsGameOddsStatus", "postProcessingStatus")
        )
        if failed:
            state = "FAILED"
            message = "The latest recovery finished with a provider or post-processing failure."
        elif actionable:
            state = "RECOMMENDED"
            message = (
                "The latest recovery completed, but authorized provider data is still incomplete."
            )
        else:
            state = "SUCCEEDED"
            message = "The latest recovery completed successfully."
    elif job_status in _ACTIVE_JOB_STATUSES:
        state = "QUEUED"
        message = "Provider recovery is queued on the background worker."
    elif actionable:
        state = "RECOMMENDED"
        message = "One safe global recovery can refresh the affected authorized sports."

    queue_ready = bool(queue.get("available")) and int(queue.get("workers") or 0) > 0
    return {
        "generatedAt": current.isoformat(),
        "state": state,
        "message": message,
        "recoveryRecommended": bool(actionable),
        "canStartRecovery": bool(actionable) and queue_ready and not active and state != "QUEUED",
        "actionableSports": actionable,
        "sports": actions,
        "latestRequest": latest or None,
        "queue": {
            "available": bool(queue.get("available")),
            "workers": int(queue.get("workers") or 0),
            "queued": int(queue.get("queued") or 0),
            "started": int(queue.get("started") or 0),
            "retryPolicy": queue.get("retryPolicy"),
        },
        "sync": {
            "status": sync.get("status") or "idle",
            "startedAt": sync.get("startedAt"),
            "finishedAt": sync.get("finishedAt"),
            "coverageStatus": sync.get("coverageStatus") or "idle",
            "coverageProgress": sync.get("coverageProgress"),
            "sportsGameOddsStatus": sync.get("sportsGameOddsStatus") or "idle",
            "postProcessingStatus": sync.get("postProcessingStatus") or "idle",
            "postProcessingStep": sync.get("postProcessingStep"),
            "error": sync.get("error") or sync.get("coverageError") or sync.get("postProcessingError"),
        },
    }


def request_provider_recovery(
    target_sport: str = "ALL", *, now: datetime | None = None,
) -> dict[str, object]:
    current = _utc(now)
    target = (target_sport or "ALL").strip().upper()
    before = provider_recovery_snapshot(now=current)
    sports = {str(row["sport"]): row for row in before["sports"]}
    if target != "ALL" and target not in sports:
        raise ValueError(f"Unsupported recovery sport: {target}")
    selected = [row for sport, row in sports.items() if target == "ALL" or sport == target]
    recoverable = [row for row in selected if row["canRecover"]]
    if not recoverable:
        reason = selected[0]["reason"] if selected else "No provider recovery is required."
        return {**before, "request": {"accepted": False, "status": "BLOCKED", "reason": reason}}
    if before["state"] in {"RUNNING", "QUEUED"}:
        return {
            **before,
            "request": {
                "accepted": True,
                "status": before["state"],
                "deduplicated": True,
                "reason": "An existing provider recovery is already active.",
            },
        }
    queue = before["queue"]
    if not queue["available"] or int(queue["workers"] or 0) < 1:
        return {
            **before,
            "request": {
                "accepted": False,
                "status": "BLOCKED",
                "reason": "The background worker is unavailable; no sync was started.",
            },
        }

    version = os.getenv("RENDER_GIT_COMMIT", os.getenv("APP_VERSION", "development"))
    bucket = int(time.time() // _RECOVERY_BUCKET_SECONDS)
    job_id = f"prop-freshness:{version[:12]}:{bucket}"
    job = enqueue("jobs.run_prop_sync", job_id=job_id)
    if job is None:
        return {
            **before,
            "request": {
                "accepted": False,
                "status": "FAILED",
                "reason": "The recovery job could not be queued.",
            },
        }
    existing_status = _status(job.get("status"))
    if job.get("deduplicated") and existing_status not in _ACTIVE_JOB_STATUSES:
        return {
            **before,
            "request": {
                "accepted": False,
                "status": "COOLDOWN",
                "deduplicated": True,
                "jobId": job.get("id"),
                "reason": (
                    "A recovery already ran in this 15-minute safety window. "
                    "Automatic monitoring will retry in the next window if data remains stale."
                ),
            },
        }
    action = {
        "requestedAt": current.isoformat(),
        "targetSport": target,
        "affectedSports": [str(row["sport"]) for row in recoverable],
        "job": job,
    }
    set_json(_ACTION_KEY, action, ttl_seconds=_ACTION_TTL_SECONDS)
    after = provider_recovery_snapshot(now=current)
    return {
        **after,
        "request": {
            "accepted": True,
            "status": "QUEUED",
            "deduplicated": bool(job.get("deduplicated")),
            "jobId": job.get("id"),
            "reason": "Provider recovery queued with automatic retries.",
        },
    }