from datetime import datetime, timedelta, timezone

import scripts.sync_pregame as pregame
from services import operations_notification_service as notifications


def _capture(monkeypatch):
    sent: list[dict] = []
    monkeypatch.setattr(
        pregame,
        "notify_operations_alert",
        lambda **kwargs: sent.append(kwargs) or True,
    )
    return sent


def _readiness(minutes_old: float, recovery: bool = False) -> dict:
    published = datetime.now(timezone.utc) - timedelta(minutes=minutes_old)
    return {
        "catalogPublishedAt": published.isoformat(),
        "source": "durable-snapshot" if recovery else "shared-cache",
        "recovery": recovery,
        "count": 4318,
    }


def test_a_catalog_that_stopped_publishing_raises_an_alert(monkeypatch):
    """The shape of the outage that ran six hours unnoticed.

    Providers answered, every stage reported success, and the only symptom
    was a publication timestamp that stopped moving. Nothing watched it.
    """

    sent = _capture(monkeypatch)
    monkeypatch.setattr(
        pregame, "_request_json_with_retry", lambda *a, **k: _readiness(342)
    )

    pregame._alert_on_a_stalled_feed("https://api.example.com")

    assert sent and sent[0]["kind"] == "feed_stalled"
    assert "342 minutes ago" in sent[0]["summary"]


def test_a_fresh_catalog_stays_quiet(monkeypatch):
    sent = _capture(monkeypatch)
    monkeypatch.setattr(
        pregame, "_request_json_with_retry", lambda *a, **k: _readiness(4)
    )

    pregame._alert_on_a_stalled_feed("https://api.example.com")

    assert sent == []


def test_a_recovery_feed_alerts_even_while_it_looks_fresh(monkeypatch):
    # Serving the durable snapshot means the live catalog is unreachable,
    # which is worth waking someone for even if the snapshot is recent.
    sent = _capture(monkeypatch)
    monkeypatch.setattr(
        pregame,
        "_request_json_with_retry",
        lambda *a, **k: _readiness(3, recovery=True),
    )

    pregame._alert_on_a_stalled_feed("https://api.example.com")

    assert sent and "recovery snapshot" in sent[0]["summary"]


def test_an_unreachable_api_does_not_break_the_cron(monkeypatch):
    sent = _capture(monkeypatch)

    def _boom(*_args, **_kwargs):
        raise RuntimeError("connection refused")

    monkeypatch.setattr(pregame, "_request_json_with_retry", _boom)

    pregame._alert_on_a_stalled_feed("https://api.example.com")

    assert sent == []


def test_an_actionable_tier_that_stopped_paying_raises_an_alert(monkeypatch):
    sent = _capture(monkeypatch)

    pregame._alert_on_a_tier_that_stopped_paying(
        [
            {"tier": "Premium", "actionable": True,
             "profitability": "proven_profitable"},
            {"tier": "Strong", "actionable": True,
             "profitability": "proven_unprofitable"},
        ]
    )

    assert sent and sent[0]["kind"] == "tier_unprofitable"
    assert "Strong" in sent[0]["summary"]


def test_a_tier_within_noise_does_not_cry_wolf(monkeypatch):
    """A flag that fires on noise is one everybody learns to ignore."""

    sent = _capture(monkeypatch)

    pregame._alert_on_a_tier_that_stopped_paying(
        [{"tier": "Strong", "actionable": True,
          "profitability": "not_distinguishable"}]
    )

    assert sent == []


def test_a_losing_tier_nobody_is_told_to_bet_stays_quiet(monkeypatch):
    sent = _capture(monkeypatch)

    pregame._alert_on_a_tier_that_stopped_paying(
        [{"tier": "Pass", "actionable": False,
          "profitability": "proven_unprofitable"}]
    )

    assert sent == []


def test_no_webhook_configured_is_not_an_error(monkeypatch):
    monkeypatch.delenv("PIPELINE_ALERT_WEBHOOK_URL", raising=False)

    assert notifications.notify_operations_alert(
        kind="feed_stalled", summary="anything"
    ) is False


def _sent_payload(monkeypatch, send) -> dict:
    import json

    captured: dict = {}

    class _Response:
        status = 204

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def _urlopen(request, timeout=None):
        captured.update(json.loads(request.data.decode("utf-8")))
        return _Response()

    monkeypatch.setenv("PIPELINE_ALERT_WEBHOOK_URL", "https://example.invalid/hook")
    monkeypatch.setattr(notifications, "urlopen", _urlopen)
    send()
    return captured


def test_alerts_speak_both_webhook_dialects(monkeypatch):
    """Slack reads `text`; Discord reads `content` and ignores `text`.

    A webhook that speaks the other dialect answers 400, which this module
    swallows on purpose, so the alerts would simply never arrive and nothing
    would say why. One duplicated string removes that failure mode.
    """

    payload = _sent_payload(
        monkeypatch,
        lambda: notifications.notify_operations_alert(
            kind="feed_stalled", summary="catalog last published 342 minutes ago"
        ),
    )

    assert payload["text"] == payload["content"]
    assert "342 minutes" in payload["content"]


def test_pipeline_failures_speak_both_dialects_too(monkeypatch):
    payload = _sent_payload(
        monkeypatch,
        lambda: notifications.notify_pipeline_issue(
            "pregame-sync", "PARTIAL", [{"stage": "odds-sync", "error": "boom"}]
        ),
    )

    assert payload["text"] == payload["content"]
    assert "PARTIAL" in payload["content"]
