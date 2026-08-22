from services import billing_certification_service


def test_billing_certification_passes_complete_recorded_catalog(monkeypatch):
    monkeypatch.setenv("REVENUECAT_WEBHOOK_SECRET", "secret")
    monkeypatch.setenv("REVENUECAT_PUBLIC_API_KEY", "public")
    monkeypatch.setenv("REVENUECAT_CORE_PRODUCT_IDS", "core-monthly,core-annual")
    monkeypatch.setenv("REVENUECAT_EDGE_PRODUCT_IDS", "pro-monthly,pro-annual")
    monkeypatch.setenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "founding-monthly,founding-annual")
    monkeypatch.setenv("FOUNDING_PRO_MEMBER_LIMIT", "100")
    monkeypatch.setenv("BILLING_CATALOG_VERIFIED", "true")
    monkeypatch.setenv("BILLING_CATALOG_VERIFIED_AT", "2026-08-09T20:00:00Z")
    monkeypatch.setattr(
        billing_certification_service,
        "_delivery_snapshot",
        lambda: {"webhookEventCount": 3, "lastWebhookAt": "2026-08-09T20:00:00Z"},
    )

    result = billing_certification_service.billing_release_certification()

    assert result["status"] == "PASS"
    assert result["releaseReady"] is True
    assert result["expectedCatalog"]["pro"]["monthlyUsd"] == 59.99
    assert result["expectedCatalog"]["monthlyTrialDays"] == 3


def test_billing_certification_blocks_missing_mappings_and_wrong_cap(monkeypatch):
    for name in (
        "REVENUECAT_WEBHOOK_SECRET",
        "REVENUECAT_PUBLIC_API_KEY",
        "REVENUECAT_CORE_PRODUCT_IDS",
        "REVENUECAT_EDGE_PRODUCT_IDS",
        "REVENUECAT_FOUNDING_PRODUCT_IDS",
        "BILLING_CATALOG_VERIFIED",
        "BILLING_CATALOG_VERIFIED_AT",
    ):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("FOUNDING_PRO_MEMBER_LIMIT", "25")
    monkeypatch.setattr(
        billing_certification_service,
        "_delivery_snapshot",
        lambda: {"webhookEventCount": 0, "lastWebhookAt": None},
    )

    result = billing_certification_service.billing_release_certification()

    assert result["status"] == "FAIL"
    assert result["releaseReady"] is False
    failed = {check["key"] for check in result["checks"] if check["status"] == "FAIL"}
    assert {
        "webhook_auth",
        "public_billing_key",
        "core_packages",
        "pro_packages",
        "founding_packages",
        "founding_cap",
    } <= failed
