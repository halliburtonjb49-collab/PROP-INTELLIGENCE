import json
from collections import defaultdict
from typing import Any

from models.prop_builder_strategy import (
    PropBuilderStrategyResponse,
    StrategyRecommendation,
)
from services.market_normalizer import normalize_market
from services.prop_builder_history_service import (
    _connect,
    initialize_prop_builder_history,
)

MINIMUM_RESOLVED_LEGS = 10
MINIMUM_CATEGORY_SAMPLE = 5


def _empty_group() -> dict[str, float]:
    return {
        "total": 0,
        "won": 0,
        "lost": 0,
        "pushed": 0,
        "edge_total": 0,
        "confidence_total": 0,
    }


def _safe_float(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0


def _add_leg(
    *,
    group: dict[str, float],
    status: str,
    edge: float,
    confidence: float,
) -> None:
    group["total"] += 1
    group["edge_total"] += edge
    group["confidence_total"] += confidence
    if status == "won":
        group["won"] += 1
    elif status == "lost":
        group["lost"] += 1
    elif status == "push":
        group["pushed"] += 1


def _to_recommendation(
    *,
    name: str,
    group: dict[str, float],
) -> StrategyRecommendation:
    resolved = int(
        group["won"]
        + group["lost"]
        + group["pushed"]
    )
    hit_rate = (
        round(
            group["won"] / resolved * 100,
            1,
        )
        if resolved > 0
        else 0
    )
    total = int(group["total"])
    return StrategyRecommendation(
        name=name,
        sample_size=resolved,
        hit_rate=hit_rate,
        average_edge=(
            round(
                group["edge_total"] / total,
                1,
            )
            if total > 0
            else 0
        ),
        average_confidence=(
            round(
                group["confidence_total"] / total,
                1,
            )
            if total > 0
            else 0
        ),
    )


def _best_group(
    groups: dict[
        str,
        dict[str, float],
    ],
) -> StrategyRecommendation | None:
    recommendations = [
        _to_recommendation(
            name=name,
            group=group,
        )
        for name, group in groups.items()
    ]
    qualified = [
        item
        for item in recommendations
        if item.sample_size
        >= MINIMUM_CATEGORY_SAMPLE
    ]
    if not qualified:
        return None

    qualified.sort(
        key=lambda item: (
            item.hit_rate,
            item.sample_size,
            item.average_edge,
        ),
        reverse=True,
    )
    return qualified[0]


def _leg_result_status(leg: dict[str, Any]) -> str:
    status = str(
        leg.get(
            "result_status",
            leg.get(
                "result",
                leg.get(
                    "status",
                    "pending",
                ),
            ),
        )
    ).lower()
    if status in {"won", "win"}:
        return "won"
    if status in {"lost", "loss"}:
        return "lost"
    if status in {"push", "pushed"}:
        return "push"
    return "pending"


def get_prop_builder_strategy() -> PropBuilderStrategyResponse:
    initialize_prop_builder_history()
    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT legs_json
            FROM prop_builder_history
            ORDER BY created_at DESC
            """
        ).fetchall()

    sport_groups: dict[
        str,
        dict[str, float],
    ] = defaultdict(_empty_group)
    site_groups: dict[
        str,
        dict[str, float],
    ] = defaultdict(_empty_group)
    market_groups: dict[
        str,
        dict[str, float],
    ] = defaultdict(_empty_group)

    resolved_legs = 0
    winning_edges: list[float] = []
    winning_confidences: list[float] = []
    resolved_build_sizes: list[int] = []

    for row in rows:
        legs = json.loads(
            row["legs_json"]
        )
        resolved_in_build = 0
        for leg in legs:
            if not isinstance(leg, dict):
                continue

            status = _leg_result_status(leg)
            if status not in {
                "won",
                "lost",
                "push",
            }:
                continue

            resolved_legs += 1
            resolved_in_build += 1

            sport = str(
                leg.get(
                    "sport",
                    "Unknown",
                )
            ).strip() or "Unknown"
            site = str(
                leg.get(
                    "prop_site",
                    leg.get(
                        "sportsbook",
                        "Unknown",
                    ),
                )
            ).strip() or "Unknown"
            market = normalize_market(
                str(
                    leg.get(
                        "market",
                        "Unknown",
                    )
                )
            )
            edge = _safe_float(
                leg.get("edge")
            )
            confidence = _safe_float(
                leg.get(
                    "confidence",
                    edge,
                )
            )

            _add_leg(
                group=sport_groups[sport],
                status=status,
                edge=edge,
                confidence=confidence,
            )
            _add_leg(
                group=site_groups[site],
                status=status,
                edge=edge,
                confidence=confidence,
            )
            _add_leg(
                group=market_groups[market],
                status=status,
                edge=edge,
                confidence=confidence,
            )

            if status == "won":
                winning_edges.append(edge)
                winning_confidences.append(
                    confidence
                )

        if resolved_in_build > 0:
            resolved_build_sizes.append(
                resolved_in_build
            )

    warnings: list[str] = []
    enough_data = (
        resolved_legs >=
        MINIMUM_RESOLVED_LEGS
    )

    if not enough_data:
        warnings.append(
            "More graded legs are needed before "
            "the strategy recommendations are reliable."
        )

    best_sport = _best_group(
        sport_groups
    )
    best_site = _best_group(
        site_groups
    )
    best_market = _best_group(
        market_groups
    )

    if best_sport is None:
        warnings.append(
            "No sport has at least five "
            "resolved legs yet."
        )
    if best_site is None:
        warnings.append(
            "No prop site has at least five "
            "resolved legs yet."
        )
    if best_market is None:
        warnings.append(
            "No market has at least five "
            "resolved legs yet."
        )

    recommended_edge = 60
    if winning_edges:
        recommended_edge = round(
            sum(winning_edges)
            / len(winning_edges)
        )
        recommended_edge = max(
            50,
            min(recommended_edge, 90),
        )

    recommended_confidence = 60
    if winning_confidences:
        recommended_confidence = round(
            sum(winning_confidences)
            / len(winning_confidences)
        )
        recommended_confidence = max(
            50,
            min(
                recommended_confidence,
                95,
            ),
        )

    recommended_leg_count = 3
    if resolved_build_sizes:
        average_size = round(
            sum(resolved_build_sizes)
            / len(resolved_build_sizes)
        )
        recommended_leg_count = max(
            2,
            min(average_size, 8),
        )

    return PropBuilderStrategyResponse(
        enough_data=enough_data,
        minimum_required_legs=(
            MINIMUM_RESOLVED_LEGS
        ),
        resolved_legs=resolved_legs,
        recommended_sport=best_sport,
        recommended_prop_site=best_site,
        recommended_market=best_market,
        recommended_minimum_edge=(
            recommended_edge
        ),
        recommended_minimum_confidence=(
            recommended_confidence
        ),
        recommended_leg_count=(
            recommended_leg_count
        ),
        warnings=warnings,
    )
