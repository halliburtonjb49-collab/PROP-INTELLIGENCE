"""Owner controls and quality analytics for MLB strikeout recommendations."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json

from database.postgres import database_is_configured, get_database_pool


CONTROL_KEY = "strikeout_quality_gate"
DEFAULT_CONTROLS: dict[str, object] = {
    "enabled": True,
    "maxLineupAgeMinutes": 240,
    "minOpposingLineupSize": 8,
    "requireConfirmedLineup": True,
    "requireTemperature": True,
    "requireUmpireBoost": True,
    "requireSplitSignal": True,
    "maxFallbackSignals": 0,
    "calibrationWindowDays": 45,
    "calibrationMinSample": 80,
    "driftWindowDays": 7,
    "driftMinSample": 40,
    "maxBrierDelta": 0.03,
    "maxAccuracyDelta": 0.07,
    "calibrationGapWarn": 0.03,
    "calibrationGapHard": 0.05,
}


@dataclass(frozen=True)
class StrikeoutGateResult:
    blocked: bool
    reason: str
    details: list[str]


_CACHE_TTL_SECONDS = 600
_cached_calibration_at: datetime | None = None
_cached_calibration: dict[str, object] | None = None

ALERT_OWNERS: dict[str, str] = {
    "stale_data": "data-platform",
    "calibration_drift": "model-ops",
    "calibration_gap_guardrail": "model-ops",
    "ingest_failure": "data-platform",
    "deploy_failure": "release-engineering",
    "grading_mismatch": "grading-ops",
    "cross_book_validation": "model-ops",
}


def _safe_int(value: object, default: int = 0) -> int:
    try:
        return int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default


def _safe_float(value: object, default: float = 0.0) -> float:
    try:
        return float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default


def _to_bool(value: object, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "y", "on"}:
            return True
        if normalized in {"false", "0", "no", "n", "off"}:
            return False
    return default


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def _coerce_controls(raw: dict[str, object] | None) -> dict[str, object]:
    merged = dict(DEFAULT_CONTROLS)
    if isinstance(raw, dict):
        merged.update(raw)
    merged["enabled"] = _to_bool(merged.get("enabled"), True)
    merged["maxLineupAgeMinutes"] = _safe_int(merged.get("maxLineupAgeMinutes"), 240)
    merged["minOpposingLineupSize"] = _safe_int(merged.get("minOpposingLineupSize"), 8)
    merged["requireConfirmedLineup"] = _to_bool(merged.get("requireConfirmedLineup"), True)
    merged["requireTemperature"] = _to_bool(merged.get("requireTemperature"), True)
    merged["requireUmpireBoost"] = _to_bool(merged.get("requireUmpireBoost"), True)
    merged["requireSplitSignal"] = _to_bool(merged.get("requireSplitSignal"), True)
    merged["maxFallbackSignals"] = _safe_int(merged.get("maxFallbackSignals"), 0)
    merged["calibrationWindowDays"] = _safe_int(merged.get("calibrationWindowDays"), 45)
    merged["calibrationMinSample"] = _safe_int(merged.get("calibrationMinSample"), 80)
    merged["driftWindowDays"] = _safe_int(merged.get("driftWindowDays"), 7)
    merged["driftMinSample"] = _safe_int(merged.get("driftMinSample"), 40)
    merged["maxBrierDelta"] = _safe_float(merged.get("maxBrierDelta"), 0.03)
    merged["maxAccuracyDelta"] = _safe_float(merged.get("maxAccuracyDelta"), 0.07)
    merged["calibrationGapWarn"] = _safe_float(merged.get("calibrationGapWarn"), 0.03)
    merged["calibrationGapHard"] = _safe_float(merged.get("calibrationGapHard"), 0.05)

    merged["maxLineupAgeMinutes"] = max(30, min(720, _safe_int(merged["maxLineupAgeMinutes"], 240)))
    merged["minOpposingLineupSize"] = max(5, min(9, _safe_int(merged["minOpposingLineupSize"], 8)))
    merged["maxFallbackSignals"] = max(0, min(3, _safe_int(merged["maxFallbackSignals"], 0)))
    merged["calibrationWindowDays"] = max(14, min(120, _safe_int(merged["calibrationWindowDays"], 45)))
    merged["calibrationMinSample"] = max(30, min(500, _safe_int(merged["calibrationMinSample"], 80)))
    merged["driftWindowDays"] = max(3, min(30, _safe_int(merged["driftWindowDays"], 7)))
    merged["driftMinSample"] = max(20, min(200, _safe_int(merged["driftMinSample"], 40)))
    merged["maxBrierDelta"] = round(_clamp(_safe_float(merged["maxBrierDelta"], 0.03), 0.005, 0.2), 4)
    merged["maxAccuracyDelta"] = round(_clamp(_safe_float(merged["maxAccuracyDelta"], 0.07), 0.01, 0.3), 4)
    merged["calibrationGapWarn"] = round(_clamp(_safe_float(merged["calibrationGapWarn"], 0.03), 0.01, 0.1), 4)
    hard_gap = round(_clamp(_safe_float(merged["calibrationGapHard"], 0.05), 0.02, 0.2), 4)
    merged["calibrationGapHard"] = max(hard_gap, _safe_float(merged["calibrationGapWarn"], 0.03) + 0.005)
    return merged


def _gap_guardrail_status(gap: float | None, warn_gap: float, hard_gap: float) -> str:
    if gap is None:
        return "unknown"
    abs_gap = abs(gap)
    if abs_gap > hard_gap:
        return "hard_breach"
    if abs_gap > warn_gap:
        return "warning"
    return "ok"


def _owner_for_alert(alert_type: str) -> str:
    return ALERT_OWNERS.get(alert_type, "model-ops")


def _ensure_controls_table() -> None:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """create table if not exists owner_runtime_controls (
                key text primary key,
                value jsonb not null,
                updated_at timestamptz not null default now()
            )"""
        )
        connection.commit()


def get_strikeout_release_controls() -> dict[str, object]:
    if not database_is_configured():
        return {
            "configured": False,
            "controls": _coerce_controls(None),
            "source": "defaults",
        }
    try:
        _ensure_controls_table()
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute("select value, updated_at from owner_runtime_controls where key=%s", (CONTROL_KEY,))
            row = cursor.fetchone()
        if row is None:
            return {
                "configured": True,
                "controls": _coerce_controls(None),
                "source": "defaults",
            }
        controls = _coerce_controls(row[0] if isinstance(row[0], dict) else None)
        return {
            "configured": True,
            "controls": controls,
            "source": "database",
            "updatedAt": row[1].isoformat() if row[1] is not None else None,
        }
    except Exception as exc:
        return {
            "configured": True,
            "controls": _coerce_controls(None),
            "source": "defaults",
            "error": type(exc).__name__,
        }


def update_strikeout_release_controls(patch: dict[str, object]) -> dict[str, object]:
    controls = _coerce_controls(patch)
    if not database_is_configured():
        return {
            "persisted": False,
            "reason": "DATABASE_URL is not configured",
            "controls": controls,
        }
    _ensure_controls_table()
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """insert into owner_runtime_controls(key, value, updated_at)
                values(%s, %s::jsonb, now())
                on conflict(key) do update set value=excluded.value, updated_at=excluded.updated_at
                returning updated_at""",
            (CONTROL_KEY, json.dumps(controls)),
        )
        row = cursor.fetchone()
        connection.commit()
    global _cached_calibration_at, _cached_calibration
    _cached_calibration_at = None
    _cached_calibration = None
    return {
        "persisted": True,
        "controls": controls,
        "updatedAt": row[0].isoformat() if row and row[0] is not None else None,
    }


def _parse_iso_datetime(value: object) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def evaluate_release_gate(prop: object, controls: dict[str, object] | None = None) -> StrikeoutGateResult:
    active_controls = _coerce_controls(controls)
    if not bool(active_controls["enabled"]):
        return StrikeoutGateResult(blocked=False, reason="", details=[])

    details: list[str] = []

    lineup_matchup = getattr(prop, "mlbProjectedLineupMatchup", None)
    if not isinstance(lineup_matchup, dict):
        return StrikeoutGateResult(True, "strikeout_lineup_missing", ["lineup payload missing"])

    opposing_lineup = list(lineup_matchup.get("opposingLineup") or [])
    if len(opposing_lineup) < _safe_int(active_controls["minOpposingLineupSize"], 8):
        return StrikeoutGateResult(True, "strikeout_lineup_coverage_low", [
            f"opposing lineup size {len(opposing_lineup)} below threshold",
        ])

    observed_at = _parse_iso_datetime(lineup_matchup.get("observedAt"))
    if observed_at is None:
        details.append("lineup observedAt missing")
    else:
        age_minutes = (datetime.now(timezone.utc) - observed_at).total_seconds() / 60.0
        if age_minutes > _safe_int(active_controls["maxLineupAgeMinutes"], 240):
            return StrikeoutGateResult(True, "strikeout_lineup_stale", [
                f"lineup age {int(age_minutes)} minutes exceeds threshold",
            ])

    if _to_bool(active_controls.get("requireConfirmedLineup"), True):
        confirmed = bool(lineup_matchup.get("confirmed"))
        if not confirmed:
            return StrikeoutGateResult(True, "strikeout_lineup_unconfirmed", ["lineup not confirmed"])

    if _to_bool(active_controls.get("requireTemperature"), True) and getattr(prop, "temperatureF", None) is None:
        return StrikeoutGateResult(True, "strikeout_weather_missing", ["temperature missing"])

    if _to_bool(active_controls.get("requireUmpireBoost"), True) and getattr(prop, "umpireKBoost", None) is None:
        return StrikeoutGateResult(True, "strikeout_umpire_missing", ["umpire tendency missing"])

    if _to_bool(active_controls.get("requireSplitSignal"), True):
        if getattr(prop, "lineupKPercent", None) is None and getattr(prop, "lineupCswAgainst", None) is None:
            return StrikeoutGateResult(True, "strikeout_lineup_split_missing", ["lineup split signals missing"])

    fallback_signals = [
        bool(getattr(prop, "strikeoutUsedFallbackPitcherRate", False)),
        bool(getattr(prop, "strikeoutUsedFallbackLineupRate", False)),
        bool(getattr(prop, "strikeoutUsedFallbackTbf", False)),
    ]
    fallback_count = sum(1 for flag in fallback_signals if flag)
    if fallback_count > _safe_int(active_controls["maxFallbackSignals"], 0):
        return StrikeoutGateResult(True, "strikeout_fallback_over_limit", [
            f"fallback signals {fallback_count} exceed threshold",
        ])

    return StrikeoutGateResult(False, "", details)


def build_explainability_snippet(prop: object) -> str:
    method = str(getattr(prop, "strikeoutModelMethod", "") or "log5_binomial")
    side = str(getattr(prop, "recommendedSide", "") or "N/A")
    line = getattr(prop, "line", None)
    fair_probability = getattr(prop, "fairProbability", None)
    pitcher_k = getattr(prop, "pitcherKPercent", None)
    lineup_k = getattr(prop, "lineupKPercent", None)
    tbf = getattr(prop, "strikeoutProjectedBattersFaced", None)
    temp = getattr(prop, "temperatureF", None)
    umpire = getattr(prop, "umpireKBoost", None)
    park = getattr(prop, "parkKFactor", None)
    fallback_count = sum(
        int(bool(value))
        for value in (
            getattr(prop, "strikeoutUsedFallbackPitcherRate", False),
            getattr(prop, "strikeoutUsedFallbackLineupRate", False),
            getattr(prop, "strikeoutUsedFallbackTbf", False),
        )
    )

    parts = [f"{method} {side}"]
    if line is not None:
        parts.append(f"line {float(line):g}")
    if fair_probability is not None:
        parts.append(f"p {float(fair_probability) * 100:.1f}%")
    if pitcher_k is not None and lineup_k is not None:
        parts.append(f"K {float(pitcher_k) * 100:.1f}% vs {float(lineup_k) * 100:.1f}%")
    if tbf is not None:
        parts.append(f"TBF {int(tbf)}")
    if temp is not None:
        parts.append(f"{float(temp):.0f}F")
    if umpire is not None:
        parts.append(f"ump {float(umpire) * 100:+.1f}%")
    if park is not None:
        parts.append(f"park {float(park):.2f}")
    parts.append(f"fallbacks {fallback_count}")
    return " | ".join(parts)


def build_explainability_payload(prop: object) -> dict[str, object]:
    action_status = (
        "blocked"
        if not bool(getattr(prop, "recommendationAvailable", False))
        else "actionable"
        if str(getattr(prop, "opportunityStatus", "") or "").strip().upper() == "READY"
        else "monitor"
    )
    fallback_count = sum(
        int(bool(value))
        for value in (
            getattr(prop, "strikeoutUsedFallbackPitcherRate", False),
            getattr(prop, "strikeoutUsedFallbackLineupRate", False),
            getattr(prop, "strikeoutUsedFallbackTbf", False),
        )
    )
    lineup_payload = getattr(prop, "mlbProjectedLineupMatchup", None)
    observed_at = (
        lineup_payload.get("observedAt")
        if isinstance(lineup_payload, dict)
        else None
    )
    reason = str(getattr(prop, "recommendationExplanation", "") or "").strip()
    if not reason:
        reason = str(getattr(prop, "pickGradeExplanation", "") or "").strip()
    if not reason:
        reasons = list(getattr(prop, "opportunityReasons", []) or [])
        reason = str(reasons[0]) if reasons else "quality gates applied"
    return {
        "formatVersion": "v1",
        "pick": {
            "side": str(getattr(prop, "recommendedSide", "N/A") or "N/A"),
            "line": getattr(prop, "line", None),
            "market": str(getattr(prop, "market", "") or ""),
        },
        "confidence": {
            "value": int(getattr(prop, "confidence", 0) or 0),
            "tier": str(getattr(prop, "tier", "No Pick") or "No Pick"),
        },
        "model": {
            "method": str(getattr(prop, "strikeoutModelMethod", "") or getattr(prop, "selectionMethod", "") or "calibrated model"),
            "calibrationAdjustment": float(getattr(prop, "probabilityCalibrationAdjustment", 0.0) or 0.0),
        },
        "topFactors": {
            "pitcherKPercent": getattr(prop, "pitcherKPercent", None),
            "lineupKPercent": getattr(prop, "lineupKPercent", None),
            "projectedBattersFaced": getattr(prop, "strikeoutProjectedBattersFaced", None),
            "umpireKBoost": getattr(prop, "umpireKBoost", None),
            "parkKFactor": getattr(prop, "parkKFactor", None),
        },
        "riskFlags": {
            "fallbackCount": fallback_count,
            "fallbackLimit": 3,
            "lineupObservedAt": observed_at,
            "lineupConfirmed": bool(lineup_payload.get("confirmed")) if isinstance(lineup_payload, dict) else False,
            "temperaturePresent": getattr(prop, "temperatureF", None) is not None,
            "umpirePresent": getattr(prop, "umpireKBoost", None) is not None,
            "splitPresent": (
                getattr(prop, "lineupKPercent", None) is not None
                or getattr(prop, "lineupCswAgainst", None) is not None
            ),
        },
        "recommendationReason": reason,
        "actionStatus": {
            "status": action_status,
            "reason": str(getattr(prop, "recommendationUnavailableReason", "") or ""),
        },
    }


def _calibration_query(window_days: int) -> tuple[list[tuple[object, ...]], int, float | None, float | None]:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select
                coalesce(nullif(side,''),'UNKNOWN') side,
                case
                    when hit_probability >= .75 then '75_100'
                    when hit_probability >= .65 then '65_74'
                    when hit_probability >= .55 then '55_64'
                    else '50_54'
                end confidence_bucket,
                count(*),
                avg(hit_probability),
                avg(case when hit then 1 else 0 end)
            from prediction_snapshots
            where hit is not null
              and created_at >= now() - (%s || ' days')::interval
              and upper(coalesce(sport,''))='MLB'
                            and lower(coalesce(market,'')) like '%%strikeout%%'
            group by 1,2""",
            (window_days,),
        )
        grouped = cursor.fetchall()
        cursor.execute(
            """select count(*),
                avg(hit_probability),
                avg(case when hit then 1 else 0 end)
            from prediction_snapshots
            where hit is not null
              and created_at >= now() - (%s || ' days')::interval
              and upper(coalesce(sport,''))='MLB'
                            and lower(coalesce(market,'')) like '%%strikeout%%'""",
            (window_days,),
        )
        count, avg_prob, avg_hit = cursor.fetchone()
    return grouped, int(count or 0), float(avg_prob) if avg_prob is not None else None, float(avg_hit) if avg_hit is not None else None


