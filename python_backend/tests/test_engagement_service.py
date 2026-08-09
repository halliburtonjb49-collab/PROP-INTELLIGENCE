from models.intelligence import SentimentEvent
from services.engagement_service import product_observability, sentiment_rollup


def test_sentiment_rollup_degrades_without_database(monkeypatch) -> None:
    monkeypatch.setattr("services.engagement_service.database_is_configured", lambda: False)
    result = sentiment_rollup("prop-1")
    assert result["label"] == "NEUTRAL"
    assert result["sampleSize"] == 0


def test_product_observability_degrades_without_database(monkeypatch) -> None:
    monkeypatch.setattr("services.engagement_service.database_is_configured", lambda: False)
    result = product_observability(24)
    assert result["available"] is False
    assert result["windowHours"] == 24
    assert result["events"] == {}
    assert result["errors"] == {}

def test_product_observability_actions_are_validated() -> None:
    for action in (
        "APP_OPEN",
        "ONBOARDING_COMPLETE",
        "SITE_FILTER",
        "VERDICT_FILTER",
        "SLOW_LOAD",
        "ERROR",
    ):
        event = SentimentEvent(prop_id="__PRODUCT__", action=action)
        assert event.action == action