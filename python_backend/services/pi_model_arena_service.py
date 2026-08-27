"""Owner-only, chronological model comparison with guarded promotion evidence."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from math import fsum

from database.postgres import database_is_configured, get_database_pool


MINIMUM_PROMOTION_SAMPLE = 200
MINIMUM_OVERLAP = 100


def _number(value: object) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _metrics(rows: list[dict[str, object]]) -> dict[str, object]:
    decisions = [row for row in rows if row["hit"] is not None]
    projections = [
        (float(row["actual"]), float(row["projection"]))
        for row in rows
        if row["actual"] is not None and row["projection"] is not None
    ]
    probabilities = [
        (float(row["probability"]), 1.0 if row["hit"] else 0.0)
        for row in decisions
        if row["probability"] is not None
    ]
    clv = [float(row["clv"]) for row in rows if row["clv"] is not None]
    accuracy = sum(bool(row["hit"]) for row in decisions) / len(decisions) if decisions else None
    average_probability = (
        fsum(probability for probability, _ in probabilities) / len(probabilities)
        if probabilities else None
    )
    return {
        "sampleSize": len(decisions),
        "accuracy": round(accuracy, 6) if accuracy is not None else None,
        "projectionMae": (
            round(fsum(abs(actual - projection) for actual, projection in projections) / len(projections), 6)
            if projections else None
        ),
        "brierScore": (
            round(fsum((probability - result) ** 2 for probability, result in probabilities) / len(probabilities), 6)
            if probabilities else None
        ),
        "calibrationGap": (
            round(abs(average_probability - accuracy), 6)
            if average_probability is not None and accuracy is not None else None
        ),
        "clvSampleSize": len(clv),
        "averageClv": round(fsum(clv) / len(clv), 6) if clv else None,
        "positiveClvRate": round(sum(value > 0 for value in clv) / len(clv), 6) if clv else None,
    }


def _promotion(candidate: dict[str, object], production: dict[str, object], overlap: int) -> tuple[str, str]:
    if int(candidate["sampleSize"]) < MINIMUM_PROMOTION_SAMPLE:
        return "OBSERVING", f"Needs {MINIMUM_PROMOTION_SAMPLE - int(candidate['sampleSize'])} more settled results."
    if overlap < MINIMUM_OVERLAP:
        return "OBSERVING", f"Only {overlap} directly comparable props overlap production."
    required = ("projectionMae", "brierScore", "calibrationGap", "averageClv", "positiveClvRate")
    if any(candidate[key] is None or production[key] is None for key in required):
        return "OBSERVING", "Projection, probability, or closing-line evidence is incomplete."
    passed = (
        float(candidate["projectionMae"]) < float(production["projectionMae"])
        and float(candidate["brierScore"]) < float(production["brierScore"])
        and float(candidate["calibrationGap"]) <= float(production["calibrationGap"])
        and float(candidate["averageClv"]) >= float(production["averageClv"])
        and float(candidate["positiveClvRate"]) >= max(.55, float(production["positiveClvRate"]))
    )
    if passed:
        return "ELIGIBLE", "Beat production across error, calibration, and closing-line guardrails."
    return "REJECTED", "Did not beat every production promotion guardrail."


def pi_model_arena_report(production_model: str, days: int = 60) -> dict[str, object]:
    if not database_is_configured():
        return {"available": False, "reason": "DATABASE_URL is not configured"}
    window_days = max(1, min(int(days), 365))
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select model_version, prop_id, sport, market, actual_value, projection,
                   hit_probability, hit, nullif(inputs->>'lineClvPoints',''), line
              from public.prediction_snapshots
             where hit is not null
               and graded_at >= now() - %s::interval
               and created_at < event_time - interval '5 minutes'
             order by event_time, created_at
            """,
            (f"{window_days} days",),
        )
        raw = cursor.fetchall()

    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    keys_by_model: dict[str, set[str]] = defaultdict(set)
    baseline_rows: list[dict[str, object]] = []
    for model, prop_id, sport, market, actual, projection, probability, hit, clv, line in raw:
        version = str(model or "UNKNOWN")
        key = f"{prop_id}|{sport}|{market}"
        row = {
            "actual": _number(actual), "projection": _number(projection),
            "probability": _number(probability), "hit": bool(hit), "clv": _number(clv),
        }
        grouped[version].append(row)
        keys_by_model[version].add(key)
        if version == production_model:
            baseline_rows.append({
                "actual": _number(actual), "projection": _number(line),
                "probability": .5, "hit": bool(hit), "clv": 0.0,
            })

    production_rows = grouped.get(production_model, [])
    production_metrics = _metrics(production_rows)
    production_keys = keys_by_model.get(production_model, set())
    competitors: list[dict[str, object]] = []
    for version, rows in grouped.items():
        metrics = _metrics(rows)
        overlap = len(production_keys.intersection(keys_by_model[version]))
        if version == production_model:
            status, reason = "PRODUCTION", "Current production reference model."
        else:
            status, reason = _promotion(metrics, production_metrics, overlap)
        competitors.append({
            "modelVersion": version, "status": status, "reason": reason,
            "overlapWithProduction": overlap, **metrics,
        })
    if baseline_rows:
        competitors.append({
            "modelVersion": "MARKET-LINE-BASELINE", "status": "BASELINE",
            "reason": "Neutral 50% probability and sportsbook line projection benchmark.",
            "overlapWithProduction": len(baseline_rows), **_metrics(baseline_rows),
        })
    order = {"PRODUCTION": 0, "ELIGIBLE": 1, "OBSERVING": 2, "REJECTED": 3, "BASELINE": 4}
    competitors.sort(key=lambda row: (order.get(str(row["status"]), 9), -int(row["sampleSize"])))
    return {
        "available": bool(production_rows), "productionModel": production_model,
        "windowDays": window_days, "minimumPromotionSample": MINIMUM_PROMOTION_SAMPLE,
        "minimumOverlap": MINIMUM_OVERLAP, "competitors": competitors,
        "eligibleChallengers": sum(row["status"] == "ELIGIBLE" for row in competitors),
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "reason": None if production_rows else "No settled production snapshots are available.",
    }