def strikeout_calibration_report(controls: dict[str, object] | None = None) -> dict[str, object]:
    active_controls = _coerce_controls(controls)
    if not database_is_configured():
        return {
            "available": False,
            "reason": "DATABASE_URL is not configured",
            "sampleSize": 0,
            "windowDays": active_controls["calibrationWindowDays"],
            "adjustments": [],
        }
    window_days = _safe_int(active_controls["calibrationWindowDays"], 45)
    grouped, sample_size, avg_prob, avg_hit = _calibration_query(window_days)
    overall_gap = None
    if avg_prob is not None and avg_hit is not None:
        overall_gap = round(avg_prob - avg_hit, 4)
    adjustments: list[dict[str, object]] = []
    for side, bucket, count, predicted, actual in grouped:
        predicted_value = float(predicted) if predicted is not None else None
        actual_value = float(actual) if actual is not None else None
        gap = (
            round(predicted_value - actual_value, 4)
            if predicted_value is not None and actual_value is not None
            else None
        )
        adjustment = (
            round(_clamp(-gap * 0.5, -0.08, 0.08), 4)
            if gap is not None else 0.0
        )
        adjustments.append({
            "side": str(side or "UNKNOWN").upper(),
            "bucket": str(bucket),
            "sampleSize": int(count or 0),
            "predicted": round(predicted_value, 4) if predicted_value is not None else None,
            "actual": round(actual_value, 4) if actual_value is not None else None,
            "gap": gap,
            "recommendedAdjustment": adjustment,
        })
    minimum = _safe_int(active_controls["calibrationMinSample"], 80)
    warn_gap = _safe_float(active_controls["calibrationGapWarn"], 0.03)
    hard_gap = _safe_float(active_controls["calibrationGapHard"], 0.05)
    guardrail = _gap_guardrail_status(overall_gap, warn_gap, hard_gap)
    return {
        "available": True,
        "sampleSize": sample_size,
        "minimumSample": minimum,
        "windowDays": window_days,
        "healthy": sample_size >= minimum and guardrail != "hard_breach",
        "guardrailStatus": guardrail,
        "calibrationGapWarn": warn_gap,
        "calibrationGapHard": hard_gap,
        "overallGap": overall_gap,
        "adjustments": adjustments,
    }


