from models.intelligence import SentimentEvent
from services.engagement_service import (
    _funnel_rows,
    _preferred_p95,
    product_observability,
    sentiment_rollup,
)


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
        "AUTH_READY",
        "PROP_CACHE_PAINT",
        "PROP_LIVE_APPLY",
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


def test_content_milestones_replace_legacy_timing_when_available() -> None:
    operational = {
        "SCREEN_TIMING": {"count": 10, "p95Ms": 900},
        "PROP_CACHE_PAINT": {"count": 4, "p95Ms": 1250},
        "PROP_LOAD_SUCCESS": {"count": 10, "p95Ms": 1800},
        "PROP_LIVE_APPLY": {"count": 4, "p95Ms": 2100},
    }
    assert _preferred_p95(
        operational, "PROP_CACHE_PAINT", "SCREEN_TIMING"
    ) == 1250
    assert _preferred_p95(
        operational, "PROP_LIVE_APPLY", "PROP_LOAD_SUCCESS"
    ) == 2100


def test_content_milestones_fall_back_for_older_clients() -> None:
    operational = {
        "SCREEN_TIMING": {"count": 10, "p95Ms": 900},
        "PROP_LOAD_SUCCESS": {"count": 10, "p95Ms": 1800},
    }
    assert _preferred_p95(
        operational, "PROP_CACHE_PAINT", "SCREEN_TIMING"
    ) == 900
    assert _preferred_p95(
        operational, "PROP_LIVE_APPLY", "PROP_LOAD_SUCCESS"
    ) == 1800
