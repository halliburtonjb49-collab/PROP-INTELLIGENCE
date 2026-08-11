"""Evidence-quality scoring for WNBA props.

The score is deliberately not a prediction. It answers whether minutes, role,
news, matchup and price evidence are complete enough to trust the model's
probability. A large statistical edge cannot override uncertain playing time.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class WnbaResearchAssessment:
    score: int
    band: str
    research_ready: bool
    minutes_certainty: int
    role_clarity: int
    factors: tuple[dict[str, object], ...]
    warnings: tuple[str, ...]


def _text(value: object) -> str:
    return str(value or "").strip().lower()


def _number(value: object) -> float | None:
    try:
        return None if value is None else float(value)
    except (TypeError, ValueError):
        return None


def _factor(
    key: str,
    label: str,
    score: int,
    maximum: int,
    detail: str,
) -> dict[str, object]:
    return {
        "key": key,
        "label": label,
        "score": score,
        "maxScore": maximum,
        "status": (
            "STRONG"
            if score >= maximum * .8
            else "FAIR"
            if score >= maximum * .55
            else "WEAK"
        ),
        "detail": detail,
    }


def _market_context(prop: object) -> tuple[int, str]:
    market = " ".join((
        _text(getattr(prop, "marketKey", "")),
        _text(getattr(prop, "market", "")),
        _text(getattr(prop, "category", "")),
    ))
    common = {
        "pace": getattr(prop, "paceMultiplier", None),
        "opponent": getattr(prop, "opponentDefenseMultiplier", None),
        "matchup": getattr(prop, "matchupMultiplier", None),
        "lineup_effect": getattr(prop, "wowyMultiplier", None),
    }
    if "assist" in market:
        checks = {
            **common,
            "opportunity": getattr(prop, "projectedOpportunity", None),
        }
        label = "assist chances, pace and opponent assist context"
    elif "rebound" in market:
        checks = {
            **common,
            "opportunity": getattr(prop, "projectedOpportunity", None),
        }
        label = "rebound opportunity, expected misses and matchup context"
    elif any(token in market for token in ("pra", "points rebounds assists")):
        checks = {
            **common,
            "usage": getattr(prop, "usageMultiplier", None),
            "opportunity": getattr(prop, "projectedOpportunity", None),
        }
        label = "minutes, usage and all-around opportunity context"
    else:
        checks = {
            **common,
            "usage": getattr(prop, "usageMultiplier", None),
        }
        label = "usage, shot environment, pace and opponent context"
    present = sum(value is not None for value in checks.values())
    score = round(15 * present / max(1, len(checks)))
    return score, f"{present}/{len(checks)} inputs available for {label}."


def assess_wnba_research(prop: object) -> WnbaResearchAssessment:
    if _text(getattr(prop, "sport", "")) != "wnba":
        return WnbaResearchAssessment(
            0, "NOT_APPLICABLE", False, 0, 0, (), ()
        )

    warnings: list[str] = []
    factors: list[dict[str, object]] = []

    minutes = _number(getattr(prop, "projectedOpportunity", None))
    if _text(getattr(prop, "opportunityUnit", "")) != "minutes":
        minutes = _number(getattr(prop, "projectedMinutes", None))
    minute_sample = int(
        getattr(prop, "opportunitySampleSize", 0)
        or getattr(prop, "projectionSampleSize", 0)
        or 0
    )
    minute_confidence = (
        _number(getattr(prop, "opportunityConfidence", None)) or 0.0
    )
    minute_volatility = _number(
        getattr(prop, "opportunityVolatility", None)
    )
    minute_score = 0
    if minutes is not None:
        minute_score += 30
    if minute_sample >= 12:
        minute_score += 25
    elif minute_sample >= 8:
        minute_score += 18
    elif minute_sample >= 5:
        minute_score += 10
    if minute_confidence >= .75:
        minute_score += 25
    elif minute_confidence >= .60:
        minute_score += 18
    elif minute_confidence > 0:
        minute_score += 10
    if minutes and minute_volatility is not None:
        volatility_ratio = minute_volatility / max(minutes, 1.0)
        minute_score += (
            20 if volatility_ratio <= .12
            else 12 if volatility_ratio <= .20
            else 4
        )
    minute_score = min(100, minute_score)
    if minutes is None:
        warnings.append("No verified minutes projection is attached.")
    elif minute_score < 60:
        warnings.append(
            "Recent minutes are too volatile or the sample is too small."
        )
    factors.append(_factor(
        "minutes",
        "Minutes certainty",
        round(minute_score * .35),
        35,
        (
            f"Projected minutes {minutes:g} from {minute_sample} games."
            if minutes is not None
            else "Projected minutes unavailable."
        ),
    ))

    role = _text(getattr(prop, "roleStatus", ""))
    role_change = _text(getattr(prop, "roleChange", ""))
    lineup = _text(getattr(prop, "lineupStatus", ""))
    lineup_confirmed = lineup in {
        "confirmed", "starter", "starting", "active"
    }
    role_score = 0
    if role not in {"", "unknown"}:
        role_score += 45
    if role_change == "stable":
        role_score += 35
    elif role_change in {"expanded", "reduced"}:
        role_score += 25 if lineup_confirmed else 10
    if lineup_confirmed:
        role_score += 20
    role_score = min(100, role_score)
    if role_score < 60:
        warnings.append("The current rotation role is not clear enough.")
    factors.append(_factor(
        "role",
        "Role clarity",
        round(role_score * .20),
        20,
        (
            f"Role {role or 'unknown'}; recent change "
            f"{role_change or 'unknown'}; lineup {lineup or 'unknown'}."
        ),
    ))

    injury = _text(getattr(prop, "injuryStatus", ""))
    injury_resolved = injury in {
        "healthy", "active", "available", "probable", "none", "clear",
        "no injury reported",
    }
    news_score = (8 if injury_resolved else 0) + (
        7 if lineup_confirmed else 0
    )
    if not injury_resolved:
        warnings.append("Injury status is unresolved; recheck before acting.")
    if not lineup_confirmed:
        warnings.append("Wait for confirmed starters and rotation news.")
    factors.append(_factor(
        "news",
        "Injury and lineup news",
        news_score,
        15,
        f"Injury {injury or 'unknown'}; lineup {lineup or 'unknown'}.",
    ))

    context_score, context_detail = _market_context(prop)
    if context_score < 9:
        warnings.append("Prop-type matchup inputs are incomplete.")
    factors.append(_factor(
        "market_context",
        "Prop-type matchup",
        context_score,
        15,
        context_detail,
    ))

    books = int(getattr(prop, "marketBookCount", 0) or 0)
    market_score = (
        10 if books >= 3 else 7 if books == 2 else 3 if books == 1 else 0
    )
    if books < 2:
        warnings.append(
            "Fewer than two independent market sources confirm the line."
        )
    factors.append(_factor(
        "market",
        "Market confirmation",
        market_score,
        10,
        f"{books} distinct books confirm this market.",
    ))

    freshness_score = (
        2 if not bool(getattr(prop, "dataStale", False)) else 0
    )
    fatigue_known = (
        getattr(prop, "restDays", None) is not None
        or getattr(prop, "fatigueMultiplier", None) is not None
    )
    schedule_score = freshness_score + (3 if fatigue_known else 0)
    if not fatigue_known:
        warnings.append(
            "Rest, travel or back-to-back context is unavailable."
        )
    factors.append(_factor(
        "schedule",
        "Schedule and freshness",
        schedule_score,
        5,
        (
            "Rest/fatigue and a current price are both included."
            if schedule_score == 5
            else "One or more schedule/freshness inputs are missing."
        ),
    ))

    score = sum(int(factor["score"]) for factor in factors)
    ready = (
        minute_score >= 60
        and role_score >= 60
        and lineup_confirmed
        and injury_resolved
    )
    band = (
        "STRONG"
        if score >= 80 and ready
        else "RESEARCH"
        if score >= 65
        else "WAIT"
        if score >= 45
        else "LIMITED"
    )
    return WnbaResearchAssessment(
        score=score,
        band=band,
        research_ready=ready,
        minutes_certainty=minute_score,
        role_clarity=role_score,
        factors=tuple(factors),
        warnings=tuple(warnings[:5]),
    )