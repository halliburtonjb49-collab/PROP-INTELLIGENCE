"""Operational and segmented model-performance reporting."""

from __future__ import annotations

from database.postgres import database_is_configured, get_database_pool
from services.pipeline_run_service import recent_pipeline_runs
from services.baseline_projection_service import MODEL_VERSION


def _segment(row: tuple[object, ...]) -> dict[str, object]:
    count, hits, brier, log_loss, roi, sport, market, confidence = row
    return {"sampleSize": count, "hits": hits, "accuracy": round(float(hits or 0) / count, 4) if count else None,
            "brierScore": round(float(brier), 6) if brier is not None else None,
            "logLoss": round(float(log_loss), 6) if log_loss is not None else None,
            "simulatedRoi": round(float(roi), 4) if roi is not None else None,
            "sport": sport, "market": market, "confidenceTier": confidence}


def model_performance(model_version: str = MODEL_VERSION) -> dict[str, object]:
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
            avg(-(case when hit then ln(greatest(hit_probability,1e-15))
                else ln(greatest(1-hit_probability,1e-15)) end)),
            avg({profit}) filter(where nullif(inputs->>'entryOdds','') is not null),
            null,null,null {base}""", (model_version,))
        overall = _segment(cursor.fetchone())
        cursor.execute(f"""select count(*),count(*) filter(where hit),
            avg(power(hit_probability-case when hit then 1 else 0 end,2)),
            avg(-(case when hit then ln(greatest(hit_probability,1e-15))
                else ln(greatest(1-hit_probability,1e-15)) end)),
            avg({profit}) filter(where nullif(inputs->>'entryOdds','') is not null),
            sport,market,case when hit_probability>=.7 then 'HIGH'
              when hit_probability>=.6 then 'MEDIUM' else 'BASELINE' end {base}
            group by sport,market,7 order by count(*) desc""", (model_version,))
        segments = [_segment(row) for row in cursor.fetchall()]
        cursor.execute(f"""select count(*), count(*) filter(where hit),
            avg(power(hit_probability-case when hit then 1 else 0 end,2)),
            avg(hit_probability), sport,
            coalesce(nullif(inputs->>'category',''), market) category,
            coalesce(nullif(inputs->>'sourceProvider',''), 'unknown') provider,
            case when hit_probability>=.8 then '80-100%'
              when hit_probability>=.7 then '70-79%'
              when hit_probability>=.6 then '60-69%' else 'below-60%' end confidence_range
            {base}
            group by sport,6,7,8 order by count(*) desc""", (model_version,))
        quality_segments = [{
            "sampleSize": row[0],
            "hits": row[1],
            "accuracy": round(float(row[1] or 0) / row[0], 4) if row[0] else None,
            "brierScore": round(float(row[2]), 6) if row[2] is not None else None,
            "averageConfidence": round(float(row[3]), 4) if row[3] is not None else None,
            "sport": row[4],
            "category": row[5],
            "provider": row[6],
            "confidenceRange": row[7],
            "calibrationGap": (
                round(float(row[3]) - (float(row[1] or 0) / row[0]), 4)
                if row[0] and row[3] is not None else None
            ),
        } for row in cursor.fetchall()]
        cursor.execute(
            """select count(*),
                avg(case when (inputs->>'beatClosingLine')::boolean then 1 else 0 end),
                avg((inputs->>'lineClvPoints')::double precision)
            from prediction_snapshots
            where model_version=%s and inputs ? 'closingLine'""",
            (model_version,),
        )
        clv_count, beat_close_rate, average_points = cursor.fetchone()
    return {"modelVersion": model_version, **overall, "segments": segments,
            "qualitySegments": quality_segments,
            "minimumCalibrationSample": 100, "calibrated": overall["sampleSize"] >= 100,
            "clv": {
                "available": bool(clv_count),
                "sampleSize": int(clv_count or 0),
                "beatClosingLineRate": (
                    round(float(beat_close_rate), 4)
                    if beat_close_rate is not None else None
                ),
                "averageLineClvPoints": (
                    round(float(average_points), 4)
                    if average_points is not None else None
                ),
                "reason": (
                    None if clv_count else
                    "Closing lines populate during the final 20 minutes before start."
                ),
            }}


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