def _current_calibration() -> dict[str, object]:
    global _cached_calibration_at, _cached_calibration
    now = datetime.now(timezone.utc)
    if (
        _cached_calibration is not None
        and _cached_calibration_at is not None
        and (now - _cached_calibration_at).total_seconds() < _CACHE_TTL_SECONDS
    ):
        return _cached_calibration
    controls_response = get_strikeout_release_controls()
    controls = controls_response.get("controls") if isinstance(controls_response, dict) else None
    try:
        report = strikeout_calibration_report(controls if isinstance(controls, dict) else None)
    except Exception as exc:
        report = {
            "available": False,
            "reason": type(exc).__name__,
            "sampleSize": 0,
            "minimumSample": _coerce_controls(None)["calibrationMinSample"],
            "adjustments": [],
        }
    _cached_calibration = report
    _cached_calibration_at = now
    return report


def strikeout_probability_adjustment(side: str, fair_probability: float) -> float:
    calibration = _current_calibration()
    if not calibration.get("available"):
        return 0.0
    if int(calibration.get("sampleSize") or 0) < int(calibration.get("minimumSample") or 0):
        return 0.0
    bucket = (
        "75_100" if fair_probability >= 0.75
        else "65_74" if fair_probability >= 0.65
        else "55_64" if fair_probability >= 0.55
        else "50_54"
    )
    side_text = str(side or "UNKNOWN").upper()
    matches = [
        row for row in (calibration.get("adjustments") or [])
        if isinstance(row, dict)
        and str(row.get("bucket") or "") == bucket
        and str(row.get("side") or "").upper() == side_text
    ]
    if not matches:
        return 0.0
    return _safe_float(matches[0].get("recommendedAdjustment"), 0.0)


