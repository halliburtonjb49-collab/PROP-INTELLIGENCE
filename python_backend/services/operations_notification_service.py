"""Best-effort notifications for production pipeline failures.

Every payload carries the message under both ``text`` and ``content``.
Slack incoming webhooks read the first and Discord reads the second, and a
webhook that speaks the other dialect does not fail loudly -- it returns a
400 that this module swallows by design, so the alerts would simply never
arrive and nothing would say why. Sending both costs a duplicated string
and removes an entire class of silent misconfiguration.
"""

from __future__ import annotations

import json
import logging
import os
from urllib.error import HTTPError
from urllib.request import Request, urlopen


# urllib announces itself as "Python-urllib/3.12", and Discord's edge
# refuses that with a 403 before the webhook is ever reached. The failure is
# indistinguishable from a quiet channel: delivery returns False, the caller
# carries on, and the alerts simply never arrive. Any honest agent string is
# accepted.
_USER_AGENT = "PropIntelligenceAlerts/1.0 (+https://propsintell.com)"


def _deliver(webhook: str, payload: bytes, *, kind: str) -> bool:
    """POST one alert, and say why when it does not land.

    Delivery failures are swallowed on purpose -- an alert that cannot be
    sent must not take a pipeline down with it -- so the log line is the
    only evidence that exists. It carries the status and the provider's own
    message, because "delivery failed" cost an evening once already.
    """

    request = Request(
        webhook,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": _USER_AGENT,
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:  # noqa: S310 - operator-configured webhook
            return 200 <= response.status < 300
    except HTTPError as error:
        detail = ""
        try:
            detail = error.read().decode("utf-8", "replace")[:200]
        except Exception:
            detail = ""
        logging.error(
            "Alert rejected kind=%s status=%s detail=%s",
            kind,
            error.code,
            detail,
        )
        return False
    except Exception:
        logging.exception("Alert delivery failed kind=%s", kind)
        return False


def notify_pipeline_issue(pipeline: str, status: str, errors: list[dict[str, object]]) -> bool:
    webhook = os.getenv("PIPELINE_ALERT_WEBHOOK_URL", "").strip()
    if not webhook or status == "SUCCEEDED":
        return False
    message = f"PROP INTELLIGENCE: {pipeline} finished {status}"
    payload = json.dumps({
        "text": message,
        "content": message,
        "pipeline": pipeline,
        "status": status,
        "errors": errors[:10],
    }).encode("utf-8")
    return _deliver(webhook, payload, kind=f"pipeline:{pipeline}")


def notify_operations_alert(
    *,
    kind: str,
    summary: str,
    details: dict[str, object] | None = None,
) -> bool:
    """Raise a condition that no pipeline reported as a failure.

    Pipeline alerts only fire when a run ends badly. The expensive outages
    are the quiet ones: a catalog that stopped publishing while every stage
    reported success, or a tier still labelled playable months after it
    stopped paying. Those need a channel of their own, because by
    definition nothing else is going to raise them.
    """

    webhook = os.getenv("PIPELINE_ALERT_WEBHOOK_URL", "").strip()
    if not webhook:
        return False
    message = f"PROP INTELLIGENCE: {summary}"
    payload = json.dumps(
        {
            "text": message,
            "content": message,
            "kind": kind,
            "summary": summary,
            "details": details or {},
        },
        default=str,
    ).encode("utf-8")
    return _deliver(webhook, payload, kind=kind)


def notify_member_signup(*, user_id: str, email: str = "", source: str = "") -> bool:
    webhook = os.getenv("MEMBER_SIGNUP_ALERT_WEBHOOK_URL", "").strip()
    if not webhook:
        webhook = os.getenv("PIPELINE_ALERT_WEBHOOK_URL", "").strip()
    if not webhook:
        return False

    identity = email.strip() or user_id.strip() or "unknown"
    message = f"PROP INTELLIGENCE: New member signup {identity}"
    payload = json.dumps(
        {
            "text": message,
            "content": message,
            "event": "member_signup",
            "userId": user_id.strip()[:120],
            "email": email.strip()[:240],
            "source": source.strip()[:80] or "app",
        }
    ).encode("utf-8")
    return _deliver(webhook, payload, kind="member_signup")
