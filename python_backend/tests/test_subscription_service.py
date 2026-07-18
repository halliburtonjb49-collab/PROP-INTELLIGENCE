from services.subscription_service import tier_from_event


def test_edge_entitlement_wins() -> None:
    assert tier_from_event({"type": "RENEWAL", "entitlement_ids": ["core_tier", "edge_tier"]}) == "edge"


def test_core_entitlement_maps_to_core() -> None:
    assert tier_from_event({"type": "INITIAL_PURCHASE", "entitlement_ids": ["core_tier"]}) == "core"


def test_expiration_removes_access() -> None:
    assert tier_from_event({"type": "EXPIRATION", "entitlement_ids": ["edge_tier"]}) == "free"


def test_unknown_product_does_not_grant_access() -> None:
    assert tier_from_event({"type": "INITIAL_PURCHASE", "product_id": "unknown"}) is None
