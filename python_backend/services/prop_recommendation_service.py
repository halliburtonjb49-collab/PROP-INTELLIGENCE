from typing import Any


def safe_float(value: object, default: float | None = None) -> float | None:
    try:
        if value is None:
            return default
        return float(value)
    except (ValueError, TypeError):
        return default


def _tier_from_confidence(confidence: int, side: str) -> str:
    if side == "Pass":
        return "Pass"
    if confidence >= 65:
        return "Premium"
    if confidence >= 60:
        return "Strong"
    if confidence >= 57:
        return "Lean"
    return "Pass"


def _pick_text(side: str, line: float | None, tier: str) -> str:
    if tier == "Pass" or side in {"Pass", "N/A"}:
        return "Pass"
    if line is None:
        return side
    line_text = str(int(line)) if float(line).is_integer() else str(line)
    return f"{side} {line_text}"


def build_prop_recommendation(
    projection: object,
    line: object,
) -> dict[str, Any]:
    projection_value = safe_float(projection)
    line_value = safe_float(line)

    if projection_value is None or line_value is None:
        return {
            "recommendedSide": "N/A",
            "confidence": 0,
            "edge": 0.0,
            "recommendationEdge": 0.0,
            "tier": "No Pick",
            "pickText": "No Pick",
        }

    difference = projection_value - line_value

    if difference > 0:
        side = "Over"
    elif difference < 0:
        side = "Under"
    else:
        side = "Pass"

    edge = abs(difference)

    confidence = round(50 + (edge * 12))
    confidence = max(50, min(confidence, 99))

    tier = _tier_from_confidence(confidence, side)
    pick_text = _pick_text(side, line_value, tier)

    return {
        "recommendedSide": side,
        "confidence": confidence,
        "edge": round(edge, 2),
        "recommendationEdge": round(edge, 2),
        "tier": tier,
        "pickText": pick_text,
    }


def build_verified_prop_recommendation(
    *,
    projection: object,
    line: object,
    canonical_player_id: str,
    identity_confidence: float,
) -> dict[str, Any]:
    """Return a model recommendation only when its required inputs are real."""
    projection_value = safe_float(projection)
    if projection_value is None:
        return {
            **build_prop_recommendation(None, line),
            "recommendationAvailable": False,
            "recommendationUnavailableReason": "projection_unavailable",
        }

    canonical = canonical_player_id.strip().lower()
    if (
        not canonical
        or canonical.startswith("unresolved:")
        or identity_confidence < 0.8
    ):
        return {
            **build_prop_recommendation(None, line),
            "recommendationAvailable": False,
            "recommendationUnavailableReason": "player_identity_unresolved",
        }

    return {
        **build_prop_recommendation(projection_value, line),
        "recommendationAvailable": True,
        "recommendationUnavailableReason": "",
    }


def get_over_under_pick(
    projection: object,
    line: object,
) -> dict[str, Any]:
    # Compatibility helper for callers that only need side/pick/edge/confidence.
    recommendation = build_prop_recommendation(
        projection=projection,
        line=line,
    )
    return {
        "recommendedSide": recommendation["recommendedSide"],
        "pickText": recommendation["pickText"],
        "edge": recommendation["edge"],
        "confidence": recommendation["confidence"],
    }


def build_prop_recommendation_with_fallback(
    *,
    projection: object,
    line: object,
    odds_pick: str,
    odds_confidence: int,
) -> dict[str, Any]:
    """Deprecated compatibility wrapper.

    Odds-derived direction and confidence are market signals, not model
    projections, so they must never be promoted into a model recommendation.
    """
    recommendation = build_prop_recommendation(projection, line)
    return recommendation
