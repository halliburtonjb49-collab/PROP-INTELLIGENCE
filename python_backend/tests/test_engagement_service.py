from models.intelligence import SentimentEvent
from services.engagement_service import _funnel_rows, product_observability, sentiment_rollup


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
        "DASHBOARD_READY",
        "ONBOARDING_COMPLETE",
        "SITE_FILTER",
        "VERDICT_FILTER",
        "PROP_SELECTED",
        "SLIP_LOCKED",
        "PAYWALL_VIEW",
        "CHECKOUT_STARTED",
        "CHECKOUT_FAILED",
        "PURCHASE_COMPLETED",
        "SLOW_LOAD",
        "ERROR",
    ):
        event = SentimentEvent(prop_id="__PRODUCT__", action=action)
        assert event.action == action

def test_product_funnels_use_unique_users_and_prior_stage_conversion() -> None:
    result = _funnel_rows(
        {
            "APP_OPEN": 20,
            "DASHBOARD_READY": 18,
            "PROP_SELECTED": 10,
            "SLIP_LOCKED": 4,
        },
        {
            "APP_OPEN": 10,
            "DASHBOARD_READY": 9,
            "PROP_SELECTED": 5,
            "SLIP_LOCKED": 2,
        },
    )

    research = result["research"]
    assert research[1]["conversionFromPrevious"] == 0.9
    assert research[2]["conversionFromPrevious"] == 0.5556
    assert research[3]["conversionFromPrevious"] == 0.4
    assert research[3]["events"] == 4
