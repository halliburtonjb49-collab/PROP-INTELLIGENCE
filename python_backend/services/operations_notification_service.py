"""Best-effort notifications for production pipeline failures."""

from __future__ import annotations

import json
import logging
import os
from urllib.request import Request, urlopen


def notify_pipeline_issue(pipeline: str, status: str, errors: list[dict[str, object]]) -> bool:
    webhook = os.getenv("PIPELINE_ALERT_WEBHOOK_URL", "").strip()
    if not webhook or status == "SUCCEEDED":
        return False
    payload = json.dumps({
        "text": f"PROP INTELLIGENCE: {pipeline} finished {status}",
        "pipeline": pipeline,
        "status": status,
        "errors": errors[:10],
    }).encode("utf-8")
    try:
        request = Request(webhook, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        with urlopen(request, timeout=10) as response:  # noqa: S310 - operator-configured webhook
            return 200 <= response.status < 300
    except Exception:
        logging.exception("Pipeline alert delivery failed pipeline=%s", pipeline)
        return False


def notify_member_signup(*, user_id: str, email: str = "", source: str = "") -> bool:
    webhook = os.getenv("MEMBER_SIGNUP_ALERT_WEBHOOK_URL", "").strip()
    if not webhook:
        webhook = os.getenv("PIPELINE_ALERT_WEBHOOK_URL", "").strip()
    if not webhook:
        return False

    identity = email.strip() or user_id.strip() or "unknown"
    payload = json.dumps(
        {
            "text": f"PROP INTELLIGENCE: New member signup {identity}",
            "event": "member_signup",
            "userId": user_id.strip()[:120],
            "email": email.strip()[:240],
            "source": source.strip()[:80] or "app",
        }
    ).encode("utf-8")
    try:
        request = Request(
            webhook,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=10) as response:  # noqa: S310 - operator-configured webhook
            return 200 <= response.status < 300
    except Exception:
        logging.exception("Member signup alert delivery failed user_id=%s", user_id)
        return False
