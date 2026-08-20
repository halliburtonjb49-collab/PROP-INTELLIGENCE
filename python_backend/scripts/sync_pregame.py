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

from services.pipeline_run_service import finish_pipeline_run, start_pipeline_run
from services.prediction_automation_service import (
    confidence_tier_calibration,
    grade_completed_predictions,
)
from services.sync_service import run_global_sync_pipeline


_TRANSIENT_HTTP_STATUSES = {429, 502, 503, 504}


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


def run_live_api_sync() -> dict[str, object] | None:
    api_base_url = os.getenv("API_BASE_URL", "").strip().rstrip("/")
    if not api_base_url and os.getenv("RENDER", "").lower() == "true":
        api_base_url = "https://api.propsintell.com"
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
    while time.monotonic() < deadline:
        time.sleep(3)
        payload = _request_json_with_retry(
            "GET",
            f"{api_base_url}/api/sync/status",
        )
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
    if _is_daily_measurement_window():
        # Whether a displayed tier still earns its number is the one claim
        # the product makes to every user, and it went unchecked for months
        # until somebody ran the query by hand. Recording it into the run
        # history puts the answer where the other pipeline numbers already
        # live, without standing up a service to ask it.
        try:
            metrics["confidenceTiers"] = confidence_tier_calibration()
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
