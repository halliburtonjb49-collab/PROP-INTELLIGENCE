"""Operational and segmented model-performance reporting."""

from __future__ import annotations

from database.postgres import database_is_configured, get_database_pool
from services.pipeline_run_service import recent_pipeline_runs
from services.baseline_projection_service import MODEL_VERSION


MINIMUM_ACTION_SAMPLE = 30

ROLLING_WINDOWS = (
    ("7d", "LAST 7 DAYS", "7 days"),
    ("30d", "LAST 30 DAYS", "30 days"),
    ("all", "ALL TIME", None),
)


def _audit_recommendation(
    sample_size: int,
    accuracy: float | None,
    average_confidence: float | None,
) -> dict[str, object]:
    """Return a conservative action label for an evaluated model segment."""
    gap = (
        average_confidence - accuracy
        if accuracy is not None and average_confidence is not None
        else None
    )
    if sample_size < MINIMUM_ACTION_SAMPLE:
        status = "COLLECTING"
        reason = f"Needs {MINIMUM_ACTION_SAMPLE - sample_size} more graded picks"
    elif accuracy is not None and (accuracy < 0.50 or (gap is not None and gap > 0.08)):
        status = "RECALIBRATE"
        reason = "Verified results are below the release threshold"
    elif gap is not None and abs(gap) > 0.05:
        status = "MONITOR"
        reason = "Predicted confidence and observed accuracy differ by more than 5 points"
    else:
        status = "HEALTHY"
        reason = "Observed results are within the guarded calibration range"
    return {
        "status": status,
        "reason": reason,
        "calibrationGap": round(gap, 4) if gap is not None else None,
        "actionable": sample_size >= MINIMUM_ACTION_SAMPLE,
    }


def _segment(row: tuple[object, ...]) -> dict[str, object]:
    count, hits, brier, log_loss, roi, sport, market, confidence = row
    return {"sampleSize": count, "hits": hits, "accuracy": round(float(hits or 0) / count, 4) if count else None,
            "brierScore": round(float(brier), 6) if brier is not None else None,
            "logLoss": round(float(log_loss), 6) if log_loss is not None else None,
            "simulatedRoi": round(float(roi), 4) if roi is not None else None,
            "sport": sport, "market": market, "confidenceTier": confidence}


def _rolling_row(dimension: str, row: tuple[object, ...]) -> dict[str, object]:
    value, count, hits, confidence = row
    accuracy = float(hits or 0) / count if count else None
    average_confidence = float(confidence) if confidence is not None else None
    return {
        "dimension": dimension,
        "value": str(value or "UNKNOWN").upper(),
        "sampleSize": count,
        "hits": hits,
        "accuracy": round(accuracy, 4) if accuracy is not None else None,
        "averageConfidence": (
            round(average_confidence, 4)
            if average_confidence is not None else None
        ),
        **_audit_recommendation(count, accuracy, average_confidence),
    }


def _rolling_audit(cursor, model_version: str, base: str) -> dict[str, object]:
    dimensions = {
        "sport": "coalesce(nullif(sport,''),'unknown')",
        "propType": "coalesce(nullif(inputs->>'category',''),nullif(market,''),'unknown')",
        "confidenceTier": "case when hit_probability>=.7 then 'HIGH' when hit_probability>=.6 then 'MEDIUM' else 'BASELINE' end",
        "side": "coalesce(nullif(side,''),'unknown')",
    }
    windows = []
    for key, label, interval in ROLLING_WINDOWS:
        groups: dict[str, list[dict[str, object]]] = {}
        for dimension, expression in dimensions.items():
            window_clause = (
                f" and created_at >= now() - interval '{interval}'" if interval else ""
            )
            cursor.execute(
                f"""select {expression}, count(*), count(*) filter(where hit),
                    avg(hit_probability) {base}{window_clause}
                    group by 1 order by count(*) desc""",
                (model_version,),
            )
            groups[dimension] = [
                _rolling_row(dimension, row) for row in cursor.fetchall()
            ]
        all_rows = groups["side"]
        sample_size = sum(int(row["sampleSize"]) for row in all_rows)
        hits = sum(int(row["hits"] or 0) for row in all_rows)
        actionable = [row for rows in groups.values() for row in rows if row["actionable"]]
        windows.append({
            "key": key,
            "label": label,
            "sampleSize": sample_size,
            "hits": hits,
            "accuracy": round(hits / sample_size, 4) if sample_size else None,
            "healthy": sum(row["status"] == "HEALTHY" for row in actionable),
            "monitor": sum(row["status"] == "MONITOR" for row in actionable),
            "recalibrate": sum(row["status"] == "RECALIBRATE" for row in actionable),
            "collecting": sum(
                row["status"] == "COLLECTING" for rows in groups.values() for row in rows
            ),
            "dimensions": groups,
        })
    return {"windows": windows, "minimumActionSample": MINIMUM_ACTION_SAMPLE}


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
            group by sport,market,8 order by count(*) desc""", (model_version,))
        segments = [_segment(row) for row in cursor.fetchall()]
        cursor.execute(f"""select count(*), count(*) filter(where hit),
            avg(power(hit_probability-case when hit then 1 else 0 end,2)),
            avg(hit_probability), sport,
            coalesce(nullif(inputs->>'category',''), market) category,
            coalesce(nullif(inputs->>'sourceProvider',''), 'unknown') provider,
            case when hit_probability>=.8 then '80-100%%'
              when hit_probability>=.7 then '70-79%%'
              when hit_probability>=.6 then '60-69%%' else 'below-60%%' end confidence_range
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
        cursor.execute(f"""select count(*),count(*) filter(where hit),
            avg(hit_probability),side,sport,
            case when hit_probability>=.7 then 'HIGH'
              when hit_probability>=.6 then 'MEDIUM' else 'BASELINE' end confidence_tier
            {base}
            group by side,sport,6 order by count(*) desc""", (model_version,))
        side_segments = []
        for count, hits, confidence, side, sport, tier in cursor.fetchall():
            accuracy = float(hits or 0) / count if count else None
            average_confidence = float(confidence) if confidence is not None else None
            side_segments.append({
                "sampleSize": count,
                "hits": hits,
                "accuracy": round(accuracy, 4) if accuracy is not None else None,
                "averageConfidence": (
                    round(average_confidence, 4)
                    if average_confidence is not None else None
                ),
                "side": str(side or "UNKNOWN").upper(),
                "sport": sport,
                "confidenceTier": tier,
                **_audit_recommendation(count, accuracy, average_confidence),
            })
        cursor.execute(
            """select count(*),
                avg(case when (inputs->>'beatClosingLine')::boolean then 1 else 0 end),
                avg((inputs->>'lineClvPoints')::double precision)
            from prediction_snapshots
            where model_version=%s and inputs ? 'closingLine'""",
            (model_version,),
        )
        clv_count, beat_close_rate, average_points = cursor.fetchone()
        rolling_audit = _rolling_audit(cursor, model_version, base)
    actionable = [segment for segment in side_segments if segment["actionable"]]
    return {"modelVersion": model_version, **overall, "segments": segments,
            "qualitySegments": quality_segments,
            "sideSegments": side_segments,
            "auditSummary": {
                "minimumActionSample": MINIMUM_ACTION_SAMPLE,
                "healthy": sum(item["status"] == "HEALTHY" for item in actionable),
                "monitor": sum(item["status"] == "MONITOR" for item in actionable),
                "recalibrate": sum(item["status"] == "RECALIBRATE" for item in actionable),
                "collecting": sum(item["status"] == "COLLECTING" for item in side_segments),
            },
            "rollingAudit": rolling_audit,
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