def _slice_rows(window_days: int) -> list[tuple[object, ...]]:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select
                coalesce(nullif(ps.inputs->>'sportsbook',''),'unknown') sportsbook,
                case
                    when ps.line < 5 then 'LT_5'
                    when ps.line <= 6.5 then '5_TO_6_5'
                    else 'GT_6_5'
                end line_range,
                case
                    when ps.line < 5 then 'LOW_K'
                    when ps.line <= 6.5 then 'MID_K'
                    else 'HIGH_K'
                end pitcher_tier,
                coalesce(nullif(upper(mfs.features->'mlbProjectedLineupMatchup'->>'throws'), ''), 'UNKNOWN') handedness,
                coalesce(nullif(upper(ps.side), ''), 'UNKNOWN') side,
                count(*) sample_size,
                avg(case when ps.hit then 1 else 0 end) accuracy,
                avg(ps.hit_probability) predicted,
                avg(power(ps.hit_probability - case when ps.hit then 1 else 0 end, 2)) brier
            from prediction_snapshots ps
            left join matchup_feature_snapshots mfs on mfs.prediction_snapshot_id = ps.id
            where ps.hit is not null
              and ps.created_at >= now() - (%s || ' days')::interval
              and upper(coalesce(ps.sport,''))='MLB'
                            and lower(coalesce(ps.market,'')) like '%%strikeout%%'
            group by 1,2,3,4,5
            order by sample_size desc""",
            (window_days,),
        )
        return cursor.fetchall()


def strikeout_backtest_monitoring(controls: dict[str, object] | None = None) -> dict[str, object]:
    active_controls = _coerce_controls(controls)
    if not database_is_configured():
        return {
            "available": False,
            "reason": "DATABASE_URL is not configured",
            "slices": [],
            "alerts": [],
        }
    window_days = max(14, _safe_int(active_controls["driftWindowDays"], 7) * 2)
    rows = _slice_rows(window_days)
    slices = [
        {
            "sportsbook": str(row[0]),
            "lineRange": str(row[1]),
            "pitcherTier": str(row[2]),
            "handedness": str(row[3]),
            "side": str(row[4]),
            "sampleSize": int(row[5] or 0),
            "accuracy": round(float(row[6]), 4) if row[6] is not None else None,
            "predicted": round(float(row[7]), 4) if row[7] is not None else None,
            "brier": round(float(row[8]), 4) if row[8] is not None else None,
            "gap": (
                round(float(row[7]) - float(row[6]), 4)
                if row[6] is not None and row[7] is not None else None
            ),
        }
        for row in rows
    ]
    alerts: list[dict[str, object]] = []
    min_sample = _safe_int(active_controls["driftMinSample"], 40)
    max_gap = _safe_float(active_controls["maxAccuracyDelta"], 0.07)
    for item in slices:
        sample_size = int(item["sampleSize"])
        gap = item.get("gap")
        if sample_size < min_sample or gap is None:
            continue
        if abs(float(gap)) > max_gap:
            severity = "warning" if abs(float(gap)) <= max_gap * 1.35 else "critical"
            alerts.append({
                "severity": severity,
                "type": "calibration_drift",
                "owner": _owner_for_alert("calibration_drift"),
                "sportsbook": item["sportsbook"],
                "lineRange": item["lineRange"],
                "pitcherTier": item["pitcherTier"],
                "handedness": item["handedness"],
                "side": item["side"],
                "sampleSize": sample_size,
                "gap": gap,
                "message": (
                    f"Accuracy drift {float(gap) * 100:.1f} pts on {item['sportsbook']} "
                    f"{item['lineRange']} {item['pitcherTier']} {item['handedness']} {item['side']}"
                ),
            })
    return {
        "available": True,
        "windowDays": window_days,
        "minimumSample": min_sample,
        "maxAccuracyDelta": max_gap,
        "slices": slices,
        "alerts": alerts,
        "healthy": not alerts,
    }


def _calibration_window_slice_report(
    window_days: int,
    minimum_sample: int,
    warn_gap: float,
    hard_gap: float,
) -> dict[str, object]:
    rows = _slice_rows(window_days)
    slices: list[dict[str, object]] = []
    alerts: list[dict[str, object]] = []
    total_sample = 0
    weighted_gap_sum = 0.0
    weighted_brier_sum = 0.0

    for row in rows:
        sportsbook = str(row[0])
        line_range = str(row[1])
        handedness = str(row[3])
        side = str(row[4])
        sample_size = int(row[5] or 0)
        actual = float(row[6]) if row[6] is not None else None
        predicted = float(row[7]) if row[7] is not None else None
        brier = float(row[8]) if row[8] is not None else None
        calibration_gap = (
            round(predicted - actual, 4)
            if predicted is not None and actual is not None
            else None
        )
        hit_rate_delta = (
            round(actual - predicted, 4)
            if predicted is not None and actual is not None
            else None
        )
        guardrail_status = _gap_guardrail_status(calibration_gap, warn_gap, hard_gap)

        item = {
            "sportsbook": sportsbook,
            "lineBand": line_range,
            "handedness": handedness,
            "side": side,
            "sampleSize": sample_size,
            "predicted": round(predicted, 4) if predicted is not None else None,
            "actual": round(actual, 4) if actual is not None else None,
            "calibrationGap": calibration_gap,
            "brier": round(brier, 4) if brier is not None else None,
            "hitRateDeltaVsPredicted": hit_rate_delta,
            "guardrailStatus": guardrail_status,
        }
        slices.append(item)

        if sample_size >= minimum_sample and guardrail_status in {"warning", "hard_breach"}:
            severity = "critical" if guardrail_status == "hard_breach" else "warning"
            alerts.append({
                "severity": severity,
                "type": "calibration_gap_guardrail",
                "owner": _owner_for_alert("calibration_gap_guardrail"),
                "windowDays": window_days,
                "sportsbook": sportsbook,
                "lineBand": line_range,
                "handedness": handedness,
                "side": side,
                "sampleSize": sample_size,
                "calibrationGap": calibration_gap,
                "message": (
                    f"Calibration gap {float(calibration_gap) * 100:+.1f} pts in {window_days}d "
                    f"for {sportsbook} {line_range} {handedness} {side}"
                ) if calibration_gap is not None else "Calibration gap unavailable",
            })

        if sample_size > 0 and calibration_gap is not None:
            total_sample += sample_size
            weighted_gap_sum += calibration_gap * sample_size
            if brier is not None:
                weighted_brier_sum += brier * sample_size

    overall_gap = round(weighted_gap_sum / total_sample, 4) if total_sample else None
    overall_brier = round(weighted_brier_sum / total_sample, 4) if total_sample else None
    return {
        "windowDays": window_days,
        "minimumSample": minimum_sample,
        "sampleSize": total_sample,
        "overallCalibrationGap": overall_gap,
        "overallBrier": overall_brier,
        "slices": slices,
        "alerts": alerts,
        "healthy": not any(alert.get("severity") == "critical" for alert in alerts),
    }


def strikeout_calibration_history_report(controls: dict[str, object] | None = None) -> dict[str, object]:
    active_controls = _coerce_controls(controls)
    if not database_is_configured():
        return {
            "available": False,
            "reason": "DATABASE_URL is not configured",
            "windows": [],
            "alerts": [],
        }

    minimum_sample = _safe_int(active_controls["driftMinSample"], 40)
    warn_gap = _safe_float(active_controls["calibrationGapWarn"], 0.03)
    hard_gap = _safe_float(active_controls["calibrationGapHard"], 0.05)
    windows = [
        _calibration_window_slice_report(7, minimum_sample, warn_gap, hard_gap),
        _calibration_window_slice_report(30, minimum_sample, warn_gap, hard_gap),
        _calibration_window_slice_report(90, minimum_sample, warn_gap, hard_gap),
    ]
    alerts = [
        alert
        for window in windows
        for alert in (window.get("alerts") or [])
        if isinstance(alert, dict)
    ]
    hard_breach_count = sum(1 for alert in alerts if alert.get("severity") == "critical")
    warning_count = sum(1 for alert in alerts if alert.get("severity") == "warning")

    return {
        "available": True,
        "fixedWindowsDays": [7, 30, 90],
        "guardrails": {
            "calibrationGapWarn": warn_gap,
            "calibrationGapHard": hard_gap,
            "units": "probability",
        },
        "minimumSample": minimum_sample,
        "windows": windows,
        "alerts": alerts,
        "healthy": hard_breach_count == 0,
        "hardBreaches": hard_breach_count,
        "warnings": warning_count,
    }


def _weekly_trend_rows(lookback_days: int = 90) -> list[tuple[object, ...]]:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select
                date_trunc('week', ps.created_at)::date week_start,
                coalesce(nullif(ps.inputs->>'sportsbook',''),'unknown') sportsbook,
                coalesce(nullif(ps.market,''),'unknown') market,
                count(*) sample_size,
                avg(ps.hit_probability) predicted,
                avg(case when ps.hit then 1 else 0 end) actual,
                avg(power(ps.hit_probability - case when ps.hit then 1 else 0 end, 2)) brier,
                avg(nullif(ps.inputs->>'lineClvPoints','')::double precision)
                    filter(where nullif(ps.inputs->>'lineClvPoints','') is not null) line_clv,
                avg(case
                    when nullif(ps.inputs->>'entryOdds','')::double precision > 0 and ps.hit then
                        nullif(ps.inputs->>'entryOdds','')::double precision/100
                    when nullif(ps.inputs->>'entryOdds','')::double precision <= 0 and ps.hit then
                        100/abs(nullif(ps.inputs->>'entryOdds','')::double precision)
                    else -1 end)
                    filter(where nullif(ps.inputs->>'entryOdds','') is not null) roi
            from prediction_snapshots ps
            where ps.hit is not null
              and ps.created_at >= now() - (%s || ' days')::interval
              and upper(coalesce(ps.sport,''))='MLB'
                            and lower(coalesce(ps.market,'')) like '%%strikeout%%'
            group by 1,2,3
            order by 1 desc, 4 desc""",
            (lookback_days,),
        )
        return cursor.fetchall()


