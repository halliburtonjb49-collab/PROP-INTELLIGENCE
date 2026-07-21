import json
from collections import defaultdict

from models.prop_builder_performance import (
    LegPerformanceBreakdown,
    PerformanceBreakdown,
    PerformanceTrendPoint,
    PropBuilderPerformanceResponse,
    RecentBuildPerformance,
)
from services.prop_builder_history_service import (
    _connect,
    initialize_prop_builder_history,
)
from services.market_normalizer import (
    normalize_market,
)

MARKET_DISPLAY_NAMES = {
    "points": "Points",
    "rebounds": "Rebounds",
    "assists": "Assists",
    "pra": "Points + Rebounds + Assists",
    "three_pointers_made": "Three-Pointers Made",
    "steals": "Steals",
    "blocks": "Blocks",
    "turnovers": "Turnovers",
    "strikeouts": "Strikeouts",
    "pitcher_strikeouts": "Strikeouts",
    "hits": "Hits",
    "home_runs": "Home Runs",
    "total_bases": "Total Bases",
    "rbi": "RBIs",
    "passing_yards": "Passing Yards",
    "rushing_yards": "Rushing Yards",
    "receiving_yards": "Receiving Yards",
    "receptions": "Receptions",
    "shots_on_goal": "Shots on Goal",
    "saves": "Saves",
}


def _market_display_name(
    value: str,
) -> str:
    normalized = normalize_market(value)
    if normalized in MARKET_DISPLAY_NAMES:
        return MARKET_DISPLAY_NAMES[normalized]
    return normalized.replace(
        "_",
        " ",
    ).title()


def _safe_rate(
    numerator: int,
    denominator: int,
) -> float:
    if denominator <= 0:
        return 0
    return round(
        (numerator / denominator) * 100,
        1,
    )


def _empty_breakdown() -> dict[str, int]:
    return {
        "total_builds": 0,
        "won_builds": 0,
        "lost_builds": 0,
        "pushed_builds": 0,
        "pending_builds": 0,
        "legs_won": 0,
        "legs_lost": 0,
        "legs_pushed": 0,
        "legs_pending": 0,
    }


def _add_build_to_breakdown(
    *,
    target: dict[str, int],
    status: str,
    legs_won: int,
    legs_lost: int,
    legs_pushed: int,
    legs_pending: int,
) -> None:
    target["total_builds"] += 1
    status_key = {
        "won": "won_builds",
        "lost": "lost_builds",
        "push": "pushed_builds",
        "pending": "pending_builds",
    }.get(
        status,
        "pending_builds",
    )
    target[status_key] += 1
    target["legs_won"] += legs_won
    target["legs_lost"] += legs_lost
    target["legs_pushed"] += legs_pushed
    target["legs_pending"] += legs_pending


def _to_breakdown(
    *,
    name: str,
    values: dict[str, int],
) -> PerformanceBreakdown:
    resolved_builds = values["won_builds"] + values["lost_builds"]
    resolved_legs = (
        values["legs_won"]
        + values["legs_lost"]
        + values["legs_pushed"]
    )
    return PerformanceBreakdown(
        name=name,
        total_builds=values["total_builds"],
        won_builds=values["won_builds"],
        lost_builds=values["lost_builds"],
        pushed_builds=values["pushed_builds"],
        pending_builds=values["pending_builds"],
        legs_won=values["legs_won"],
        legs_lost=values["legs_lost"],
        legs_pushed=values["legs_pushed"],
        legs_pending=values["legs_pending"],
        build_win_rate=_safe_rate(
            values["won_builds"],
            resolved_builds,
        ),
        leg_hit_rate=_safe_rate(
            values["legs_won"],
            resolved_legs,
        ),
    )


def _empty_leg_breakdown() -> dict[str, float]:
    return {
        "total_legs": 0,
        "legs_won": 0,
        "legs_lost": 0,
        "legs_pushed": 0,
        "legs_pending": 0,
        "edge_sum": 0.0,
        "confidence_sum": 0.0,
    }


def _normalize_text(value: object) -> str:
    return str(value).strip().lower()


def _leg_sport(leg: dict[str, object]) -> str:
    return str(
        leg.get(
            "sport",
            "Unknown",
        )
    )


def _leg_prop_site(leg: dict[str, object]) -> str:
    return str(
        leg.get(
            "prop_site",
            leg.get(
                "sportsbook",
                "Unknown",
            ),
        )
    )


