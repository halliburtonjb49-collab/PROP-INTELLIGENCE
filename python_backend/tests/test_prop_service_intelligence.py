from services.prop_service import apply_prop_intelligence_recommendation


def test_apply_prop_intelligence_recommendation_uses_value_when_existing_decision_is_pass() -> None:
    result = apply_prop_intelligence_recommendation(
        {
            "recommendedSide": "N/A",
            "confidence": 0,
            "tier": "No Pick",
            "pickText": "No Pick",
            "recommendationAvailable": False,
            "recommendationUnavailableReason": "probability_below_threshold",
            "recommendationEdge": 0.0,
        },
        projection=24.0,
        line=22.5,
        projected_volatility=4.0,
        over_odds=1.91,
        under_odds=1.91,
        sport="NBA",
        market="player_points",
    )

    assert result["recommendationAvailable"] is True
    assert result["recommendedSide"] == "OVER"
    assert result["confidence"] >= 50
