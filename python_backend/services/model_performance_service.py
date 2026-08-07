"""Operational and segmented model-performance reporting."""

from __future__ import annotations

from database.postgres import database_is_configured, get_database_pool
from services.pipeline_run_service import recent_pipeline_runs
from services.baseline_projection_service import MODEL_VERSION


MINIMUM_ACTION_SAMPLE = 30

QUARANTINED_MARKETS = {
    "basketball_nba": {"player_fantasy_points"},
    "basketball_wnba": {"player_fantasy_points"},
}

QUARANTINE_SQL = """ and not (
    lower(coalesce(sport,'')) in ('nba','wnba','basketball_nba','basketball_wnba')
    and lower(coalesce(market,'')) in ('player_fantasy_points','fantasy points','fantasypoints')
)"""

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


def _is_quarantined_market(sport: str | None, market: str | None) -> bool:
    if not sport or not market:
        return False
    normalized_sport = str(sport).strip().lower()
    normalized_market = str(market).strip().lower()
    if normalized_market in {"player_fantasy_points", "fantasy points", "fantasypoints"}:
        return normalized_sport in {"nba", "wnba", "basketball_nba", "basketball_wnba"}
    return False


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


def _summarize_roi_clv_segments(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    summarized: list[dict[str, object]] = []
    for row in rows:
        count = int(row.get("sampleSize") or 0)
        hits = int(row.get("hits") or 0)
        accuracy = round(float(hits) / count, 4) if count else None
        average_confidence = (
            round(float(row.get("averageConfidence", 0) or 0), 4)
            if row.get("averageConfidence") is not None
            else None
        )
        summarized.append({
            "sport": row.get("sport"),
            "market": row.get("market"),
            "side": str(row.get("side") or "UNKNOWN").upper(),
            "sampleSize": count,
            "hits": hits,
            "accuracy": accuracy,
            "averageConfidence": average_confidence,
            "simulatedRoi": round(float(row.get("simulatedRoi") or 0), 4),
            "beatClosingLineRate": round(float(row.get("beatClosingLineRate") or 0), 4),
            "averageLineClvPoints": round(float(row.get("averageLineClvPoints") or 0), 4),
            "averageOddsClvExpectedValuePercent": round(float(row.get("averageOddsClvExpectedValuePercent") or 0), 4),
            "positiveOddsClvRate": round(float(row.get("positiveOddsClvRate") or 0), 4),
            "oddsSampleSize": int(row.get("oddsSampleSize") or 0),
            **_audit_recommendation(count, accuracy, average_confidence),
        })
    return summarized


def _rolling_audit(cursor, model_version: str, base: str) -> dict[str, object]:
    dimensions = {
        "sport": "coalesce(nullif(sport,''),'unknown')",
        "propType": "coalesce(nullif(inputs->>'category',''),nullif(market,''),'unknown')",
        "confidenceTier": "case when hit_probability>=.7 then 'HIGH' when hit_probability>=.6 then 'MEDIUM' else 'BASELINE' end",
        "side": "coalesce(nullif(side,''),'unknown')",
        "pickGrade": "case when upper(coalesce(inputs->>'pickGrade','')) in ('A','B') "
        "then upper(inputs->>'pickGrade') else 'C' end",
        "opportunityRole": "coalesce(nullif(inputs->>'roleStatus',''),'unknown')",
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


def _dominant_model_version(cursor) -> str | None:
    """The model_version with the most graded, in-window predictions.

    Predictions aren't always snapshotted under the MODEL_VERSION constant -
    snapshot_live_predictions falls back to a prop's own
    projectionModelVersion (e.g. "provider-projection-v1") whenever one is
    present. Querying a single hardcoded version can silently show "0
    graded" while real graded data sits under a different version string.
    """
    cursor.execute("""select model_version, count(*)
        from prediction_snapshots
        where hit is not null and created_at < event_time - interval '5 minutes'
        group by model_version order by count(*) desc limit 1""")
    row = cursor.fetchone()
    return str(row[0]) if row and row[0] else None


def model_performance(model_version: str = MODEL_VERSION) -> dict[str, object]:
    if not database_is_configured():
        return {"modelVersion": model_version, "sampleSize": 0, "segments": []}
    requested_version = model_version
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select count(*) from prediction_snapshots
            where model_version=%s and hit is not null
            and created_at < event_time - interval '5 minutes'""" + QUARANTINE_SQL,
            (model_version,),
        )
        (requested_count,) = cursor.fetchone()
        if not requested_count:
            dominant = _dominant_model_version(cursor)
            if dominant:
                model_version = dominant
    base = """from prediction_snapshots where model_version=%s and hit is not null
              and created_at < event_time - interval '5 minutes'""" + QUARANTINE_SQL
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
                -- Only over lines that actually moved. A prop line often does
                -- not move at all, and beatClosingLine collapses "unchanged"
                -- into false, so averaging it across every row measured how
                -- often prop lines move rather than how well we priced them.
                avg(case when (inputs->>'beatClosingLine')::boolean then 1 else 0 end)
                    filter(where nullif(inputs->>'lineClvPoints','')::double precision <> 0),
                avg((inputs->>'lineClvPoints')::double precision),
                avg((inputs->>'oddsClvExpectedValuePercent')::double precision),
                avg(case when (inputs->>'oddsClvExpectedValuePercent')::double precision > 0 then 1 else 0 end)
                    filter(where inputs ? 'oddsClvExpectedValuePercent'),
                count(*) filter(where inputs ? 'oddsClvExpectedValuePercent'),
                count(*) filter(where nullif(inputs->>'lineClvPoints','')::double precision <> 0),
                count(*) filter(where nullif(inputs->>'lineClvPoints','')::double precision = 0)
            from prediction_snapshots
            where model_version=%s and inputs ? 'closingLine'""",
            (model_version,),
        )
        # Read before the next execute replaces the result set. This row used
        # to be fetched further down, after the per-segment query below had
        # already overwritten it and fetchall had drained the cursor, so the
        # fetch returned None and unpacking it raised -- taking the whole
        # performance view, and every page built on it, down with it.
        clv_totals = cursor.fetchone() or (0, None, None, None, None, 0, 0, 0)
        cursor.execute(f"""select sport,market,side,count(*),count(*) filter(where hit),
            avg(hit_probability),
            avg({profit}) filter(where nullif(inputs->>'entryOdds','') is not null),
            avg(case when (inputs->>'beatClosingLine')::boolean then 1 else 0 end)
                filter(where inputs ? 'beatClosingLine'),
            avg((inputs->>'lineClvPoints')::double precision)
                filter(where inputs ? 'lineClvPoints'),
            avg((inputs->>'oddsClvExpectedValuePercent')::double precision)
                filter(where inputs ? 'oddsClvExpectedValuePercent'),
            avg(case when (inputs->>'oddsClvExpectedValuePercent')::double precision > 0 then 1 else 0 end)
                filter(where inputs ? 'oddsClvExpectedValuePercent'),
            count(*) filter(where inputs ? 'oddsClvExpectedValuePercent')
            {base}
            group by sport,market,side order by count(*) desc""", (model_version,))
        roi_clv_segments = _summarize_roi_clv_segments([
            {
                "sport": row[0],
                "market": row[1],
                "side": row[2],
                "sampleSize": row[3],
                "hits": row[4],
                "averageConfidence": row[5],
                "simulatedRoi": row[6],
                "beatClosingLineRate": row[7],
                "averageLineClvPoints": row[8],
                "averageOddsClvExpectedValuePercent": row[9],
                "positiveOddsClvRate": row[10],
                "oddsSampleSize": row[11],
            }
            for row in cursor.fetchall()
        ])
        (clv_count, beat_close_rate, average_points, average_odds_ev,
         positive_odds_rate, odds_sample_size, moved_line_count,
         unchanged_line_count) = clv_totals
        rolling_audit = _rolling_audit(cursor, model_version, base)
    actionable = [segment for segment in side_segments if segment["actionable"]]
    return {"modelVersion": model_version, "requestedModelVersion": requested_version,
            **overall, "segments": segments,
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
            "roiClvSegments": roi_clv_segments,
            "minimumCalibrationSample": 100, "calibrated": overall["sampleSize"] >= 100,
            "clv": {
                "available": bool(clv_count),
                "sampleSize": int(clv_count or 0),
                # Read as: of the lines that moved, how often ours was the
                # better number. Unchanged lines are reported beside it rather
                # than counted as failures.
                "beatClosingLineRate": (
                    round(float(beat_close_rate), 4)
                    if beat_close_rate is not None else None
                ),
                "movedLineSampleSize": int(moved_line_count or 0),
                "unchangedLineCount": int(unchanged_line_count or 0),
                "averageLineClvPoints": (
                    round(float(average_points), 4)
                    if average_points is not None else None
                ),
                "oddsSampleSize": int(odds_sample_size or 0),
                "averageOddsClvExpectedValuePercent": (
                    round(float(average_odds_ev), 4)
                    if average_odds_ev is not None else None
                ),
                "positiveOddsClvRate": (
                    round(float(positive_odds_rate), 4)
                    if positive_odds_rate is not None else None
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
