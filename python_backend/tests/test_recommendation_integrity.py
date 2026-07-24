from services.prop_recommendation_service import (
    build_prop_recommendation_with_fallback,
    build_verified_prop_recommendation,
)


def test_missing_projection_suppresses_recommendation() -> None:
    result = build_verified_prop_recommendation(
        projection=None,
        line=24.5,
        canonical_player_id="odds-api:123",
        identity_confidence=1.0,
    )
    assert result["recommendationAvailable"] is False
    assert result["recommendationUnavailableReason"] == "projection_unavailable"
    assert result["recommendedSide"] == "N/A"
    assert result["confidence"] == 0
    assert result["edge"] == 0
    assert result["tier"] == "No Pick"


def test_unresolved_identity_suppresses_modeled_projection() -> None:
    result = build_verified_prop_recommendation(
        projection=27.2,
        line=24.5,
        canonical_player_id="unresolved:odds-api:test-player",
        identity_confidence=0.0,
    )
    assert result["recommendationAvailable"] is False
    assert result["recommendationUnavailableReason"] == "player_identity_unresolved"
    assert result["recommendedSide"] == "N/A"
    assert result["confidence"] == 0


def test_verified_projection_and_identity_produce_recommendation() -> None:
    result = build_verified_prop_recommendation(
        projection=27.2,
        line=24.5,
        canonical_player_id="odds-api:123",
        identity_confidence=0.82,
    )
    assert result["recommendationAvailable"] is True
    assert result["recommendationUnavailableReason"] == ""
    assert result["recommendedSide"] == "Over"
    assert result["confidence"] > 0
    assert result["edge"] == 2.7


def test_odds_fallback_is_not_exposed_as_model_confidence() -> None:
    result = build_prop_recommendation_with_fallback(
        projection=None,
        line=0.5,
        odds_pick="UNDER",
        odds_confidence=99,
    )
    assert result["recommendedSide"] == "N/A"
    assert result["confidence"] == 0
    assert result["tier"] == "No Pick"