def _leg_status(leg: dict[str, object]) -> str:
    raw_status = str(
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
    ).strip().lower()
    if raw_status in {"won", "win"}:
        return "won"
    if raw_status in {"lost", "loss"}:
        return "lost"
    if raw_status in {"push", "pushed"}:
        return "push"
    return "pending"


def _add_leg_to_breakdown(
    *,
    target: dict[str, float],
    status: str,
    edge: float,
    confidence: float,
) -> None:
    target["total_legs"] += 1
    if status == "won":
        target["legs_won"] += 1
    elif status == "lost":
        target["legs_lost"] += 1
    elif status == "push":
        target["legs_pushed"] += 1
    else:
        target["legs_pending"] += 1

    target["edge_sum"] += edge
    target["confidence_sum"] += confidence


def _to_leg_breakdown(
    *,
    name: str,
    values: dict[str, float],
) -> LegPerformanceBreakdown:
    total_legs = int(values["total_legs"])
    legs_won = int(values["legs_won"])
    legs_lost = int(values["legs_lost"])
    legs_pushed = int(values["legs_pushed"])
    legs_pending = int(values["legs_pending"])
    resolved_legs = legs_won + legs_lost + legs_pushed
    return LegPerformanceBreakdown(
        name=name,
        total_legs=total_legs,
        legs_won=legs_won,
        legs_lost=legs_lost,
        legs_pushed=legs_pushed,
        legs_pending=legs_pending,
        resolved_legs=resolved_legs,
        leg_hit_rate=_safe_rate(
            legs_won,
            resolved_legs,
        ),
        average_edge=(
            round(values["edge_sum"] / total_legs, 1)
            if total_legs
            else 0
        ),
        average_confidence=(
            round(values["confidence_sum"] / total_legs, 1)
            if total_legs
            else 0
        ),
    )


