from statistics import NormalDist
from typing import Any

from services.projection_calibration_service import (
    confidence_from_probability,
    market_volatility_floor,
)


def safe_float(value: object, default: float | None = None) -> float | None:
    try:
        if value is None:
            return default
        return float(value)
    except (ValueError, TypeError):
        return default


# Measured against 25,685 graded predictions carrying a displayed
# confidence, grouped by the tier the board actually showed:
#
#   Premium 65+    n=2398   claimed 69.1%   hit 71.6%   flat ROI  +7.6%
#   Strong  60-64  n=2464   claimed 61.6%   hit 60.3%   flat ROI  -2.2%
#   Lean    57-59  n=2859   claimed 57.9%   hit 54.0%   flat ROI  -9.1%
#   Pass    50-56  n=17964  claimed 51.9%   hit 47.0%   flat ROI -16.5%
#
# The ladder discriminates and the top of it beats its own claim, but the
# 57-59 band did not: it was presented as playable, missed its stated hit
# rate by four points, and lost money flat-staked. A tier that costs the
# user money is worse than no tier, so that band is now Pass. The two
# thresholds that survive keep the meaning they already had, so nothing a
# user learned about Premium or Strong changes underneath them.
ACTIONABLE_CONFIDENCE_FLOOR = 60
PREMIUM_CONFIDENCE_FLOOR = 65


def tier_from_confidence(confidence: int, side: str = "") -> str:
    """Bucket a confidence into the strength label the board displays.

    Single definition on purpose. This lived in four places, and the copy
    behind the uncertainty gate had no floor at all, so a prop the gate
    called actionable was labelled Lean at any confidence whatsoever.
    """

    if side == "Pass":
        return "Pass"
    if confidence >= PREMIUM_CONFIDENCE_FLOOR:
        return "Premium"
    if confidence >= ACTIONABLE_CONFIDENCE_FLOOR:
        return "Strong"
    return "Pass"


def _tier_from_confidence(confidence: int, side: str) -> str:
    return tier_from_confidence(confidence, side)


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
    *,
    sport: str = "",
    market: str = "",
    volatility: object = None,
) -> dict[str, Any]:
    """Side, edge and confidence for a projection against a line.

    Confidence comes from how far the projection sits from the line measured
    in the market's own spread, not from the raw difference. A yard of
    receiving yards and a strikeout are not the same distance: scaling the
    gap by a linear constant made a trivial move on a wide market outrank a
    large one on a tight market. The edge itself stays in stat units, since
    that is what a card displays.
    """
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

    # The market's typical spread, so the same gap means the same thing
    # whichever market it came from.
    sigma = safe_float(volatility) or market_volatility_floor(sport, market)
    sigma = max(1e-6, float(sigma))
    win_probability = NormalDist().cdf(edge / sigma)
    confidence = max(50, min(confidence_from_probability(win_probability), 99))

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
    confidence_override: int | None = None,
    data_quality_score: float = 1.0,
    data_quality_reasons: list[str] | None = None,
) -> dict[str, Any]:
    """Return a model recommendation only when its required inputs are real."""
    projection_value = safe_float(projection)
    line_value = safe_float(line)
    if projection_value is None or line_value is None:
        return {
            **build_prop_recommendation(None, line),
            "recommendationAvailable": False,
            "recommendationUnavailableReason": "projection_unavailable",
            "explanation": "No recommendation is available because a verified projection could not be produced.",
            "dataQualityScore": 0.0,
            "dataQualityReasons": ["projection_unavailable"],
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
            "explanation": "No recommendation is available because the player identity could not be verified.",
            "dataQualityScore": round(max(0.0, min(1.0, data_quality_score)), 3),
            "dataQualityReasons": ["player_identity_unresolved"],
        }
    quality = max(0.0, min(1.0, float(data_quality_score)))
    quality_reasons = list(data_quality_reasons or [])
    if quality < 0.6:
        return {
            **build_prop_recommendation(None, line),
            "recommendationAvailable": False,
            "recommendationUnavailableReason": "insufficient_data_quality",
            "explanation": "No Pro recommendation is shown because the supporting data does not meet the quality threshold.",
            "dataQualityScore": round(quality, 3),
            "dataQualityReasons": quality_reasons or ["quality_threshold_not_met"],
        }

    recommendation = build_prop_recommendation(projection_value, line)
    if confidence_override is not None:
        confidence = max(50, min(99, int(confidence_override)))
        recommendation["confidence"] = confidence
        recommendation["tier"] = _tier_from_confidence(
            confidence,
            str(recommendation["recommendedSide"]),
        )
        recommendation["pickText"] = _pick_text(
            str(recommendation["recommendedSide"]),
            safe_float(line),
            str(recommendation["tier"]),
        )
    return {
        **recommendation,
        "recommendationAvailable": True,
        "recommendationUnavailableReason": "",
        "explanation": (
            f"The model projects {projection_value:g}, which is "
            f"{abs(projection_value - float(line_value)):g} "
            f"{'above' if projection_value > float(line_value) else 'below'} "
            f"the selected line of {float(line_value):g}."
        ),
        "dataQualityScore": round(quality, 3),
        "dataQualityReasons": quality_reasons,
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
