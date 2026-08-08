from services import founding_pro_service


class Cursor:
    def __init__(self, results):
        self.results = list(results)
        self.queries = []

    def execute(self, query, params=None):
        self.queries.append((query, params))

    def fetchone(self):
        return self.results.pop(0)


def test_founding_product_mapping_is_explicit(monkeypatch):
    monkeypatch.setenv(
        "REVENUECAT_FOUNDING_PRODUCT_IDS",
        "founding-monthly, founding-annual",
    )

    assert founding_pro_service.is_founding_event(
        {"product_id": "founding-monthly"}
    )
    assert not founding_pro_service.is_founding_event(
        {"product_id": "regular-pro"}
    )


def test_webhook_rejects_an_unreserved_purchase_when_capacity_is_full(
    monkeypatch,
):
    monkeypatch.setenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "founding-monthly")
    monkeypatch.setenv("FOUNDING_PRO_MEMBER_LIMIT", "100")
    cursor = Cursor([None, (100,)])

    result = founding_pro_service.apply_founding_event(
        cursor,
        {"type": "INITIAL_PURCHASE", "product_id": "founding-monthly"},
        "00000000-0000-0000-0000-000000000101",
    )

    assert result is not None
    assert result["foundingRejected"] is True
    assert result["tier"] == "free"
    assert not any("insert into founding_pro_claims" in query for query, _ in cursor.queries)


def test_reserved_member_is_activated_without_exceeding_capacity(monkeypatch):
    monkeypatch.setenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "founding-monthly")
    cursor = Cursor([("reserved",)])

    result = founding_pro_service.apply_founding_event(
        cursor,
        {"type": "INITIAL_PURCHASE", "product_id": "founding-monthly"},
        "00000000-0000-0000-0000-000000000100",
    )

    assert result is None
    assert any("insert into founding_pro_claims" in query for query, _ in cursor.queries)


def test_expiration_releases_price_but_not_the_lifetime_claim(monkeypatch):
    monkeypatch.setenv("REVENUECAT_FOUNDING_PRODUCT_IDS", "founding-monthly")
    cursor = Cursor([])

    result = founding_pro_service.apply_founding_event(
        cursor,
        {"type": "EXPIRATION", "product_id": "founding-monthly"},
        "00000000-0000-0000-0000-000000000001",
    )

    assert result is None
    assert any("status='released'" in query for query, _ in cursor.queries)
    assert not any("delete from founding_pro_claims" in query for query, _ in cursor.queries)
