"""Refresh live lines, capture pregame predictions, and grade resolved results."""

import json
import logging
import os
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.pipeline_run_service import finish_pipeline_run, start_pipeline_run
from services.prediction_automation_service import grade_completed_predictions
from services.sync_service import run_global_sync_pipeline


def run_live_api_sync() -> dict[str, object] | None:
    api_base_url = os.getenv("API_BASE_URL", "").strip().rstrip("/")
    if not api_base_url and os.getenv("RENDER", "").lower() == "true":
        api_base_url = "https://api.propsintell.com"
    if not api_base_url:
        return None
    response = requests.post(f"{api_base_url}/api/sync", timeout=30)
    response.raise_for_status()
    payload = response.json()
    if str(payload.get("status", "")).lower() == "complete":
        return payload

    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        time.sleep(3)
        status_response = requests.get(
            f"{api_base_url}/api/sync/status",
            timeout=30,
        )
        status_response.raise_for_status()
        payload = status_response.json()
        status = str(payload.get("status", "")).lower()
        if status == "complete":
            return payload
        if status == "failed":
            raise RuntimeError(str(payload.get("error") or "Live API sync failed"))
    raise TimeoutError("Live API prop sync did not finish within four minutes")


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
    result = finish_pipeline_run(identifier, started, metrics=metrics, errors=errors)
    print(json.dumps(result, indent=2, default=str))
    return 0 if result["status"] in {"SUCCEEDED", "PARTIAL"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
