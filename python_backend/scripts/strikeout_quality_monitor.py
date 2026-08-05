"""Daily MLB strikeout calibration and drift monitor."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
import sys

from database.postgres import database_is_configured, get_database_pool
from services.strikeout_quality_service import (
    get_strikeout_release_controls,
    strikeout_backtest_monitoring,
    strikeout_calibration_report,
    strikeout_calibration_history_report,
    strikeout_weekly_trust_report,
)


def _collect_alerts(report: dict[str, object]) -> list[dict[str, object]]:
    alerts: list[dict[str, object]] = []
    for section_key in ("backtest", "calibrationHistory", "trustWeekly"):
        section = report.get(section_key)
        if not isinstance(section, dict):
            continue
        section_alerts = section.get("alerts")
        if not isinstance(section_alerts, list):
            continue
        for alert in section_alerts:
            if isinstance(alert, dict):
                alert_copy = dict(alert)
                alert_copy.setdefault("section", section_key)
                alerts.append(alert_copy)
    return alerts


def _ensure_incident_table() -> None:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """create table if not exists model_incident_records (
                id bigserial primary key,
                incident_key text unique not null,
                title text not null,
                severity text not null,
                owner text not null,
                status text not null default 'open',
                source text not null,
                alert_type text not null,
                payload jsonb not null,
                created_at timestamptz not null default now()
            )"""
        )
        connection.commit()


def _incident_key(alert: dict[str, object]) -> str:
    normalized = json.dumps(
        {
            "type": alert.get("type"),
            "sportsbook": alert.get("sportsbook"),
            "lineBand": alert.get("lineBand") or alert.get("lineRange"),
            "handedness": alert.get("handedness"),
            "side": alert.get("side"),
            "windowDays": alert.get("windowDays"),
            "section": alert.get("section"),
            "date": datetime.now(timezone.utc).date().isoformat(),
        },
        sort_keys=True,
    )
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _open_incident_records(alerts: list[dict[str, object]]) -> int:
    if not database_is_configured():
        return 0
    critical_alerts = [
        alert
        for alert in alerts
        if str(alert.get("severity") or "").lower() == "critical"
    ]
    if not critical_alerts:
        return 0

    _ensure_incident_table()
    created = 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        for alert in critical_alerts:
            key = _incident_key(alert)
            alert_type = str(alert.get("type") or "unknown")
            owner = str(alert.get("owner") or "model-ops")
            message = str(alert.get("message") or alert_type)
            cursor.execute(
                """insert into model_incident_records
                    (incident_key, title, severity, owner, source, alert_type, payload)
                    values (%s, %s, %s, %s, %s, %s, %s::jsonb)
                    on conflict(incident_key) do nothing""",
                (
                    key,
                    f"Critical strikeout alert: {alert_type}",
                    "critical",
                    owner,
                    "strikeout_quality_monitor",
                    alert_type,
                    json.dumps({
                        "alert": alert,
                        "sla": {
                            "acknowledgeMinutes": 10,
                            "mitigateMinutes": 60,
                        },
                        "postmortemDueHours": 24,
                        "postmortemTemplate": {
                            "trigger": "",
                            "blastRadius": "",
                            "rootCause": "",
                            "permanentFix": "",
                            "followUpOwnerDate": "",
                        },
                    }),
                ),
            )
            created += int(cursor.rowcount or 0)
        connection.commit()
    return created


def main() -> int:
    controls_payload = get_strikeout_release_controls()
    controls = controls_payload.get("controls") if isinstance(controls_payload, dict) else None
    control_values = controls if isinstance(controls, dict) else None

    calibration = strikeout_calibration_report(control_values)
    calibration_history = strikeout_calibration_history_report(control_values)
    backtest = strikeout_backtest_monitoring(control_values)
    trust_weekly = strikeout_weekly_trust_report(control_values)

    report = {
        "controls": controls_payload,
        "calibration": calibration,
        "calibrationHistory": calibration_history,
        "backtest": backtest,
        "trustWeekly": trust_weekly,
    }
    alerts = _collect_alerts(report)
    opened_incidents = _open_incident_records(alerts)
    report["incidentRecordsOpened"] = opened_incidents
    report["responseSla"] = {
        "acknowledgeMinutes": 10,
        "mitigateCriticalMinutes": 60,
        "postmortemDueHours": 24,
    }
    print(json.dumps(report, indent=2, sort_keys=True))

    fail_on_alert = os.getenv("STRIKEOUT_MONITOR_FAIL_ON_ALERT", "true").strip().lower() != "false"
    if not fail_on_alert:
        return 0
    if any(str(alert.get("severity") or "").lower() == "critical" for alert in alerts):
        print("Strikeout drift alerts detected.", file=sys.stderr)
        return 1
    if calibration.get("available") and not calibration.get("healthy", True):
        print("Strikeout calibration is outside tolerance.", file=sys.stderr)
        return 1
    if calibration_history.get("available") and int(calibration_history.get("hardBreaches") or 0) > 0:
        print("Strikeout calibration history has hard guardrail breaches.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
