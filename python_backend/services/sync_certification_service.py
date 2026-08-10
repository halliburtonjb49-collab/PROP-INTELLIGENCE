"""Secret-safe certification of the live synchronization system."""

from __future__ import annotations

from datetime import datetime, timezone


def _check(
    key: str,
    label: str,
    status: str,
    detail: str,
) -> dict[str, str]:
    return {"key": key, "label": label, "status": status, "detail": detail}


def sync_certification(
    *,
    feed: dict[str, object],
    queue: dict[str, object],
    keys: dict[str, object],
    coverage: dict[str, object],
    now_utc: datetime | None = None,
) -> dict[str, object]:
    """Return PASSED, WARNING, FAILED, or PENDING with actionable reasons."""

    checks: list[dict[str, str]] = []
    feed_ok = bool(feed.get("healthy")) or (
        feed.get("latestEmpty") is False and feed.get("stale") is False
    )
    checks.append(_check(
        "feed", "Live prop feed", "PASSED" if feed_ok else "FAILED",
        "The catalog is populated and fresh." if feed_ok
        else "The live catalog is empty, stale, or could not be verified.",
    ))

    queue_available = bool(queue.get("available"))
    workers = int(queue.get("workers") or 0)
    failed_jobs = int(queue.get("failed") or 0)
    queue_status = (
        "FAILED" if not queue_available or workers < 1
        else "WARNING" if failed_jobs > 0
        else "PASSED"
    )
    checks.append(_check(
        "queue", "Sync worker queue", queue_status,
        f"{workers} worker(s), {failed_jobs} failed job(s), "
        f"{int(queue.get('queued') or 0)} queued.",
    ))

    configured_keys = int(keys.get("configuredKeyCount") or 0)
    usable_keys = int(keys.get("usableKeyCount") or 0)
    key_status = (
        "FAILED" if usable_keys < 1
        else "WARNING" if usable_keys < configured_keys
        else "PASSED"
    )
    checks.append(_check(
        "provider_keys", "Odds provider keys", key_status,
        f"{usable_keys} of {configured_keys} configured key(s) are usable.",
    ))

    configured_sports = list(coverage.get("configured") or [])
    never_fetched = list(coverage.get("neverFetched") or [])
    results = coverage.get("results") or {}
    result_rows = results.values() if isinstance(results, dict) else []
    fetch_errors = [
        str(row.get("lastError") or "")
        for row in result_rows
        if isinstance(row, dict)
        and str(row.get("lastError") or "")
        and not str(row.get("lastError") or "").startswith("skipped:")
    ]
    failed_events = sum(
        int(row.get("failedEvents") or 0)
        for row in result_rows
        if isinstance(row, dict)
    )
    starved = list(coverage.get("starvedByQuota") or [])
    fetched_but_empty = list(coverage.get("fetchedButEmpty") or [])
    coverage_status = (
        "WARNING"
        if fetch_errors or failed_events or starved or fetched_but_empty
        else "PENDING" if never_fetched
        else "PASSED"
    )
    checks.append(_check(
        "coverage", "Broad sport coverage", coverage_status,
        f"{len(configured_sports) - len(never_fetched)} of "
        f"{len(configured_sports)} configured sport(s) fetched; "
        f"{len(fetch_errors)} sport error(s), {failed_events} failed event "
        f"request(s), {len(starved)} quota-starved, "
        f"{len(fetched_but_empty)} fetched but empty.",
    ))

    statuses = {check["status"] for check in checks}
    status = (
        "FAILED" if "FAILED" in statuses
        else "WARNING" if "WARNING" in statuses
        else "PENDING" if "PENDING" in statuses
        else "PASSED"
    )
    retry_policy = queue.get("retryPolicy")
    return {
        "status": status,
        "generatedAtUtc": (now_utc or datetime.now(timezone.utc)).isoformat(),
        "checks": checks,
        "automaticRetries": bool(
            isinstance(retry_policy, dict)
            and int(retry_policy.get("maxAttempts") or 0) > 1
        ),
        "retryPolicy": retry_policy,
        "needsAttention": status in {"FAILED", "WARNING"},
        "pendingSports": never_fetched,
    }
