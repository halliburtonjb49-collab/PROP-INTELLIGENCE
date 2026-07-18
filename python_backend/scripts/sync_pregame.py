"""Refresh live lines, capture pregame predictions, and grade resolved results."""

import json
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.pipeline_run_service import finish_pipeline_run, start_pipeline_run
from services.prediction_automation_service import grade_completed_predictions
from services.sync_service import run_global_sync_pipeline


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    identifier, started = start_pipeline_run("pregame-sync")
    metrics: dict[str, object] = {}
    errors: list[dict[str, object]] = []
    try:
        results = run_global_sync_pipeline()
        metrics["sync"] = results
        errors.extend(
            {"stage": str(row.get("sport", "sync")), "error": row["error"]}
            for row in results if isinstance(row, dict) and row.get("error")
        )
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
