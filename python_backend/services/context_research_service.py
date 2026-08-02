"""Verified full-game Stat Slam and rest-split research."""

from __future__ import annotations

from datetime import date
from statistics import fmean, median

from database.postgres import database_is_configured, get_database_pool
from models.intelligence import ContextResearchRequest


def analyze_context_rows(
    rows: list[dict[str, object]], metrics: list[str], threshold: float
) -> dict[str, object]:
    ordered = sorted(rows, key=lambda row: row["game_date"])
    games: list[dict[str, object]] = []
    prior_date: date | None = None
    for row in ordered:
        game_date = row["game_date"]
        rest_days = None if prior_date is None else max(0, (game_date - prior_date).days - 1)
        values = [float(row.get(metric) or 0) for metric in metrics]
        total = sum(values)
        games.append({
            "date": game_date.isoformat(),
            "matchup": str(row.get("matchup") or ""),
            "value": round(total, 2),
            "hit": total >= threshold,
            "restDays": rest_days,
        })
        prior_date = game_date

    values = [float(game["value"]) for game in games]
    hits = sum(1 for game in games if game["hit"])
    rest_splits = []
    for label, predicate in (
        ("0 DAYS", lambda value: value == 0),
        ("1 DAY", lambda value: value == 1),
        ("2+ DAYS", lambda value: value is not None and value >= 2),
    ):
        subset = [game for game in games if predicate(game["restDays"])]
        split_values = [float(game["value"]) for game in subset]
        split_hits = sum(1 for game in subset if game["hit"])
        rest_splits.append({
            "label": label,
            "games": len(subset),
            "average": round(fmean(split_values), 2) if split_values else None,
            "hitRate": round(split_hits / len(subset), 4) if subset else None,
        })

    return {
        "sampleSize": len(games),
        "average": round(fmean(values), 2) if values else None,
        "median": round(median(values), 2) if values else None,
        "hits": hits,
        "hitRate": round(hits / len(games), 4) if games else None,
        "restSplits": rest_splits,
        "games": list(reversed(games)),
    }


def context_research(request: ContextResearchRequest) -> dict[str, object]:
    if not database_is_configured():
        return {
            "player": request.player,
            "sport": request.sport,
            "metrics": request.metrics,
            "threshold": request.threshold,
            "available": False,
            "reason": "Historical research database is not configured.",
        }
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select game_date,matchup,points,rebounds,assists,steals,blocks,threes
               from historical_basketball_game_logs
               where sport=%s and lower(player_name)=lower(%s) and game_date is not null
               order by game_date desc limit %s""",
            (request.sport, request.player.strip(), request.limit),
        )
        columns = [description.name for description in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    analysis = analyze_context_rows(rows, request.metrics, request.threshold)
    return {
        "player": request.player.strip(),
        "sport": request.sport,
        "metrics": request.metrics,
        "label": " + ".join(metric.upper() for metric in request.metrics),
        "threshold": request.threshold,
        "available": bool(rows),
        "source": "Verified completed full-game box scores",
        **analysis,
    }