def _regime_split_rows(lookback_days: int = 90) -> list[tuple[object, ...]]:
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """with base as (
                select
                    case
                        when (
                            coalesce((ps.inputs->>'strikeoutUsedFallbackPitcherRate')::boolean, false)::int +
                            coalesce((ps.inputs->>'strikeoutUsedFallbackLineupRate')::boolean, false)::int +
                            coalesce((ps.inputs->>'strikeoutUsedFallbackTbf')::boolean, false)::int
                        ) >= 2 then 'fallback_heavy'
                        when (
                            coalesce((ps.inputs->>'strikeoutUsedFallbackPitcherRate')::boolean, false)::int +
                            coalesce((ps.inputs->>'strikeoutUsedFallbackLineupRate')::boolean, false)::int +
                            coalesce((ps.inputs->>'strikeoutUsedFallbackTbf')::boolean, false)::int
                        ) = 0 then 'enriched_only'
                        else 'mixed'
                    end fallback_regime,
                    case
                        when ps.line < 5 then 'low_line'
                        when ps.line >= 6.5 then 'high_line'
                        else 'mid_line'
                    end line_regime,
                    case
                        when ps.event_time is null then 'unknown_timing'
                        when ps.created_at <= ps.event_time - interval '6 hours' then 'early_day'
                        when ps.created_at >= ps.event_time - interval '90 minutes' then 'close_to_game'
                        else 'mid_window'
                    end timing_regime,
                    ps.hit_probability,
                    ps.hit,
                    nullif(ps.inputs->>'lineClvPoints','')::double precision line_clv
                from prediction_snapshots ps
                where ps.hit is not null
                  and ps.created_at >= now() - (%s || ' days')::interval
                  and upper(coalesce(ps.sport,''))='MLB'
                                and lower(coalesce(ps.market,'')) like '%%strikeout%%'
            )
            select regime_type, regime_value,
                count(*) sample_size,
                avg(hit_probability) predicted,
                avg(case when hit then 1 else 0 end) actual,
                avg(power(hit_probability - case when hit then 1 else 0 end, 2)) brier,
                avg(line_clv)
            from (
                select 'fallback' regime_type, fallback_regime regime_value, * from base
                union all
                select 'line' regime_type, line_regime regime_value, * from base
                union all
                select 'timing' regime_type, timing_regime regime_value, * from base
            ) expanded
            group by 1,2
            order by 1,3 desc""",
            (lookback_days,),
        )
        return cursor.fetchall()


