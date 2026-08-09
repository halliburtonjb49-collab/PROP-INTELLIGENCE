"""Explainable PI Trust Scores and compact research capsules for prop rows.

The score measures whether the underlying prop record is dependable enough to
research. It is deliberately separate from the model's recommendation strength:
a fresh, verified line can be highly trustworthy even when the model says PASS.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Mapping


def _value(row: object, *names: str, default: object = None) -> object:
    for name in names:
        if isinstance(row, Mapping) and name in row:
            return row[name]
        value = getattr(row, name, None)
        if value is not None:
            return value
    return default


def _number(value: object) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if result == result else None


def _timestamp(value: object) -> datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _factor(key: str, label: str, ratio: float, weight: int, detail: str) -> dict[str, object]:
    bounded = max(0.0, min(1.0, ratio))
    points = round(bounded * weight, 1)
    status = "STRONG" if bounded >= .8 else "FAIR" if bounded >= .55 else "WEAK"
    return {
        "key": key,
        "label": label,
        "score": points,
        "maxScore": weight,
        "status": status,
        "detail": detail,
    }


def build_prop_trust(row: object, *, now_utc: datetime | None = None) -> dict[str, object]:
    now = (now_utc or datetime.now(timezone.utc)).astimezone(timezone.utc)
    warnings: list[str] = []

    quality = _number(_value(row, "dataQualityScore", "data_quality_score"))
    if quality is None or quality <= 0:
        required = (
            _value(row, "player"),
            _value(row, "sport"),
            _value(row, "market"),
            _number(_value(row, "line")),
            _value(row, "sportsbook"),
            _value(row, "startTimeUtc", "start_time_utc"),
        )
        quality = sum(value not in (None, "") for value in required) / len(required)
    completeness_detail = f"{round(quality * 100)}% of required research fields are complete."
    factors = [_factor("completeness", "Feed completeness", quality, 25, completeness_detail)]
    if quality < .6:
        warnings.append("Important research fields are incomplete.")

    updated = _timestamp(_value(row, "lastUpdatedUtc", "last_updated_utc", "sourceUpdatedUtc"))
    age_seconds = _number(_value(row, "dataAgeSeconds", "data_age_seconds"))
    if age_seconds is None and updated is not None:
        age_seconds = max(0.0, (now - updated).total_seconds())
    age_minutes = None if age_seconds is None else max(0, round(age_seconds / 60))
    stale = bool(_value(row, "dataStale", "data_stale", default=False))
    if age_minutes is None:
        freshness_ratio, freshness_detail = .25, "The provider did not publish a usable refresh time."
        warnings.append("Refresh time is unknown.")
    elif age_minutes <= 5:
        freshness_ratio, freshness_detail = 1.0, f"Line refreshed {age_minutes} minutes ago."
    elif age_minutes <= 15:
        freshness_ratio, freshness_detail = .9, f"Line refreshed {age_minutes} minutes ago."
    elif age_minutes <= 45:
        freshness_ratio, freshness_detail = .75, f"Line refreshed {age_minutes} minutes ago."
    elif age_minutes <= 120:
        freshness_ratio, freshness_detail = .45, f"Line is {age_minutes} minutes old."
        warnings.append("Recheck the provider before using this line.")
    else:
        freshness_ratio, freshness_detail = .15, f"Line is {age_minutes} minutes old."
        warnings.append("This line may be stale.")
    if stale:
        freshness_ratio = min(freshness_ratio, .15)
    factors.append(_factor("freshness", "Last refresh", freshness_ratio, 20, freshness_detail))

    source_count = int(_number(_value(row, "marketBookCount", "market_book_count")) or 0)
    if source_count <= 0 and str(_value(row, "sourceProvider", "source_provider", default="") or "").strip():
        source_count = 1
    source_ratio = min(1.0, source_count / 4)
    factors.append(_factor(
        "sources",
        "Confirming sources",
        source_ratio,
        15,
        f"{source_count} independent market source{'s' if source_count != 1 else ''} confirm this prop.",
    ))
    if source_count < 2:
        warnings.append("Only one source currently confirms this line.")

    opening = _number(_value(row, "openingLine", "opening_line"))
    current = _number(_value(row, "currentLine", "current_line", "line"))
    if opening is None or current is None:
        stability_ratio, stability_detail = .45, "Opening-line history is unavailable."
    else:
        movement = abs(current - opening)
        relative = movement / max(abs(opening), 1.0)
        if movement == 0:
            stability_ratio = 1.0
        elif relative <= .02:
            stability_ratio = .95
        elif relative <= .05:
            stability_ratio = .8
        elif relative <= .10:
            stability_ratio = .6
        elif relative <= .20:
            stability_ratio = .35
        else:
            stability_ratio = .1
        stability_detail = f"Line moved {movement:g} from its {opening:g} opener."
        if stability_ratio < .55:
            warnings.append("The line has moved materially from its opener.")
    factors.append(_factor("stability", "Line stability", stability_ratio, 15, stability_detail))

    status = str(_value(row, "verificationStatus", "verification_status", default="") or "").upper()
    identity = _number(_value(row, "playerIdentityConfidence", "player_identity_confidence")) or 0
    selectable = bool(_value(row, "selectable", default=True))
    event_present = bool(str(_value(row, "eventId", "gameId", "matchup", default="") or "").strip())
    verification_ratio = (
        (.5 if status in {"VERIFIED", "CONFIRMED", ""} else .15)
        + (.2 * max(0.0, min(1.0, identity)))
        + (.15 if selectable else 0)
        + (.15 if event_present else 0)
    )
    factors.append(_factor(
        "verification",
        "Player and game verification",
        verification_ratio,
        15,
        "Player, market, and scheduled event are verified." if verification_ratio >= .8 else "One or more identity or event checks are incomplete.",
    ))
    if not selectable or verification_ratio < .55:
        warnings.append("Player or game verification needs review.")

    sample = max(
        int(_number(_value(row, "projectionSampleSize", "projection_sample_size")) or 0),
        int(_number(_value(row, "probabilityCalibrationSampleSize", "probability_calibration_sample_size")) or 0),
        int(_number(_value(row, "opportunitySampleSize", "opportunity_sample_size")) or 0),
    )
    sample_ratio = 1.0 if sample >= 2000 else .85 if sample >= 1000 else .65 if sample >= 500 else .4 if sample >= 250 else .1 if sample > 0 else 0.0
    factors.append(_factor(
        "sample",
        "Historical model sample",
        sample_ratio,
        10,
        f"Largest verified model sample contains {sample} observations." if sample else "No verified model sample is attached to this prop.",
    ))
    if sample < 100:
        warnings.append("Model sample size is limited or unavailable.")

    score = round(sum(float(factor["score"]) for factor in factors))
    band = "EXCELLENT" if score >= 85 else "STRONG" if score >= 70 else "CAUTION" if score >= 55 else "LIMITED"
    return {
        "score": score,
        "band": band,
        "researchReady": score >= 55 and selectable,
        "ageMinutes": age_minutes,
        "confirmingSources": source_count,
        "factors": factors,
        "warnings": warnings[:4],
    }


def build_research_capsule(row: object, trust: Mapping[str, object] | None = None) -> dict[str, object]:
    """Return concise, honest evidence statements; unavailable inputs stay absent."""

    items: list[dict[str, object]] = []
    line = _number(_value(row, "line", "currentLine", "current_line"))
    projection = _number(_value(row, "projection"))
    if projection is not None and line is not None:
        gap = projection - line
        items.append({
            "key": "projection",
            "label": "Projection vs line",
            "value": f"{projection:g} vs {line:g}",
            "detail": f"The model is {abs(gap):g} {'above' if gap >= 0 else 'below'} the current line.",
            "tone": "POSITIVE" if abs(gap) > 0 else "NEUTRAL",
        })

    hit_rate = _number(_value(row, "historicalHitRate", "historical_hit_rate"))
    if hit_rate is not None:
        items.append({
            "key": "history",
            "label": "Historical hit rate",
            "value": f"{hit_rate:.0f}%",
            "detail": "Verified historical results for this market and line context.",
            "tone": "POSITIVE" if hit_rate >= 55 else "CAUTION",
        })

    matchup = str(_value(row, "matchupContext", "matchup_context", default="") or "").strip()
    opponent_multiplier = _number(_value(row, "matchupMultiplier", "matchup_multiplier", "opponentDefenseMultiplier"))
    if matchup or opponent_multiplier is not None:
        items.append({
            "key": "matchup",
            "label": "Opponent matchup",
            "value": f"{opponent_multiplier:.2f}x" if opponent_multiplier is not None else "Available",
            "detail": matchup or "Opponent-adjusted projection context is included.",
            "tone": "NEUTRAL",
        })

    minutes = _number(_value(row, "projectedMinutes", "projected_minutes"))
    usage = _number(_value(row, "usageMultiplier", "usage_multiplier"))
    role_change = str(_value(row, "roleChange", "role_change", default="") or "").strip()
    if minutes is not None or usage is not None or role_change not in {"", "UNKNOWN"}:
        pieces = []
        if minutes is not None:
            pieces.append(f"{minutes:g} projected minutes")
        if usage is not None:
            pieces.append(f"{usage:.2f}x usage")
        if role_change not in {"", "UNKNOWN"}:
            pieces.append(role_change.replace("_", " ").lower())
        items.append({
            "key": "role",
            "label": "Minutes and usage",
            "value": " | ".join(pieces[:2]),
            "detail": "Current workload and role assumptions used by the projection.",
            "tone": "NEUTRAL",
        })

    injury = str(_value(row, "injuryStatus", "injury_status", default="unknown") or "unknown").strip()
    lineup = str(_value(row, "lineupStatus", "lineup_status", default="unknown") or "unknown").strip()
    if injury.lower() not in {"unknown", "healthy", "no injury reported"} or lineup.lower() not in {"unknown", "confirmed"}:
        items.append({
            "key": "availability",
            "label": "Injury and lineup",
            "value": f"{injury} | {lineup}",
            "detail": "Availability can materially change minutes, usage, and the projection.",
            "tone": "CAUTION",
        })

    opening = _number(_value(row, "openingLine", "opening_line"))
    current = _number(_value(row, "currentLine", "current_line", "line"))
    if opening is not None and current is not None:
        movement = current - opening
        items.append({
            "key": "movement",
            "label": "Line movement",
            "value": f"{opening:g} to {current:g}",
            "detail": "The line is unchanged." if movement == 0 else f"The market moved {abs(movement):g} {'up' if movement > 0 else 'down'} from open.",
            "tone": "NEUTRAL" if movement == 0 else "CAUTION",
        })

    trust_payload = dict(trust or build_prop_trust(row))
    warnings = [str(value) for value in trust_payload.get("warnings", [])]
    return {
        "summary": str(_value(row, "recommendationExplanation", "recommendation_explanation", default="") or "").strip(),
        "items": items[:7],
        "warnings": warnings,
        "trustScore": trust_payload.get("score", 0),
        "trustBand": trust_payload.get("band", "LIMITED"),
    }