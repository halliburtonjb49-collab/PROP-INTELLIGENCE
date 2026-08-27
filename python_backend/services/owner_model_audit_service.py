"""Owner-only prediction ledger and model audit summaries."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
import json
from typing import Iterable, Mapping

from database.postgres import database_is_configured, get_database_pool
from services.owner_command_center_service import command_center_window
from services.model_performance_service import QUARANTINE_SQL
from services.pi_tendency_service import pi_tendency_report

_MAX_ROWS = 10_000


def _utc(value: datetime | None = None) -> datetime:
    current = value or datetime.now(timezone.utc)
    return current.astimezone(timezone.utc) if current.tzinfo else current.replace(tzinfo=timezone.utc)


def _value(row: Mapping[str, object], key: str, default: object = None) -> object:
    value = row.get(key, default)
    return default if value is None else value


def _number(value: object) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _tier(probability: float | None) -> str:
    if probability is None:
        return "UNKNOWN"
    if probability >= .8:
        return "80-100%"
    if probability >= .7:
        return "70-79%"
    if probability >= .6:
        return "60-69%"
    return "BELOW 60%"


def _american_profit(hit: bool, odds: float | None) -> float | None:
    if odds is None or odds == 0:
        return None
    if not hit:
        return -1.0
    return odds / 100 if odds > 0 else 100 / abs(odds)


def _mapping(value: object) -> dict[str, object]:
    if isinstance(value, Mapping):
        return dict(value)
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            return dict(parsed) if isinstance(parsed, Mapping) else {}
        except (TypeError, ValueError):
            return {}
    return {}


def build_prediction_explanation(row: Mapping[str, object]) -> dict[str, object]:
    inputs = _mapping(row.get("inputs"))
    features = _mapping(row.get("featureSnapshot"))
    source_versions = _mapping(row.get("sourceVersions"))

    def evidence(*keys: str, default: object = None) -> object:
        for key in keys:
            value = inputs.get(key)
            if value not in (None, "", [], {}):
                return value
            value = features.get(key)
            if value not in (None, "", [], {}):
                return value
        return default

    def numeric(*keys: str) -> float | None:
        return _number(evidence(*keys))

    sections: list[dict[str, object]] = []
    warnings: list[str] = []
    projection = _number(row.get("projection"))
    line = _number(row.get("line"))
    edge = projection - line if projection is not None and line is not None else None
    sections.append({
        "key": "projection", "label": "Projection vs line",
        "value": f"{projection:.2f} vs {line:.2f}" if projection is not None and line is not None else "Not captured",
        "detail": f"Model difference {edge:+.2f}." if edge is not None else "Projection or line evidence is missing.",
        "status": "AVAILABLE" if edge is not None else "MISSING",
    })

    sample = numeric("projectionSampleSize")
    volatility = numeric("projectionVolatility")
    recent_detail = []
    if sample is not None:
        recent_detail.append(f"{int(sample)} verified historical games")
    if volatility is not None:
        recent_detail.append(f"volatility {volatility:.2f}")
    sections.append({
        "key": "recent_form", "label": "Recent form and sample",
        "value": " | ".join(recent_detail) if recent_detail else "Not captured",
        "detail": str(evidence("pickGradeExplanation", default="No historical-form explanation was stored.")),
        "status": "AVAILABLE" if recent_detail else "MISSING",
    })

    minutes = numeric("projectedMinutes")
    opportunity = numeric("projectedOpportunity")
    role = str(evidence("roleStatus", default="UNKNOWN"))
    role_change = str(evidence("roleChange", default="UNKNOWN"))
    opportunity_bits = []
    if minutes is not None:
        opportunity_bits.append(f"{minutes:.1f} projected minutes")
    if opportunity is not None:
        opportunity_bits.append(f"{opportunity:.1f} {evidence('opportunityUnit', default='opportunities')}")
    opportunity_bits.append(f"role {role}")
    sections.append({
        "key": "opportunity", "label": "Minutes, usage and role",
        "value": " | ".join(opportunity_bits),
        "detail": f"Role change: {role_change}; usage multiplier: {numeric('usageMultiplier') or 1:.2f}x.",
        "status": "AVAILABLE" if minutes is not None or opportunity is not None or role != "UNKNOWN" else "PARTIAL",
    })
    if minutes is None:
        warnings.append("Projected minutes were not captured for this prediction.")

    matchup = str(evidence("matchup", default="Unknown matchup"))
    pace = numeric("paceMultiplier")
    defense = numeric("opponentAllowanceByPosition")
    matchup_multiplier = numeric("matchupMultiplier")
    matchup_bits = [matchup]
    if pace is not None:
        matchup_bits.append(f"pace {pace:.2f}x")
    if matchup_multiplier is not None:
        matchup_bits.append(f"matchup {matchup_multiplier:.2f}x")
    if defense is not None:
        matchup_bits.append(f"opponent allowance {defense:.2f}")
    sections.append({
        "key": "matchup", "label": "Opponent and matchup",
        "value": " | ".join(matchup_bits),
        "detail": str(evidence("matchupContext", default=evidence("defensiveScheme", default="No detailed matchup narrative was stored."))),
        "status": "AVAILABLE" if len(matchup_bits) > 1 else "PARTIAL",
    })

    injury = str(evidence("injuryStatus", default="unknown"))
    lineup = str(evidence("lineupStatus", default="unknown"))
    availability = _mapping(evidence("pregameAvailability", default={}))
    sections.append({
        "key": "availability", "label": "Injury and lineup",
        "value": f"Injury: {injury} | Lineup: {lineup}",
        "detail": str(availability.get("summary") or availability.get("detail") or "No additional availability evidence was stored."),
        "status": "AVAILABLE" if injury.lower() != "unknown" or lineup.lower() != "unknown" else "MISSING",
    })
    if injury.lower() == "unknown":
        warnings.append("Injury status was not captured for this prediction.")
    if lineup.lower() == "unknown":
        warnings.append("Lineup status was not captured for this prediction.")

    rest = numeric("restDays")
    travel = numeric("travelMiles")
    timezone_change = numeric("timezoneChangeHours")
    fatigue = numeric("fatigueMultiplier")
    context_bits = []
    if rest is not None:
        context_bits.append(f"rest {rest:.0f} days")
    if travel is not None:
        context_bits.append(f"travel {travel:.0f} miles")
    if timezone_change is not None:
        context_bits.append(f"timezone change {timezone_change:+.0f}h")
    if fatigue is not None:
        context_bits.append(f"fatigue {fatigue:.2f}x")
    sections.append({
        "key": "schedule", "label": "Rest, travel and environment",
        "value": " | ".join(context_bits) if context_bits else "Not captured",
        "detail": "Only verified stored schedule context is shown.",
        "status": "AVAILABLE" if context_bits else "MISSING",
    })

    opening = numeric("openingLine")
    current = numeric("currentLine") or line
    closing = _number(row.get("closingLine"))
    line_bits = []
    if opening is not None:
        line_bits.append(f"open {opening:.2f}")
    if current is not None:
        line_bits.append(f"snapshot {current:.2f}")
    if closing is not None:
        line_bits.append(f"close {closing:.2f}")
    sections.append({
        "key": "line_movement", "label": "Line movement",
        "value": " -> ".join(line_bits) if line_bits else "Not captured",
        "detail": f"Closing-line value: {row.get('lineClvPoints') or '--'} points.",
        "status": "AVAILABLE" if len(line_bits) >= 2 else "PARTIAL",
    })
    if closing is None:
        warnings.append("Closing line was not captured.")

    model_probability = numeric("modelProbability") or _number(row.get("hitProbability"))
    market_probability = numeric("marketProbability")
    calibration_adjustment = numeric("calibrationAdjustment")
    probability_bits = []
    if model_probability is not None:
        probability_bits.append(f"model {model_probability * 100:.1f}%")
    if market_probability is not None:
        probability_bits.append(f"market {market_probability * 100:.1f}%")
    sections.append({
        "key": "probability", "label": "Probability and calibration",
        "value": " | ".join(probability_bits) if probability_bits else "Not captured",
        "detail": f"Method: {evidence('probabilityMethod', default='unknown')}; calibration adjustment: {(calibration_adjustment or 0) * 100:+.1f} pts.",
        "status": "AVAILABLE" if model_probability is not None else "MISSING",
    })

    missing = evidence("contextMissingFields", default=[])
    missing_fields = [str(value) for value in missing] if isinstance(missing, list) else []
    quality = numeric("contextDataQualityScore", "dataQualityScore")
    data_age = numeric("dataAgeSeconds")
    sections.append({
        "key": "data_quality", "label": "Data freshness and quality",
        "value": f"Quality {(quality * 100):.0f}%" if quality is not None else "Quality not scored",
        "detail": (
            f"Age {int(data_age)} sec; missing: {', '.join(missing_fields) or 'none reported'}."
            if data_age is not None else f"Missing: {', '.join(missing_fields) or 'none reported'}; age not captured."
        ),
        "status": "AVAILABLE" if quality is not None else "PARTIAL",
    })
    warnings.extend(f"Missing context: {field}." for field in missing_fields)

    research = _mapping(evidence("researchCapsule", default={}))
    summary = str(research.get("summary") or evidence("recommendationExplanation", default=""))
    return {
        "summary": summary or "PI used the stored projection, probability, and contextual evidence shown below.",
        "sections": sections,
        "warnings": list(dict.fromkeys(warnings)),
        "modelVersion": row.get("modelVersion"),
        "sourceVersions": source_versions,
        "capturedEvidence": sorted({*inputs.keys(), *features.keys()}),
    }

def summarize_model_audit(rows: Iterable[Mapping[str, object]]) -> dict[str, object]:
    predictions = list(rows)
    calibration: defaultdict[str, dict[str, float]] = defaultdict(
        lambda: {"sampleSize": 0, "hits": 0, "confidenceTotal": 0}
    )
    dimensions: dict[str, set[str]] = {
        "sports": set(), "markets": set(), "sides": set(), "modelVersions": set(),
    }
    hits = pushes = 0
    brier_total = 0.0
    brier_count = 0
    profits: list[float] = []
    side_totals: defaultdict[str, dict[str, int]] = defaultdict(lambda: {"sampleSize": 0, "hits": 0, "pushes": 0})
    normalized: list[dict[str, object]] = []
    for row in predictions:
        probability = _number(row.get("hitProbability"))
        actual = _number(row.get("actualValue"))
        line = _number(row.get("line"))
        is_push = actual is not None and line is not None and abs(actual - line) < 1e-9
        hit = bool(row.get("hit")) and not is_push
        side = str(_value(row, "side", "UNKNOWN")).upper()
        sport = str(_value(row, "sport", "UNKNOWN")).upper()
        market = str(_value(row, "market", "UNKNOWN"))
        model_version = str(_value(row, "modelVersion", "UNKNOWN"))
        confidence_tier = _tier(probability)
        if is_push:
            pushes += 1
        elif hit:
            hits += 1
        if probability is not None and not is_push:
            brier_total += (probability - (1.0 if hit else 0.0)) ** 2
            brier_count += 1
            bucket = calibration[confidence_tier]
            bucket["sampleSize"] += 1
            bucket["hits"] += 1 if hit else 0
            bucket["confidenceTotal"] += probability
        odds = _number(row.get("entryOdds"))
        profit = 0.0 if is_push else _american_profit(hit, odds)
        if profit is not None:
            profits.append(profit)
        side_totals[side]["sampleSize"] += 1
        side_totals[side]["hits"] += 1 if hit else 0
        side_totals[side]["pushes"] += 1 if is_push else 0
        dimensions["sports"].add(sport)
        dimensions["markets"].add(market)
        dimensions["sides"].add(side)
        dimensions["modelVersions"].add(model_version)
        normalized_row = {
            **row,
            "sport": sport,
            "side": side,
            "market": market,
            "modelVersion": model_version,
            "confidenceTier": confidence_tier,
            "push": is_push,
            "correct": None if is_push else hit,
            "profitUnits": round(profit, 4) if profit is not None else None,
        }
        normalized_row["explanation"] = build_prediction_explanation(normalized_row)
        for raw_evidence_key in ("inputs", "featureSnapshot", "sourceVersions"):
            normalized_row.pop(raw_evidence_key, None)
        normalized.append(normalized_row)

    decisions = len(predictions) - pushes
    calibration_rows = []
    for name in ("80-100%", "70-79%", "60-69%", "BELOW 60%", "UNKNOWN"):
        bucket = calibration.get(name)
        if not bucket or not bucket["sampleSize"]:
            continue
        sample = int(bucket["sampleSize"])
        accuracy = bucket["hits"] / sample
        average_confidence = bucket["confidenceTotal"] / sample
        calibration_rows.append({
            "tier": name, "sampleSize": sample, "hits": int(bucket["hits"]),
            "accuracy": round(accuracy, 4),
            "averageConfidence": round(average_confidence, 4),
            "calibrationGap": round(average_confidence - accuracy, 4),
        })
    side_rows = []
    for side, values in sorted(side_totals.items()):
        side_decisions = values["sampleSize"] - values["pushes"]
        side_rows.append({
            "side": side, **values,
            "accuracy": round(values["hits"] / side_decisions, 4) if side_decisions else None,
        })
    return {
        "summary": {
            "graded": len(predictions), "decisions": decisions, "hits": hits,
            "losses": max(0, decisions - hits), "pushes": pushes,
            "accuracy": round(hits / decisions, 4) if decisions else None,
            "brierScore": round(brier_total / brier_count, 6) if brier_count else None,
            "simulatedRoi": round(sum(profits) / len(profits), 4) if profits else None,
            "oddsSampleSize": len(profits),
        },
        "calibration": calibration_rows,
        "sidePerformance": side_rows,
        "dimensions": {key: sorted(values) for key, values in dimensions.items()},
        "predictions": normalized,
    }


def owner_model_audit_snapshot(
    window: str = "30d", *, start: str | None = None, end: str | None = None,
    now: datetime | None = None, limit: int = 500,
) -> dict[str, object]:
    current = _utc(now)
    range_start, range_end, range_label = command_center_window(
        window, now=current, start=start, end=end,
    )
    if not database_is_configured():
        return {
            "available": False,
            "reason": "Prediction ledger database is not configured.",
            "generatedAt": current.isoformat(),
            "window": {"key": window, "label": range_label,
                       "start": range_start.isoformat(), "end": range_end.isoformat()},
            **summarize_model_audit([]),
        }
    row_limit = max(1, min(int(limit), _MAX_ROWS))
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """select id::text, prop_id, coalesce(nullif(inputs->>'playerName',''),
                           nullif(inputs->>'player',''), player_id::text, 'Unknown player'),
                          sport, market, side, line, projection, actual_value,
                          hit_probability, hit, model_version, created_at, event_time,
                          graded_at, inputs->>'sourceProvider', inputs->>'entryOdds',
                          inputs->>'closingLine', inputs->>'lineClvPoints', inputs,
                          feature_snapshot.features,
                          feature_snapshot.source_versions
                   from public.prediction_snapshots
                   left join lateral (
                       select features, source_versions
                         from public.matchup_feature_snapshots
                        where prediction_snapshot_id = prediction_snapshots.id
                        limit 1
                   ) feature_snapshot on true
                   where hit is not null
                     and graded_at >= %s and graded_at < %s
                     and created_at < event_time - interval '5 minutes'""" + QUARANTINE_SQL + """
                   order by graded_at desc nulls last, created_at desc
                   limit %s""",
                (range_start, range_end, _MAX_ROWS + 1),
            )
            raw_rows = cursor.fetchall()
    except Exception as exc:
        return {
            "available": False, "reason": "Prediction ledger is temporarily unavailable.",
            "error": type(exc).__name__, "generatedAt": current.isoformat(),
            "window": {"key": window, "label": range_label,
                       "start": range_start.isoformat(), "end": range_end.isoformat()},
            **summarize_model_audit([]),
        }
    keys = (
        "id", "propId", "player", "sport", "market", "side", "line", "projection",
        "actualValue", "hitProbability", "hit", "modelVersion", "createdAt", "eventTime",
        "gradedAt", "provider", "entryOdds", "closingLine", "lineClvPoints",
        "inputs", "featureSnapshot", "sourceVersions",
    )
    calculation_truncated = len(raw_rows) > _MAX_ROWS
    rows = [dict(zip(keys, row)) for row in raw_rows[:_MAX_ROWS]]
    audit = summarize_model_audit(rows)
    predictions = list(audit["predictions"])
    audit["predictions"] = predictions[:row_limit]
    newest_model = next(
        (
            str(row.get("modelVersion"))
            for row in predictions
            if row.get("modelVersion") not in (None, "", "UNKNOWN")
        ),
        "baseline-v3",
    )
    try:
        learning = pi_tendency_report(newest_model)
    except Exception as exc:
        learning = {
            "available": False,
            "modelVersion": newest_model,
            "reason": f"PI learning scorecard is temporarily unavailable: {exc}",
        }
    return {
        "available": True, "generatedAt": current.isoformat(),
        "window": {"key": window, "label": range_label,
                   "start": range_start.isoformat(), "end": range_end.isoformat()},
        "truncated": calculation_truncated,
        "predictionListTruncated": len(predictions) > row_limit,
        "auditedRows": len(rows), "returned": len(audit["predictions"]),
        "learning": learning, **audit,
    }
