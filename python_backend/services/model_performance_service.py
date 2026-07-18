"""Operational and segmented model-performance reporting."""

from __future__ import annotations

from database.postgres import database_is_configured, get_database_pool
from services.pipeline_run_service import recent_pipeline_runs


def _segment(row: tuple[object, ...]) -> dict[str, object]:
    count, hits, brier, roi, sport, market, confidence = row
    return {"sampleSize": count, "hits": hits, "accuracy": round(float(hits or 0) / count, 4) if count else None,
            "brierScore": round(float(brier), 6) if brier is not None else None,
            "simulatedRoi": round(float(roi), 4) if roi is not None else None,
            "sport": sport, "market": market, "confidenceTier": confidence}


def model_performance(model_version: str = "intelligence-v1") -> dict[str, object]:
    if not database_is_configured():
        return {"modelVersion": model_version, "sampleSize": 0, "segments": []}
    base = """from prediction_snapshots where model_version=%s and hit is not null
              and created_at < event_time - interval '5 minutes'"""
    profit = """case when hit then
      case when nullif(inputs->>'entryOdds','')::double precision > 0
        then nullif(inputs->>'entryOdds','')::double precision/100
        else 100/abs(nullif(inputs->>'entryOdds','')::double precision) end else -1 end"""
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(f"""select count(*),count(*) filter(where hit),
            avg(power(hit_probability-case when hit then 1 else 0 end,2)),
            avg({profit}) filter(where nullif(inputs->>'entryOdds','') is not null),
            null,null,null {base}""", (model_version,))
        overall = _segment(cursor.fetchone())
        cursor.execute(f"""select count(*),count(*) filter(where hit),
            avg(power(hit_probability-case when hit then 1 else 0 end,2)),
            avg({profit}) filter(where nullif(inputs->>'entryOdds','') is not null),
            sport,market,case when hit_probability>=.7 then 'HIGH'
              when hit_probability>=.6 then 'MEDIUM' else 'BASELINE' end {base}
            group by sport,market,7 order by count(*) desc""", (model_version,))
        segments = [_segment(row) for row in cursor.fetchall()]
    return {"modelVersion": model_version, **overall, "segments": segments,
            "minimumCalibrationSample": 100, "calibrated": overall["sampleSize"] >= 100,
            "clv": {"available": False,
                    "reason": "Prediction-level closing lines will populate as captured events approach start time."}}


def operations_summary() -> dict[str, object]:
    if not database_is_configured():
        return {"databaseConfigured": False, "runs": []}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select count(*) filter(where snapshot_date=current_date),
            count(*) filter(where graded_at is null),count(*) filter(where graded_at is not null),
            count(*) filter(where graded_at is not null and created_at < event_time-interval '5 minutes')
            from prediction_snapshots""")
        today, pending, graded, valid = cursor.fetchone()
    return {"databaseConfigured": True, "snapshotsToday": today,
            "pendingPredictions": pending, "gradedPredictions": graded,
            "validCalibrationResults": valid, "calibrationTarget": 100,
            "runs": recent_pipeline_runs()}
