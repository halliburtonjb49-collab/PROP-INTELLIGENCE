"""Daily MLB strikeout calibration and drift monitor."""

from __future__ import annotations

import json
import os
import sys

from services.strikeout_quality_service import (
    get_strikeout_release_controls,
    strikeout_backtest_monitoring,
    strikeout_calibration_report,
)


def main() -> int:
    controls_payload = get_strikeout_release_controls()
    controls = controls_payload.get("controls") if isinstance(controls_payload, dict) else None
    control_values = controls if isinstance(controls, dict) else None

    calibration = strikeout_calibration_report(control_values)
    backtest = strikeout_backtest_monitoring(control_values)

    report = {
        "controls": controls_payload,
        "calibration": calibration,
        "backtest": backtest,
    }
    print(json.dumps(report, indent=2, sort_keys=True))

    fail_on_alert = os.getenv("STRIKEOUT_MONITOR_FAIL_ON_ALERT", "true").strip().lower() != "false"
    if not fail_on_alert:
        return 0
    alerts = backtest.get("alerts") if isinstance(backtest, dict) else []
    if isinstance(alerts, list) and alerts:
        print("Strikeout drift alerts detected.", file=sys.stderr)
        return 1
    if calibration.get("available") and not calibration.get("healthy", True):
        print("Strikeout calibration is outside tolerance.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
