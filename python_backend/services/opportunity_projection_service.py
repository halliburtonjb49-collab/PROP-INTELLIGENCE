"""Auditable player-opportunity projections from pregame historical volume."""

from __future__ import annotations

from dataclasses import dataclass
from statistics import fmean, median, pstdev

from database.postgres import database_is_configured, get_database_pool


@dataclass(frozen=True)
class OpportunityProjection:
    projected_volume: float
    unit: str
    sample_size: int
    volatility: float
    multiplier: float
    role: str
    role_change: str
    confidence: float
    source: str


def project_basketball_minutes(values: list[float]) -> OpportunityProjection | None:
    ordered = [max(0.0, float(value)) for value in values if value is not None][-20:]
    if len(ordered) < 5:
        return None
    weighted = ordered[0]
    for value in ordered[1:]:
        weighted = .35 * value + .65 * weighted
    recent = fmean(ordered[-5:])
    center = median(ordered)
    projected = .50 * weighted + .30 * recent + .20 * center
    volatility = pstdev(ordered) if len(ordered) > 1 else 0.0
    long_mean = fmean(ordered)
    multiplier = max(.88, min(1.12, projected / long_mean)) if long_mean > 0 else 1.0
    recent_three = fmean(ordered[-3:])
    prior = ordered[-8:-3]
    prior_mean = fmean(prior) if prior else long_mean
    delta = recent_three - prior_mean
    role_change = "EXPANDED" if delta >= 4 else "REDUCED" if delta <= -4 else "STABLE"
    role = (
        "HIGH_MINUTES" if projected >= 30
        else "ROTATION" if projected >= 20
        else "LIMITED"
    )
    stability = max(0.0, 1 - volatility / max(8.0, projected))
    confidence = min(1.0, len(ordered) / 15) * .55 + stability * .45
    return OpportunityProjection(
        projected_volume=round(projected, 2),
        unit="MINUTES",
        sample_size=len(ordered),
        volatility=round(volatility, 2),
        multiplier=round(multiplier, 4),
        role=role,
        role_change=role_change,
        confidence=round(confidence, 3),
        source="historical-minutes-ewma-v1",
    )


def basketball_opportunities(player_names: list[str], sport: str) -> dict[str, OpportunityProjection]:
    if not player_names or not database_is_configured():
        return {}
    rows: dict[str, list[float]] = {}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select lower(player_name), minutes from (
                select player_name,minutes,game_date,updated_at,
                    row_number() over(partition by lower(player_name)
                        order by game_date desc,updated_at desc) recent_rank
                from historical_basketball_game_logs
                where sport=%s and lower(player_name)=any(%s) and minutes is not null
                    and game_date < current_date
            ) games where recent_rank<=20
            order by lower(player_name),game_date,updated_at""",
            (sport.upper(), [name.lower() for name in player_names]),
        )
        for name, minutes in cursor.fetchall():
            rows.setdefault(str(name), []).append(float(minutes))
    return {
        name: result
        for name, values in rows.items()
        if (result := project_basketball_minutes(values)) is not None
    }
