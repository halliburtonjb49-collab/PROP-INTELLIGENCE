"""Evidence-gated tendencies learned from settled PI prediction snapshots."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from math import sqrt
from threading import Lock

from database.postgres import database_is_configured, get_database_pool
from services.adaptive_calibration_service import adaptive_calibration_summary


WINDOW_DAYS = 60
MINIMUM_SAMPLE = 30
PROMOTION_SAMPLE = 50
PLAYER_MINIMUM_SAMPLE = 20
MINIMUM_LIFT = 0.04
PRIOR_STRENGTH = 30.0
CACHE_TTL = timedelta(minutes=15)

_lock = Lock()
_cached_at: datetime | None = None
_cached_report: dict[str, object] | None = None


def _text(value: object) -> str:
    return str(value or "").strip()


def _confidence_bucket(probability: float) -> str:
    value = probability * 100
    if value < 55:
        return "50-54 confidence"
    if value < 65:
        return "55-64 confidence"
    if value < 75:
        return "65-74 confidence"
    return "75+ confidence"


def _line_bucket(line: float) -> str:
    if line < 2.5:
        return "line below 2.5"
    if line < 10:
        return "line 2.5-9.5"
    if line < 25:
        return "line 10-24.5"
    return "line 25+"


def _wilson(wins: int, sample: int) -> tuple[float, float]:
    if sample <= 0:
        return 0.0, 1.0
    z = 1.96
    rate = wins / sample
    denominator = 1 + z * z / sample
    center = (rate + z * z / (2 * sample)) / denominator
    margin = z * sqrt((rate * (1 - rate) + z * z / (4 * sample)) / sample) / denominator
    return max(0.0, center - margin), min(1.0, center + margin)


def _explanation(
    *, dimension: str, label: str, sport: str, market: str,
    sample: int, rate: float, baseline: float, status: str,
) -> str:
    direction = "above" if rate >= baseline else "below"
    action = {
        "PROMOTED": "PI may use this as supporting ranking evidence",
        "REJECTED": "PI will not adjust future ratings from this pattern",
        "DEVELOPING": "PI is monitoring this pattern without changing ratings",
    }[status]
    return (
        f"{sport} {market} was {rate * 100:.1f}% across {sample} settled predictions "
        f"for {dimension.replace('_', ' ')}: {label}, {abs(rate - baseline) * 100:.1f} points "
        f"{direction} its market baseline. {action}."
    )


def _build_report(model_version: str) -> dict[str, object]:
    if not database_is_configured():
        return {"available": False, "reason": "DATABASE_URL is not configured"}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select s.sport, s.market, s.side, s.line, s.hit_probability,
                   s.sportsbook, s.source_provider, s.player_id,
                   s.inputs->>'playerName', s.inputs->>'matchup',
                   coalesce(s.inputs->>'homeAway', s.inputs->>'venueSide'),
                   coalesce(s.inputs->>'restDays', s.inputs->>'daysRest'),
                   r.grade_state
              from public.prop_prediction_snapshots s
              join public.prop_results r on r.prop_prediction_snapshot_id = s.id
             where s.model_version = %s
               and r.grade_state in ('WIN', 'LOSS')
               and coalesce(r.graded_at, s.event_time) >= now() - %s::interval
            """,
            (model_version, f"{WINDOW_DAYS} days"),
        )
        rows = cursor.fetchall()

    baselines: dict[tuple[str, str], list[int]] = defaultdict(list)
    groups: dict[tuple[str, str, str, str], list[int]] = defaultdict(list)
    for row in rows:
        sport, market, side, line, probability, sportsbook, provider, player_id, player_name, matchup, home_away, rest_days, state = row
        sport_text, market_text = _text(sport).upper(), _text(market)
        result = 1 if state == "WIN" else 0
        baselines[(sport_text, market_text)].append(result)
        dimensions = [
            ("side", _text(side).upper()),
            ("confidence", _confidence_bucket(float(probability or 0.5))),
            ("line_range", _line_bucket(float(line or 0))),
            ("sportsbook", _text(sportsbook)),
            ("provider", _text(provider)),
            ("player", _text(player_name) or _text(player_id)),
            ("matchup", _text(matchup)),
            ("home_away", _text(home_away).upper()),
            ("rest", f"{_text(rest_days)} days rest" if _text(rest_days) else ""),
        ]
        for dimension, label in dimensions:
            if label:
                groups[(sport_text, market_text, dimension, label)].append(result)

    findings: list[dict[str, object]] = []
    for (sport, market, dimension, label), outcomes in groups.items():
        minimum = PLAYER_MINIMUM_SAMPLE if dimension in {"player", "matchup"} else MINIMUM_SAMPLE
        if len(outcomes) < minimum:
            continue
        baseline_outcomes = baselines[(sport, market)]
        baseline = sum(baseline_outcomes) / len(baseline_outcomes)
        wins, sample = sum(outcomes), len(outcomes)
        raw_rate = wins / sample
        rate = ((wins) + baseline * PRIOR_STRENGTH) / (sample + PRIOR_STRENGTH)
        low, high = _wilson(wins, sample)
        lift = rate - baseline
        clears_uncertainty = low > baseline or high < baseline
        if sample >= PROMOTION_SAMPLE and abs(lift) >= MINIMUM_LIFT and clears_uncertainty:
            status = "PROMOTED"
        elif sample >= PROMOTION_SAMPLE and (abs(lift) < MINIMUM_LIFT or not clears_uncertainty):
            status = "REJECTED"
        else:
            status = "DEVELOPING"
        findings.append({
            "sport": sport,
            "market": market,
            "dimension": dimension,
            "label": label,
            "status": status,
            "direction": "POSITIVE" if lift >= 0 else "NEGATIVE",
            "sampleSize": sample,
            "wins": wins,
            "losses": sample - wins,
            "rawWinRate": round(raw_rate, 4),
            "shrunkWinRate": round(rate, 4),
            "marketBaseline": round(baseline, 4),
            "lift": round(lift, 4),
            "confidenceInterval": [round(low, 4), round(high, 4)],
            "explanation": _explanation(
                dimension=dimension, label=label, sport=sport, market=market,
                sample=sample, rate=rate, baseline=baseline, status=status,
            ),
        })
    order = {"PROMOTED": 0, "DEVELOPING": 1, "REJECTED": 2}
    findings.sort(key=lambda item: (order[str(item["status"])], -abs(float(item["lift"])), -int(item["sampleSize"])))
    calibration = adaptive_calibration_summary(model_version)
    return {
        "available": True,
        "modelVersion": model_version,
        "windowDays": WINDOW_DAYS,
        "settledPredictions": len(rows),
        "marketPopulations": len(baselines),
        "summary": {
            "promoted": sum(1 for item in findings if item["status"] == "PROMOTED"),
            "developing": sum(1 for item in findings if item["status"] == "DEVELOPING"),
            "rejected": sum(1 for item in findings if item["status"] == "REJECTED"),
            "calibrationSegmentsPromoted": calibration.get("promotedSegments", 0),
        },
        "findings": findings[:150],
        "calibration": calibration,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }


def pi_tendency_report(model_version: str = "baseline-v3") -> dict[str, object]:
    global _cached_at, _cached_report
    now = datetime.now(timezone.utc)
    with _lock:
        if _cached_at is not None and _cached_report is not None and now - _cached_at < CACHE_TTL:
            return _cached_report
        _cached_report = _build_report(model_version)
        _cached_at = now
        return _cached_report
