"""Persistence and closing-line evidence for PI adaptive learning."""

from __future__ import annotations

import hashlib
import json

from database.postgres import database_is_configured, get_database_pool


def _decision_key(model_version: str, finding: dict[str, object]) -> str:
    evidence = {
        "model": model_version,
        "sport": finding.get("sport"),
        "market": finding.get("market"),
        "dimension": finding.get("dimension"),
        "label": finding.get("label"),
        "status": finding.get("status"),
        "sample": finding.get("sampleSize"),
        "wins": finding.get("wins"),
        "losses": finding.get("losses"),
    }
    return hashlib.sha256(json.dumps(evidence, sort_keys=True).encode("utf-8")).hexdigest()


def persist_learning_decisions(report: dict[str, object]) -> dict[str, int]:
    if not database_is_configured() or report.get("available") is not True:
        return {"recorded": 0, "existing": 0}
    model_version = str(report.get("modelVersion") or "")
    recorded = 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        for finding in report.get("findings") or []:
            if not isinstance(finding, dict):
                continue
            cursor.execute(
                """
                insert into public.pi_learning_ledger
                  (decision_key, model_version, status, sport, market, dimension,
                   segment_label, sample_size, wins, losses, baseline_rate,
                   observed_rate, lift, evidence, explanation)
                values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s)
                on conflict (decision_key) do nothing
                """,
                (
                    _decision_key(model_version, finding), model_version,
                    finding.get("status"), finding.get("sport"), finding.get("market"),
                    finding.get("dimension"), finding.get("label"),
                    int(finding.get("sampleSize") or 0), int(finding.get("wins") or 0),
                    int(finding.get("losses") or 0), finding.get("marketBaseline"),
                    finding.get("shrunkWinRate"), finding.get("lift"),
                    json.dumps({
                        "confidenceInterval": finding.get("confidenceInterval"),
                        "rawWinRate": finding.get("rawWinRate"),
                        "direction": finding.get("direction"),
                    }),
                    finding.get("explanation") or "",
                ),
            )
            recorded += max(0, cursor.rowcount)
        connection.commit()
    return {"recorded": recorded, "existing": max(0, len(report.get("findings") or []) - recorded)}


def closing_line_learning_summary(model_version: str, days: int = 60) -> dict[str, object]:
    if not database_is_configured():
        return {"available": False, "reason": "DATABASE_URL is not configured"}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select sport, market,
                   count(*) filter (where inputs ? 'beatClosingLine') as measured,
                   count(*) filter (where (inputs->>'beatClosingLine')::boolean is true) as beat_close,
                   avg(nullif(inputs->>'lineClvPoints','')::double precision) as average_line_clv,
                   avg(nullif(inputs->>'oddsClvExpectedValuePercent','')::double precision) as average_odds_clv
              from public.prediction_snapshots
             where model_version = %s
               and created_at >= now() - %s::interval
             group by sport, market
            having count(*) filter (where inputs ? 'beatClosingLine') > 0
             order by count(*) filter (where inputs ? 'beatClosingLine') desc
            """,
            (model_version, f"{max(1, min(days, 365))} days"),
        )
        rows = cursor.fetchall()
    segments = [
        {
            "sport": row[0], "market": row[1], "measured": int(row[2] or 0),
            "beatClose": int(row[3] or 0),
            "beatCloseRate": round(int(row[3] or 0) / int(row[2] or 1), 4),
            "averageLineClv": round(float(row[4]), 4) if row[4] is not None else None,
            "averageOddsClvEv": round(float(row[5]), 4) if row[5] is not None else None,
        }
        for row in rows
    ]
    measured = sum(int(row["measured"]) for row in segments)
    beat = sum(int(row["beatClose"]) for row in segments)
    return {
        "available": bool(segments), "windowDays": days, "measured": measured,
        "beatClose": beat, "beatCloseRate": round(beat / measured, 4) if measured else None,
        "segments": segments[:50],
        "reason": None if segments else "Closing-line samples are still accumulating.",
    }