def get_prop_builder_performance(
    *,
    recent_limit: int = 10,
    days: int | None = None,
    sport: str | None = None,
    prop_site: str | None = None,
    market: str | None = None,
    player: str | None = None,
) -> PropBuilderPerformanceResponse:
    initialize_prop_builder_history()

    query = """
    SELECT *
    FROM prop_builder_history
    """
    params: list[object] = []
    if days is not None:
        query += """
        WHERE datetime(created_at) >= datetime(
            'now',
            ?
        )
        """
        params.append(f"-{days} days")
    query += """
    ORDER BY created_at DESC
    """

    with _connect() as connection:
        rows = connection.execute(query, params).fetchall()

    filtered_rows: list[tuple] = []
    normalized_sport = _normalize_text(sport) if sport else None
    normalized_site = _normalize_text(prop_site) if prop_site else None
    normalized_market = (
        normalize_market(market)
        if market
        else None
    )
    normalized_player = _normalize_text(player) if player else None
    if normalized_sport in {"", "all"}:
        normalized_sport = None
    if normalized_site in {"", "all"}:
        normalized_site = None
    if normalized_market in {"", "all"}:
        normalized_market = None
    if normalized_player in {"", "all"}:
        normalized_player = None
    for row in rows:
        legs = json.loads(row["legs_json"])
        matching_legs: list[dict[str, object]] = []
        for raw_leg in legs:
            if not isinstance(raw_leg, dict):
                continue
            leg = dict(raw_leg)
            leg_sport = _leg_sport(leg)
            leg_site = _leg_prop_site(leg)
            if (
                normalized_sport
                and normalized_sport != _normalize_text(leg_sport)
            ):
                continue
            if (
                normalized_site
                and normalized_site != _normalize_text(leg_site)
            ):
                continue
            leg_market = normalize_market(
                str(
                    leg.get("market", "")
                )
            )
            if (
                normalized_market
                and leg_market != normalized_market
            ):
                continue
            leg_player = _normalize_text(leg.get("player", "Unknown"))
            if normalized_player and leg_player != normalized_player:
                continue
            matching_legs.append(leg)

        if not matching_legs:
            continue

        filtered_rows.append((row, matching_legs))

    rows = filtered_rows

    total_builds = len(rows)
    won_builds = 0
    lost_builds = 0
    pushed_builds = 0
    pending_builds = 0

    legs_won = 0
    legs_lost = 0
    legs_pushed = 0
    legs_pending = 0

    edge_total = 0.0
    confidence_total = 0.0

    sport_data: dict[str, dict[str, int]] = defaultdict(_empty_breakdown)
    site_data: dict[str, dict[str, int]] = defaultdict(_empty_breakdown)
    leg_sport_data: dict[str, dict[str, float]] = defaultdict(_empty_leg_breakdown)
    leg_site_data: dict[str, dict[str, float]] = defaultdict(_empty_leg_breakdown)
    leg_market_data: dict[str, dict[str, float]] = defaultdict(_empty_leg_breakdown)
    leg_player_data: dict[str, dict[str, float]] = defaultdict(_empty_leg_breakdown)
    trend_data: dict[str, dict[str, int]] = defaultdict(
        lambda: {
            "total_builds": 0,
            "won_builds": 0,
            "lost_builds": 0,
            "pending_builds": 0,
            "legs_won": 0,
            "legs_lost": 0,
            "legs_pushed": 0,
        }
    )

    recent_builds: list[RecentBuildPerformance] = []

    for index, (row, matching_legs) in enumerate(rows):
        status = str(row["status"] or "pending").lower()

        matching_legs_won = 0
        matching_legs_lost = 0
        matching_legs_pushed = 0
        matching_legs_pending = 0
        for leg in matching_legs:
            leg_status = _leg_status(leg)
            if leg_status == "won":
                matching_legs_won += 1
            elif leg_status == "lost":
                matching_legs_lost += 1
            elif leg_status == "push":
                matching_legs_pushed += 1
            else:
                matching_legs_pending += 1

        created_at = str(row["created_at"])
        day_key = created_at[:10]
        day = trend_data[day_key]
        day["total_builds"] += 1
        day["legs_won"] += matching_legs_won
        day["legs_lost"] += matching_legs_lost
        day["legs_pushed"] += matching_legs_pushed
        if status == "won":
            day["won_builds"] += 1
        elif status == "lost":
            day["lost_builds"] += 1
        else:
            day["pending_builds"] += 1

        if status == "won":
            won_builds += 1
        elif status == "lost":
            lost_builds += 1
        elif status == "push":
            pushed_builds += 1
        else:
            pending_builds += 1

        legs_won += matching_legs_won
        legs_lost += matching_legs_lost
        legs_pushed += matching_legs_pushed
        legs_pending += matching_legs_pending

        average_edge = (
            sum(float(leg.get("edge", 0) or 0) for leg in matching_legs)
            / len(matching_legs)
        )
        average_confidence = (
            sum(float(leg.get("confidence", 0) or 0) for leg in matching_legs)
            / len(matching_legs)
        )
        edge_total += sum(float(leg.get("edge", 0) or 0) for leg in matching_legs)
        confidence_total += sum(
            float(leg.get("confidence", 0) or 0) for leg in matching_legs
        )

        sports = sorted(
            {
                _leg_sport(leg)
                for leg in matching_legs
            }
        )
        sites = sorted(
            {
                _leg_prop_site(leg)
                for leg in matching_legs
            }
        )

        for leg in matching_legs:
            leg_status = _leg_status(leg)
            leg_edge = float(leg.get("edge", 0) or 0)
            leg_confidence = float(
                leg.get("confidence", 0) or 0
            )
            raw_market = str(
                leg.get("market", "Unknown")
            ).strip()
            market_name = _market_display_name(
                raw_market,
            )
            _add_leg_to_breakdown(
                target=leg_sport_data[_leg_sport(leg)],
                status=leg_status,
                edge=leg_edge,
                confidence=leg_confidence,
            )
            _add_leg_to_breakdown(
                target=leg_site_data[_leg_prop_site(leg)],
                status=leg_status,
                edge=leg_edge,
                confidence=leg_confidence,
            )
            _add_leg_to_breakdown(
                target=leg_market_data[market_name],
                status=leg_status,
                edge=leg_edge,
                confidence=leg_confidence,
            )
            _add_leg_to_breakdown(
                target=leg_player_data[str(leg.get("player", "Unknown"))],
                status=leg_status,
                edge=leg_edge,
                confidence=leg_confidence,
            )

        for sport in set(str(value) for value in sports):
            _add_build_to_breakdown(
                target=sport_data[sport],
                status=status,
                legs_won=matching_legs_won,
                legs_lost=matching_legs_lost,
                legs_pushed=matching_legs_pushed,
                legs_pending=matching_legs_pending,
            )

        for site in set(str(value) for value in sites):
            _add_build_to_breakdown(
                target=site_data[site],
                status=status,
                legs_won=matching_legs_won,
                legs_lost=matching_legs_lost,
                legs_pushed=matching_legs_pushed,
                legs_pending=matching_legs_pending,
            )

        if index < recent_limit:
            recent_builds.append(
                RecentBuildPerformance(
                    id=int(row["id"]),
                    created_at=str(row["created_at"]),
                    status=status,
                    build_mode=str(row["build_mode"]),
                    sports=[str(value) for value in sports],
                    prop_sites=[str(value) for value in sites],
                    generated_legs=int(row["generated_legs"] or 0),
                    legs_won=matching_legs_won,
                    legs_lost=matching_legs_lost,
                    legs_pushed=matching_legs_pushed,
                    legs_pending=matching_legs_pending,
                    hit_rate=_safe_rate(
                        matching_legs_won,
                        (
                            matching_legs_won
                            + matching_legs_lost
                            + matching_legs_pushed
                        ),
                    ),
                    average_edge=average_edge,
                    average_confidence=average_confidence,
                )
            )

    resolved_builds = won_builds + lost_builds
    resolved_legs = legs_won + legs_lost + legs_pushed

    by_sport = [
        _to_breakdown(name=name, values=values)
        for name, values in sport_data.items()
    ]
    by_prop_site = [
        _to_breakdown(name=name, values=values)
        for name, values in site_data.items()
    ]

    by_sport.sort(
        key=lambda item: (
            item.leg_hit_rate,
            item.total_builds,
        ),
        reverse=True,
    )
    by_prop_site.sort(
        key=lambda item: (
            item.leg_hit_rate,
            item.total_builds,
        ),
        reverse=True,
    )

    leg_performance_by_sport = [
        _to_leg_breakdown(
            name=name,
            values=values,
        )
        for name, values in leg_sport_data.items()
    ]
    leg_performance_by_prop_site = [
        _to_leg_breakdown(
            name=name,
            values=values,
        )
        for name, values in leg_site_data.items()
    ]
    leg_performance_by_sport.sort(
        key=lambda item: (
            item.leg_hit_rate,
            item.resolved_legs,
        ),
        reverse=True,
    )
    leg_performance_by_prop_site.sort(
        key=lambda item: (
            item.leg_hit_rate,
            item.resolved_legs,
        ),
        reverse=True,
    )
    leg_performance_by_market = [
        _to_leg_breakdown(
            name=name,
            values=values,
        )
        for name, values in leg_market_data.items()
    ]
    leg_performance_by_market.sort(
        key=lambda item: (
            item.leg_hit_rate,
            item.resolved_legs,
            item.total_legs,
        ),
        reverse=True,
    )
    leg_performance_by_player = [
        _to_leg_breakdown(name=name, values=values)
        for name, values in leg_player_data.items()
    ]
    leg_performance_by_player.sort(
        key=lambda item: (item.leg_hit_rate, item.resolved_legs, item.total_legs),
        reverse=True,
    )

    trend: list[PerformanceTrendPoint] = []
    for date, values in sorted(trend_data.items()):
        resolved_legs = (
            values["legs_won"]
            + values["legs_lost"]
            + values["legs_pushed"]
        )
        trend.append(
            PerformanceTrendPoint(
                date=date,
                total_builds=values["total_builds"],
                won_builds=values["won_builds"],
                lost_builds=values["lost_builds"],
                pending_builds=values["pending_builds"],
                legs_won=values["legs_won"],
                legs_lost=values["legs_lost"],
                legs_pushed=values["legs_pushed"],
                leg_hit_rate=_safe_rate(
                    values["legs_won"],
                    resolved_legs,
                ),
            )
        )

    return PropBuilderPerformanceResponse(
        total_builds=total_builds,
        won_builds=won_builds,
        lost_builds=lost_builds,
        pushed_builds=pushed_builds,
        pending_builds=pending_builds,
        build_win_rate=_safe_rate(
            won_builds,
            resolved_builds,
        ),
        total_legs=legs_won + legs_lost + legs_pushed + legs_pending,
        legs_won=legs_won,
        legs_lost=legs_lost,
        legs_pushed=legs_pushed,
        legs_pending=legs_pending,
        leg_hit_rate=_safe_rate(
            legs_won,
            resolved_legs,
        ),
        average_edge=(
            round(edge_total / (legs_won + legs_lost + legs_pushed + legs_pending), 1)
            if (legs_won + legs_lost + legs_pushed + legs_pending)
            else 0
        ),
        average_confidence=(
            round(confidence_total / (legs_won + legs_lost + legs_pushed + legs_pending), 1)
            if (legs_won + legs_lost + legs_pushed + legs_pending)
            else 0
        ),
        by_sport=by_sport,
        by_prop_site=by_prop_site,
        leg_performance_by_sport=leg_performance_by_sport,
        leg_performance_by_prop_site=leg_performance_by_prop_site,
        leg_performance_by_market=leg_performance_by_market,
        leg_performance_by_player=leg_performance_by_player,
        recent_builds=recent_builds,
        trend=trend,
    )
