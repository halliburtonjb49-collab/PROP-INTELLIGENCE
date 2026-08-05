"""Weekly publishable trust report for MLB strikeout strategy."""

from __future__ import annotations

import json
import os
import sys

from services.strikeout_quality_service import (
    get_strikeout_release_controls,
    strikeout_weekly_trust_report,
)


def main() -> int:
    controls_payload = get_strikeout_release_controls()
    controls = controls_payload.get("controls") if isinstance(controls_payload, dict) else None
    control_values = controls if isinstance(controls, dict) else None

    trust_report = strikeout_weekly_trust_report(control_values)
    payload = {
        "controls": controls_payload,
        "trustWeekly": trust_report,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))

    fail_on_critical = os.getenv("STRIKEOUT_TRUST_FAIL_ON_CRITICAL", "false").strip().lower() == "true"
    if not fail_on_critical:
        return 0

    alerts = trust_report.get("alerts") if isinstance(trust_report, dict) else []
    has_critical = isinstance(alerts, list) and any(
        str(alert.get("severity") or "").lower() == "critical"
        for alert in alerts
        if isinstance(alert, dict)
    )
    if has_critical:
        print("Critical alert found in weekly trust report.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
