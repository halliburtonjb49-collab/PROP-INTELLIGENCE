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
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


# urllib announces itself as "Python-urllib/3.12", and Discord's edge
# refuses that with a 403 before the webhook is ever reached. The failure is
# indistinguishable from a quiet channel: delivery returns False, the caller
# carries on, and the alerts simply never arrive. Any honest agent string is
# accepted.
_USER_AGENT = "PropIntelligenceAlerts/1.0 (+https://propsintell.com)"


# What the last delivery did. Failures are swallowed on purpose -- an alert
# that cannot be sent must not take a pipeline down -- which means a
# misconfigured channel looks exactly like a quiet one. It looked exactly
# like one for a whole day: the configured URL was answering 405 because it
# was not an incoming-webhook endpoint, and nothing said so.
_LAST_DELIVERY: dict[str, object] = {}

# The two hosts that publish incoming webhooks, and the path each uses.
_KNOWN_WEBHOOKS = (
    ("discord.com", "/api/webhooks/"),
    ("discordapp.com", "/api/webhooks/"),
    ("hooks.slack.com", "/services/"),
)


def alert_channel_health() -> dict[str, object]:
    """Whether alerts can actually be delivered, without exposing the URL.

    Reports the shape of the configured endpoint and the outcome of the last
    attempt. Never returns the URL itself: it is a credential, and the point
    of this is to be readable from an operations page.
    """

    webhook = os.getenv("PIPELINE_ALERT_WEBHOOK_URL", "").strip()
    if not webhook:
        return {"configured": False, "deliverable": False,
                "reason": "PIPELINE_ALERT_WEBHOOK_URL is not set"}
    parsed = urlparse(webhook)
    host = parsed.netloc.lower()
    looks_like_webhook = any(
        host.endswith(known_host) and parsed.path.startswith(known_path)
        for known_host, known_path in _KNOWN_WEBHOOKS
    )
    status = {
        "configured": True,
        "host": host,
        # A channel URL and a webhook URL share a host and differ only in
        # path, which is exactly how one gets pasted in place of the other.
        "looksLikeIncomingWebhook": looks_like_webhook,
        "lastAttemptAt": _LAST_DELIVERY.get("at"),
        "lastOutcome": _LAST_DELIVERY.get("outcome"),
        "lastStatus": _LAST_DELIVERY.get("status"),
        "lastDetail": _LAST_DELIVERY.get("detail"),
    }
    if not looks_like_webhook:
        status["deliverable"] = False
        status["reason"] = (
            "The configured URL is not an incoming-webhook endpoint. Discord "
            "webhooks are https://discord.com/api/webhooks/... and Slack "
            "webhooks are https://hooks.slack.com/services/..."
        )
        return status
    delivered = _LAST_DELIVERY.get("outcome")
    status["deliverable"] = delivered != "rejected"
    if delivered == "rejected":
        status["reason"] = (
            f"The endpoint rejected the last alert with "
            f"{_LAST_DELIVERY.get('status')}"
        )
    return status


def _record_delivery(
    *, outcome: str, status: object = None, detail: str = "",
) -> None:
    _LAST_DELIVERY.update(
        {
            "at": datetime.now(timezone.utc).isoformat(),
            "outcome": outcome,
            "status": status,
            "detail": detail[:200],
        }
    )


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
            accepted = 200 <= response.status < 300
            _record_delivery(
                outcome="delivered" if accepted else "rejected",
                status=response.status,
            )
            return accepted
    except HTTPError as error:
        detail = ""
        try:
            detail = error.read().decode("utf-8", "replace")[:200]
        except Exception:
            detail = ""
        _record_delivery(
            outcome="rejected", status=error.code, detail=detail,
        )
        logging.error(
            "Alert rejected kind=%s status=%s detail=%s",
            kind,
            error.code,
            detail,
        )
        return False
    except Exception as exc:
        _record_delivery(outcome="unreachable", detail=str(exc))
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
