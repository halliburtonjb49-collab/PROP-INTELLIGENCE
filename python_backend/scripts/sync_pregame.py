"""Refresh live lines, capture pregame predictions, and grade resolved results."""

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.operations_notification_service import notify_operations_alert
from services.pipeline_run_service import finish_pipeline_run, start_pipeline_run
from services.multi_sport_grading_service import grade_all_active_slips
from services.prediction_automation_service import (
    confidence_tier_calibration,
    grade_completed_predictions,
)
from services.sync_service import run_global_sync_pipeline


_TRANSIENT_HTTP_STATUSES = {429, 502, 503, 504}

# Each check already retries internally, so this many consecutive failures is
# a status endpoint that is genuinely gone rather than a moment of noise.
_MAX_CONSECUTIVE_STATUS_FAILURES = 10


def _request_json_with_retry(
    method: str,
    url: str,
    *,
    attempts: int = 8,
) -> dict[str, object]:
    """Return JSON while tolerating brief deploy/proxy interruptions.

    Render can return a short-lived 502 while the API instance is swapping to
    a new release. The API owns the sync lock, so retrying the trigger is safe
    and cannot create a second concurrent full sync.
    """

    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            response = requests.request(method, url, timeout=30)
            if response.status_code not in _TRANSIENT_HTTP_STATUSES:
                response.raise_for_status()
                payload = response.json()
                if not isinstance(payload, dict):
                    raise RuntimeError(f"Unexpected response from {url}")
                return payload
            last_error = requests.HTTPError(
                f"Transient HTTP {response.status_code} from {url}",
                response=response,
            )
        except (requests.ConnectionError, requests.Timeout) as exc:
            last_error = exc
        if attempt + 1 < attempts:
            time.sleep(min(2 ** (attempt + 1), 15))
    if last_error is not None:
        raise last_error
    raise RuntimeError(f"Request failed without a response: {url}")


def _api_base_url() -> str:
    """Resolve the API this job drives, once, for every caller."""

    api_base_url = os.getenv("API_BASE_URL", "").strip().rstrip("/")
    if not api_base_url and os.getenv("RENDER", "").lower() == "true":
        api_base_url = "https://api.propsintell.com"
    return api_base_url


def run_live_api_sync() -> dict[str, object] | None:
    api_base_url = _api_base_url()
    if not api_base_url:
        return None
    payload = _request_json_with_retry("POST", f"{api_base_url}/api/sync")
    if _full_sync_complete(payload):
        return payload

    # Expanded professional coverage and post-processing can exceed the old
    # ten-minute ceiling. Wait for the real terminal state instead of marking
    # an otherwise healthy, locked cycle as a failed cron run.
    timeout_seconds = max(
        600,
        int(os.getenv("PREGAME_SYNC_TIMEOUT_SECONDS", "2700")),
    )
    deadline = time.monotonic() + timeout_seconds
    # The API owns the sync; this loop only watches it. A proxy hiccup or a
    # deploy swapping instances makes one status read fail, and treating
    # that as a failed sync threw away a cycle that was still running fine
    # on the other side. Only a status endpoint that stays unreachable is
    # evidence of anything.
    consecutive_status_failures = 0
    while time.monotonic() < deadline:
        time.sleep(3)
        try:
            payload = _request_json_with_retry(
                "GET",
                f"{api_base_url}/api/sync/status",
                attempts=3,
            )
        except (
            requests.ConnectionError,
            requests.Timeout,
            requests.HTTPError,
        ) as exc:
            consecutive_status_failures += 1
            logging.warning(
                "Sync status temporarily unavailable failure=%s/%s error=%s",
                consecutive_status_failures,
                _MAX_CONSECUTIVE_STATUS_FAILURES,
                exc,
            )
            if consecutive_status_failures >= _MAX_CONSECUTIVE_STATUS_FAILURES:
                raise RuntimeError(
                    "Live API sync status remained unavailable after "
                    f"{consecutive_status_failures} consecutive checks"
                ) from exc
            continue
        consecutive_status_failures = 0
        status = str(payload.get("status", "")).lower()
        coverage_status = str(payload.get("coverageStatus", "")).lower()
        sports_game_odds_status = str(
            payload.get("sportsGameOddsStatus", "")
        ).lower()
        post_processing_status = str(
            payload.get("postProcessingStatus", "")
        ).lower()
        if _full_sync_complete(payload):
            return payload
        if "failed" in {
            status,
            coverage_status,
            sports_game_odds_status,
            post_processing_status,
        }:
            raise RuntimeError(str(
                payload.get("postProcessingError")
                or payload.get("sportsGameOddsError")
                or payload.get("coverageError")
                or payload.get("error")
                or "Live API sync failed"
            ))
    raise TimeoutError(
        f"Live API prop sync did not finish within {timeout_seconds} seconds"
    )


def _full_sync_complete(payload: dict[str, object]) -> bool:
    """Certify success only after every downstream sync lane finishes."""

    return (
        str(payload.get("status", "")).lower() == "complete"
        and str(payload.get("coverageStatus", "")).lower() == "complete"
        and str(payload.get("sportsGameOddsStatus", "")).lower()
        in {"complete", "partial"}
        and str(payload.get("postProcessingStatus", "")).lower() == "complete"
    )


