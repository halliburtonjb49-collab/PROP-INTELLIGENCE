"""Historical feature engineering and auditable prediction tracking."""

from math import sqrt
from statistics import fmean, median
from uuid import UUID

from database.postgres import database_is_configured, get_database_pool
from models.intelligence import HistoricalFeatureRequest, PredictionSnapshotRequest


def historical_features(request: HistoricalFeatureRequest) -> dict[str, object]:
    values = request.values[-request.window:]
    mean = fmean(values)
    variance = sum((value - mean) ** 2 for value in values) / max(1, len(values) - 1)
    deviation = sqrt(variance)
    recent = values[-min(5, len(values)):]
    minutes = request.minutes[-request.window:]
    per_minute = [value / minute for value, minute in zip(values[-len(minutes):], minutes) if minute > 0]
    return {
        "sampleSize": len(values), "mean": round(mean, 4), "median": round(median(values), 4),
        "volatility": round(deviation, 4), "recentMean": round(fmean(recent), 4),
        "trend": round((fmean(recent) - mean) / max(deviation, 1e-9), 4),
        "perMinuteRate": round(fmean(per_minute), 5) if per_minute else None,
        "recommendedProjection": round(fmean(recent) * .65 + mean * .35, 4),
        "recommendedVolatility": round(max(deviation, .5), 4),
    }


def save_prediction(request: PredictionSnapshotRequest) -> dict[str, object]:
    if not database_is_configured():
        return {"persisted": False, "reason": "DATABASE_URL is not configured"}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""insert into prediction_snapshots
            (prop_id,player_id,sport,market,side,line,projection,hit_probability,model_version,inputs,event_time)
            values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s) returning id""",
            (request.prop_id, request.player_id, request.sport, request.market, request.side,
             request.line, request.projection, request.hit_probability, request.model_version,
             __import__("json").dumps(request.inputs), request.event_time))
        identifier = cursor.fetchone()[0]
        connection.commit()
    return {"persisted": True, "id": str(identifier)}


def grade_prediction(identifier: UUID, actual_value: float) -> dict[str, object]:
    if not database_is_configured():
        return {"persisted": False, "reason": "DATABASE_URL is not configured"}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""update prediction_snapshots set actual_value=%s,
            hit=case when side='OVER' then %s > line else %s < line end,
            graded_at=now() where id=%s returning hit,hit_probability""",
            (actual_value, actual_value, actual_value, identifier))
        row = cursor.fetchone()
        if row is None:
            return {"persisted": False, "reason": "Prediction not found"}
        connection.commit()
    hit, probability = row
    return {"persisted": True, "hit": hit,
            "brierScore": round((float(probability) - int(hit)) ** 2, 6)}


def calibration_summary(model_version: str = "intelligence-v1") -> dict[str, object]:
    if not database_is_configured():
        return {"sampleSize": 0, "brierScore": None, "buckets": [],
                "reason": "DATABASE_URL is not configured"}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select count(*), avg(power(hit_probability - case when hit then 1 else 0 end,2))
            from prediction_snapshots where model_version=%s and hit is not null""", (model_version,))
        count, brier = cursor.fetchone()
        cursor.execute("""select floor(hit_probability*10)/10 bucket,count(*),avg(hit::int),avg(hit_probability)
            from prediction_snapshots where model_version=%s and hit is not null
            group by bucket order by bucket""", (model_version,))
        buckets = [{"bucket": float(row[0]), "count": row[1], "actualHitRate": round(float(row[2]), 4),
                    "averageProbability": round(float(row[3]), 4)} for row in cursor.fetchall()]
    return {"sampleSize": count, "brierScore": round(float(brier), 6) if brier is not None else None,
            "buckets": buckets, "modelVersion": model_version}