def _cross_book_validation(controls: dict[str, object]) -> dict[str, object]:
    min_sample = _safe_int(controls.get("driftMinSample"), 40)
    hard_gap = _safe_float(controls.get("calibrationGapHard"), 0.05)
    rows = _slice_rows(30)
    by_book: dict[str, dict[str, object]] = {}
    for row in rows:
        book = str(row[0])
        sample = int(row[5] or 0)
        actual = float(row[6]) if row[6] is not None else None
        predicted = float(row[7]) if row[7] is not None else None
        if sample <= 0 or actual is None or predicted is None:
            continue
        gap = predicted - actual
        state = by_book.setdefault(book, {"sampleSize": 0, "weightedGapSum": 0.0})
        state["sampleSize"] = int(state["sampleSize"]) + sample
        state["weightedGapSum"] = float(state["weightedGapSum"]) + (gap * sample)

    books: list[dict[str, object]] = []
    qualifying_books = 0
    for book, state in by_book.items():
        sample_size = int(state["sampleSize"])
        gap = float(state["weightedGapSum"]) / sample_size if sample_size > 0 else 0.0
        healthy = sample_size >= min_sample and abs(gap) <= hard_gap
        if healthy:
            qualifying_books += 1
        books.append({
            "sportsbook": book,
            "sampleSize": sample_size,
            "calibrationGap": round(gap, 4),
            "qualifies": healthy,
        })

    books.sort(key=lambda item: int(item.get("sampleSize") or 0), reverse=True)
    requires_books = 3
    reliability_ready = qualifying_books >= requires_books
    return {
        "windowDays": 30,
        "minimumBookSample": min_sample,
        "requiredQualifiedBooks": requires_books,
        "qualifiedBooks": qualifying_books,
        "reliabilityReady": reliability_ready,
        "books": books,
    }