_MAX_PUBLISHED_AGE_MINUTES = int(
    os.getenv("FEED_STALE_ALERT_MINUTES", "45")
)


def _alert_on_a_stalled_feed(api_base_url: str) -> None:
    """Raise a catalog that stopped publishing while the run looked healthy.

    This is the shape of the outage that ran for six hours unnoticed: the
    providers answered, the stages reported success, and the only symptom
    was a publication timestamp that stopped moving. Nothing watched that
    timestamp except a deploy that happened to run.
    """

    if not api_base_url:
        return
    try:
        payload = _request_json_with_retry(
            "GET", f"{api_base_url}/api/props/readiness", attempts=2
        )
    except Exception:
        logging.exception("Feed freshness check could not reach the API")
        return
    published = str(payload.get("catalogPublishedAt") or "")
    if not published:
        return
    try:
        published_at = datetime.fromisoformat(published.replace("Z", "+00:00"))
    except ValueError:
        return
    if published_at.tzinfo is None:
        published_at = published_at.replace(tzinfo=timezone.utc)
    age_minutes = (
        datetime.now(timezone.utc) - published_at
    ).total_seconds() / 60
    recovery = bool(payload.get("recovery"))
    if age_minutes <= _MAX_PUBLISHED_AGE_MINUTES and not recovery:
        return
    notify_operations_alert(
        kind="feed_stalled",
        summary=(
            f"prop catalog last published {age_minutes:.0f} minutes ago"
            + (" and the board is serving a recovery snapshot" if recovery else "")
        ),
        details={
            "catalogPublishedAt": published,
            "ageMinutes": round(age_minutes),
            "servingLayer": payload.get("source"),
            "recovery": recovery,
            "count": payload.get("count"),
        },
    )


def _alert_on_a_tier_that_stopped_paying(
    tiers: list[dict[str, object]],
) -> None:
    """Raise an actionable tier the results no longer support.

    A band claiming 57.9% delivered 54.0% and lost 9.1% flat-staked for
    months while the card called it playable. Recording that number is not
    the same as noticing it.
    """

    failing = [
        tier
        for tier in tiers
        if tier.get("actionable")
        and tier.get("profitability") == "proven_unprofitable"
    ]
    if not failing:
        return
    names = ", ".join(str(tier.get("tier")) for tier in failing)
    notify_operations_alert(
        kind="tier_unprofitable",
        summary=f"actionable tier no longer pays: {names}",
        details={"tiers": failing},
    )


def _is_daily_measurement_window() -> bool:
    """True for exactly one of the day's cron runs.

    The scan reads every graded snapshot, which is far too heavy for a job
    that runs every ten minutes and much cheaper than a second Render
    service. The ten-minute cadence makes a single ten-minute window a
    reliable once-a-day trigger without persisting any state to remember
    whether today's measurement already ran.
    """

    now = datetime.now(timezone.utc)
    return now.hour == int(
        os.getenv("TIER_CALIBRATION_UTC_HOUR", "10")
    ) and now.minute < 10


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    identifier, started = start_pipeline_run("pregame-sync")
    metrics: dict[str, object] = {}
    errors: list[dict[str, object]] = []
    try:
        live_result = run_live_api_sync()
        results = live_result if live_result is not None else run_global_sync_pipeline()
        metrics["sync"] = results
        if isinstance(results, list):
            errors.extend(
                {"stage": str(row.get("sport", "sync")), "error": row["error"]}
                for row in results if isinstance(row, dict) and row.get("error")
            )
        elif isinstance(results, dict) and results.get("error"):
            errors.append({"stage": "live-api-sync", "error": results["error"]})
    except Exception as exc:
        logging.exception("Pregame odds sync failed")
        errors.append({"stage": "odds-sync", "error": str(exc)})
    try:
        metrics["grading"] = grade_completed_predictions()
    except Exception as exc:
        logging.exception("Pregame grading failed")
        errors.append({"stage": "prediction-grading", "error": str(exc)})
    try:
        slip_grading = grade_all_active_slips()
        metrics["slipGrading"] = slip_grading
        if slip_grading.get("failures"):
            errors.append(
                {
                    "stage": "slip-grading",
                    "error": f"{len(slip_grading['failures'])} user grading pass(es) failed",
                }
            )
    except Exception as exc:
        logging.exception("Active slip grading failed")
        errors.append({"stage": "slip-grading", "error": str(exc)})
    _alert_on_a_stalled_feed(_api_base_url())
    if _is_daily_measurement_window():
        # Whether a displayed tier still earns its number is the one claim
        # the product makes to every user, and it went unchecked for months
        # until somebody ran the query by hand. Recording it into the run
        # history puts the answer where the other pipeline numbers already
        # live, without standing up a service to ask it.
        try:
            tiers = confidence_tier_calibration()
            metrics["confidenceTiers"] = tiers
            _alert_on_a_tier_that_stopped_paying(tiers)
        except Exception as exc:
            logging.exception("Confidence tier calibration failed")
            errors.append(
                {"stage": "tier-calibration", "error": str(exc)}
            )
    result = finish_pipeline_run(identifier, started, metrics=metrics, errors=errors)
    print(json.dumps(result, indent=2, default=str))
    # A partial run contains at least one failed stage. Returning zero made
    # Render label those executions successful and hid missing coverage.
    return 0 if result["status"] == "SUCCEEDED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
