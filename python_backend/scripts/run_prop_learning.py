"""Run the complete closed-loop prop snapshot and result-learning pipeline."""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Callable, TypeVar

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.pipeline_run_service import finish_pipeline_run, start_pipeline_run
from services.prop_learning_service import (
    grade_learning_results,
    snapshot_all_props_for_learning,
)


T = TypeVar("T")
_TRANSIENT_MARKERS = (
    "connection has been closed",
    "connection is closed",
    "connection reset",
    "connection refused",
    "consuming input failed",
    "server closed the connection",
    "ssl connection",
    "timeout",
)


def _retry(label: str, operation: Callable[[], T]) -> T:
    attempts = max(1, min(int(os.getenv("PROP_LEARNING_DB_ATTEMPTS", "4")), 6))
    base_delay = max(1, int(os.getenv("PROP_LEARNING_RETRY_SECONDS", "5")))
    for attempt in range(1, attempts + 1):
        try:
            return operation()
        except Exception as exc:
            transient = any(marker in str(exc).lower() for marker in _TRANSIENT_MARKERS)
            if not transient or attempt == attempts:
                raise
            delay = min(base_delay * (2 ** (attempt - 1)), 60)
            logging.warning(
                "%s failed on attempt %s/%s; retrying in %ss: %s",
                label,
                attempt,
                attempts,
                delay,
                exc,
            )
            time.sleep(delay)
    raise RuntimeError(f"{label} exhausted retries")


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    identifier, started = _retry(
        "learning pipeline telemetry start",
        lambda: start_pipeline_run("prop-learning"),
    )
    metrics: dict[str, object] = {}
    errors: list[dict[str, object]] = []

    try:
        metrics["snapshot"] = _retry(
            "prop snapshot",
            snapshot_all_props_for_learning,
        )
    except Exception as exc:
        logging.exception("Prop-learning snapshot failed")
        errors.append({"stage": "snapshot", "error": str(exc)})

    try:
        batch_size = max(
            100,
            min(int(os.getenv("PROP_LEARNING_GRADE_BATCH_SIZE", "2000")), 5000),
        )
        metrics["grading"] = _retry(
            "result grading",
            lambda: grade_learning_results(batch_size=batch_size),
        )
    except Exception as exc:
        logging.exception("Prop-learning result grading failed")
        errors.append({"stage": "grading", "error": str(exc)})

    result = _retry(
        "learning pipeline telemetry finish",
        lambda: finish_pipeline_run(
            identifier,
            started,
            metrics=metrics,
            errors=errors,
        ),
    )
    print(json.dumps(result, indent=2, default=str))
    return 0 if result["status"] == "SUCCEEDED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
