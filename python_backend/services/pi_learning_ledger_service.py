"""Persistence and closing-line evidence for PI adaptive learning."""

from __future__ import annotations

import hashlib
import json
from typing import Iterable

from database.postgres import database_is_configured, get_database_pool


RECALCULATION_MODEL_VERSION = "pi-recalculation-v1"


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


def persist_recalculation_event(
    *, event_type: str, status: str, sport: object, market: object,
    segment_label: object, sample_size: int = 0, wins: int = 0,
    losses: int = 0, baseline_rate: float | None = None,
    observed_rate: float | None = None, lift: float | None = None,
    evidence: dict[str, object] | None = None, explanation: str = "",
    event_key: object = "",
) -> bool:
    if not database_is_configured():
        return False
    normalized_status = status if status in {"PROMOTED", "DEVELOPING", "REJECTED"} else "DEVELOPING"
    dimension = f"PI_RECALC_{str(event_type).strip().upper()}"
    payload = {
        "model": RECALCULATION_MODEL_VERSION, "dimension": dimension,
        "status": normalized_status, "sport": str(sport or "UNKNOWN").upper(),
        "market": str(market or "unknown").lower(), "segment": str(segment_label or ""),
        "sample": int(sample_size), "eventKey": str(event_key or ""),
        "evidence": evidence or {},
    }
    decision_key = hashlib.sha256(json.dumps(payload, sort_keys=True).encode("utf-8")).hexdigest()
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
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
                    decision_key, RECALCULATION_MODEL_VERSION, normalized_status,
                    payload["sport"], payload["market"], dimension,
                    str(segment_label or ""), int(sample_size), int(wins), int(losses),
                    baseline_rate, observed_rate, lift, json.dumps(evidence or {}),
                    explanation,
                ),
            )
            inserted = cursor.rowcount > 0
            connection.commit()
            return inserted
    except Exception:
        return False


def persist_recalculation_profiles(profiles: Iterable[object]) -> int:
    recorded = 0
    for profile in profiles:
        promoted = bool(getattr(profile, "promoted", False))
        reason = str(getattr(profile, "reason", ""))
        event_type = "ROLLBACK" if reason == "recent-performance-rollback" else "PROMOTION" if promoted else "SAMPLE"
        status = "REJECTED" if event_type == "ROLLBACK" else "PROMOTED" if promoted else "DEVELOPING"
        sample = int(getattr(profile, "sample_size", 0))
        accuracy = float(getattr(profile, "accuracy", 0.0))
        recorded += int(persist_recalculation_event(
            event_type=event_type, status=status,
            sport=getattr(profile, "sport", "UNKNOWN"),
            market=getattr(profile, "market", "unknown"),
            segment_label=f"{getattr(profile, 'sport', '')} {getattr(profile, 'market', '')}",
            sample_size=sample, wins=round(sample * accuracy),
            losses=sample - round(sample * accuracy),
            baseline_rate=getattr(profile, "entry_mae", None),
            observed_rate=getattr(profile, "recalculated_mae", None),
            lift=getattr(profile, "mae_improvement", None),
            evidence={
                "recentAccuracy": getattr(profile, "recent_accuracy", 0.0),
                "recentEntryMae": getattr(profile, "recent_entry_mae", None),
                "recentRecalculatedMae": getattr(profile, "recent_recalculated_mae", None),
                "rankingInfluence": getattr(profile, "ranking_influence", 0),
                "reason": reason,
            },
            explanation=reason, event_key=f"{sample}:{reason}",
        ))
    return recorded


def recent_recalculation_audit(limit: int = 50) -> list[dict[str, object]]:
    if not database_is_configured():
        return []
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                select status, sport, market, dimension, segment_label, sample_size,
                       baseline_rate, observed_rate, lift, evidence, explanation, created_at
                  from public.pi_learning_ledger
                 where model_version = %s and dimension like 'PI_RECALC_%%'
                 order by created_at desc
                 limit %s
                """,
                (RECALCULATION_MODEL_VERSION, max(1, min(limit, 100))),
            )
            rows = cursor.fetchall()
    except Exception:
        return []
    return [{
        "status": row[0], "sport": row[1], "market": row[2],
        "eventType": str(row[3]).removeprefix("PI_RECALC_"),
        "segment": row[4], "sampleSize": row[5], "entryMae": row[6],
        "recalculatedMae": row[7], "maeImprovement": row[8],
        "evidence": row[9] or {}, "explanation": row[10],
        "createdAt": row[11].isoformat() if row[11] else None,
    } for row in rows]
