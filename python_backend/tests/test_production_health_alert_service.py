from datetime import datetime, timezone

from services import production_health_alert_service as service


def setup_function():
    service._last_alert.clear()


def test_zero_inventory_alert_is_rate_limited(monkeypatch):
    delivered = []
    monkeypatch.setattr(service, "notify_operations_alert", lambda **row: delivered.append(row) or True)
    now = datetime(2026, 9, 6, 20, tzinfo=timezone.utc)

    assert service.alert_prop_health([], now) == ["inventory_zero"]
    assert service.alert_prop_health([], now) == ["inventory_zero"]
    assert len(delivered) == 1


def test_stale_inventory_alerts_without_discarding_rows(monkeypatch):
    class Prop:
        lastUpdatedUtc = "2026-09-06T12:00:00Z"

    delivered = []
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "60")
    monkeypatch.setattr(service, "notify_operations_alert", lambda **row: delivered.append(row) or True)

    issues = service.alert_prop_health(
        [Prop()], datetime(2026, 9, 6, 20, tzinfo=timezone.utc)
    )

    assert issues == ["feed_stale"]
    assert delivered[0]["kind"] == "feed_stale"


def test_model_learning_degradation_alerts(monkeypatch):
    delivered = []
    monkeypatch.setattr(
        service,
        "model_learning_readiness",
        lambda: {"status": "warming", "checks": {"gradingObserved": False}},
    )
    monkeypatch.setattr(service, "notify_operations_alert", lambda **row: delivered.append(row) or True)

    result = service.alert_model_learning(
        datetime(2026, 9, 6, 20, tzinfo=timezone.utc)
    )

    assert result["status"] == "warming"
    assert delivered[0]["kind"] == "model_learning"