def strikeout_weekly_trust_report(controls: dict[str, object] | None = None) -> dict[str, object]:
    active_controls = _coerce_controls(controls)
    if not database_is_configured():
        return {
            "available": False,
            "reason": "DATABASE_URL is not configured",
            "weekly": [],
            "regimeSplits": {},
            "alerts": [],
        }

    weekly_rows = _weekly_trend_rows(90)
    weekly = [
        {
            "weekStart": row[0].isoformat() if row[0] is not None else None,
            "sportsbook": str(row[1]),
            "market": str(row[2]),
            "sampleSize": int(row[3] or 0),
            "predicted": round(float(row[4]), 4) if row[4] is not None else None,
            "actual": round(float(row[5]), 4) if row[5] is not None else None,
            "calibrationGap": (
                round(float(row[4]) - float(row[5]), 4)
                if row[4] is not None and row[5] is not None else None
            ),
            "brier": round(float(row[6]), 4) if row[6] is not None else None,
            "clvTrend": round(float(row[7]), 4) if row[7] is not None else None,
            "roiTrend": round(float(row[8]), 4) if row[8] is not None else None,
        }
        for row in weekly_rows
    ]

    regime_rows = _regime_split_rows(90)
    regime_splits: dict[str, list[dict[str, object]]] = {}
    for row in regime_rows:
        regime_type = str(row[0])
        regime_splits.setdefault(regime_type, []).append({
            "regime": str(row[1]),
            "sampleSize": int(row[2] or 0),
            "predicted": round(float(row[3]), 4) if row[3] is not None else None,
            "actual": round(float(row[4]), 4) if row[4] is not None else None,
            "calibrationGap": (
                round(float(row[3]) - float(row[4]), 4)
                if row[3] is not None and row[4] is not None else None
            ),
            "brier": round(float(row[5]), 4) if row[5] is not None else None,
            "lineClv": round(float(row[6]), 4) if row[6] is not None else None,
        })

    cross_book = _cross_book_validation(active_controls)
    alerts: list[dict[str, object]] = []
    if not bool(cross_book.get("reliabilityReady")):
        alerts.append({
            "severity": "warning",
            "type": "cross_book_validation",
            "owner": _owner_for_alert("cross_book_validation"),
            "message": (
                "Cross-book validation is not yet met for reliability claims "
                f"({cross_book.get('qualifiedBooks', 0)}/{cross_book.get('requiredQualifiedBooks', 3)} books)."
            ),
        })

    return {
        "available": True,
        "lookbackDays": 90,
        "weekly": weekly,
        "regimeSplits": regime_splits,
        "crossBookValidation": cross_book,
        "alerts": alerts,
        "publishable": True,
    }


def strikeout_method_ab_report() -> dict[str, object]:
    if not database_is_configured():
        return {
            "available": False,
            "reason": "DATABASE_URL is not configured",
            "variants": [],
        }
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select
                case
                    when coalesce((inputs->>'strikeoutUsedFallbackPitcherRate')::boolean, false)
                      or coalesce((inputs->>'strikeoutUsedFallbackLineupRate')::boolean, false)
                      or coalesce((inputs->>'strikeoutUsedFallbackTbf')::boolean, false)
                    then 'fallback_variant'
                    else 'enriched_variant'
                end as variant,
                count(*) sample_size,
                avg(case when hit then 1 else 0 end) accuracy,
                avg(hit_probability) predicted,
                avg(power(hit_probability - case when hit then 1 else 0 end, 2)) brier,
                avg(case when nullif(inputs->>'entryOdds','')::double precision > 0 and hit then
                    nullif(inputs->>'entryOdds','')::double precision/100
                    when nullif(inputs->>'entryOdds','')::double precision <= 0 and hit then
                    100/abs(nullif(inputs->>'entryOdds','')::double precision)
                    else -1 end)
                    filter(where nullif(inputs->>'entryOdds','') is not null) roi
            from prediction_snapshots
            where hit is not null
              and upper(coalesce(sport,''))='MLB'
                            and lower(coalesce(market,'')) like '%%strikeout%%'
            group by 1
            order by sample_size desc"""
        )
        rows = cursor.fetchall()
    variants = [
        {
            "variant": str(row[0]),
            "sampleSize": int(row[1] or 0),
            "accuracy": round(float(row[2]), 4) if row[2] is not None else None,
            "predicted": round(float(row[3]), 4) if row[3] is not None else None,
            "brier": round(float(row[4]), 4) if row[4] is not None else None,
            "simulatedRoi": round(float(row[5]), 4) if row[5] is not None else None,
        }
        for row in rows
    ]
    return {
        "available": bool(variants),
        "variants": variants,
        "reason": None if variants else "No graded strikeout variants yet.",
    }


def strikeout_explainability_snippets(limit: int = 6) -> dict[str, object]:
    if not database_is_configured():
        return {
            "available": False,
            "reason": "DATABASE_URL is not configured",
            "items": [],
        }
    bounded_limit = max(1, min(limit, 25))
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select
                coalesce(inputs->>'playerName','Unknown') player,
                coalesce(side,'UNKNOWN') side,
                line,
                hit_probability,
                hit,
                coalesce(nullif(inputs->>'strikeoutExplainability',''),
                    concat(
                        coalesce(nullif(inputs->>'strikeoutModelMethod',''),'legacy'),
                        ' | p ',
                        round(hit_probability::numeric * 100, 1),
                            '%% | fallback ',
                        (coalesce((inputs->>'strikeoutUsedFallbackPitcherRate')::boolean, false)::int +
                         coalesce((inputs->>'strikeoutUsedFallbackLineupRate')::boolean, false)::int +
                         coalesce((inputs->>'strikeoutUsedFallbackTbf')::boolean, false)::int)::text
                    )
                ) as summary,
                created_at
            from prediction_snapshots
            where hit is not null
              and upper(coalesce(sport,''))='MLB'
                            and lower(coalesce(market,'')) like '%%strikeout%%'
            order by created_at desc
            limit %s""",
            (bounded_limit,),
        )
        rows = cursor.fetchall()
    items = [
        {
            "player": str(row[0]),
            "side": str(row[1]).upper(),
            "line": float(row[2]) if row[2] is not None else None,
            "probability": round(float(row[3]), 4) if row[3] is not None else None,
            "hit": bool(row[4]) if row[4] is not None else None,
            "summary": str(row[5]),
            "createdAt": row[6].isoformat() if row[6] is not None else None,
        }
        for row in rows
    ]
    return {
        "available": bool(items),
        "items": items,
        "reason": None if items else "No graded strikeout explainability snapshots yet.",
    }
