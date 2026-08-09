"""The record, stated plainly enough that someone who has not paid can check it.

Every number here already existed. `model_performance` has computed win rate,
simulated ROI, closing-line value and per-tier results for a long time, and
all of it sat behind `require_pro`. A track record only visible to people who
already subscribed proves nothing to the person deciding whether to.

Two rules govern what this will say.

The first is that a rate must be earned before it is published. A win rate
drawn from nine graded picks is not a track record, it is noise with a
percent sign, and putting it on a page aimed at buyers makes it a claim. Below
the minimum sample this reports how far along the record is and publishes no
rate at all -- `published` is false and the rates are absent rather than zero,
because zero is a number and absent is the truth.

The second is that nothing is recomputed here. If this file disagreed with
the internal performance view, one of them would be wrong, and the one facing
buyers is the worse one to be wrong. This selects, rounds and labels; it never
calculates a result.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from threading import Lock
from typing import Any, Mapping, Sequence

from services.baseline_projection_service import MODEL_VERSION
from services.model_performance_service import model_performance

logger = logging.getLogger(__name__)

# Why the last read of the performance view failed, if it did.
#
# This page is the one a prospective buyer sees, so it must not be able to
# answer with a server error -- "the record is unavailable" is a far smaller
# problem than a page that looks broken. Swallowing the failure silently
# would just move the mystery, so the reason is kept here and reported on the
# operations health endpoint, where every other unobservable failure in this
# service ended up being diagnosed.
_failure_lock = Lock()
_last_failure = ""


def last_failure() -> str:
    with _failure_lock:
        return _last_failure


def _record_failure(error: BaseException) -> None:
    global _last_failure
    with _failure_lock:
        _last_failure = f"{type(error).__name__}: {error}"[:300]

# Graded picks required before any rate is published.
#
# Matches the calibration minimum the model already holds itself to. Choosing
# a smaller number here would mean advertising a record the model does not yet
# consider itself calibrated on.
MINIMUM_PUBLISHED_SAMPLE = 100

# Order tiers strongest first, so the page reads top down as the model's own
# confidence descending rather than alphabetically.
_TIER_ORDER = ("HIGH", "MEDIUM", "BASELINE")

_TIER_LABELS: Mapping[str, str] = {
    "HIGH": "High confidence",
    "MEDIUM": "Medium confidence",
    "BASELINE": "Baseline",
}


def _number(value: object) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if result == result else None  # reject NaN


def _count(value: object) -> int:
    number = _number(value)
    return int(number) if number is not None else 0


def _tier_results(segments: Sequence[Mapping[str, Any]]) -> list[dict[str, object]]:
    """Per-tier record, summed from the segments rather than re-derived.

    A tier is published on the same terms as the overall record: a tier with
    too few graded picks reports its count and withholds its rate, because a
    reader comparing tiers will read the strongest number as the claim.
    """

    totals: dict[str, dict[str, int]] = {}
    for segment in segments:
        tier = str(segment.get("confidenceTier") or "").strip().upper()
        if tier not in _TIER_LABELS:
            continue
        bucket = totals.setdefault(tier, {"sampleSize": 0, "hits": 0})
        bucket["sampleSize"] += _count(segment.get("sampleSize"))
        bucket["hits"] += _count(segment.get("hits"))

    results: list[dict[str, object]] = []
    for tier in _TIER_ORDER:
        bucket = totals.get(tier)
        if bucket is None or bucket["sampleSize"] <= 0:
            continue
        sample = bucket["sampleSize"]
        earned = sample >= MINIMUM_PUBLISHED_SAMPLE
        results.append(
            {
                "tier": tier,
                "label": _TIER_LABELS[tier],
                "sampleSize": sample,
                "hits": bucket["hits"],
                "winRate": round(bucket["hits"] / sample, 4) if earned else None,
                "published": earned,
            }
        )
    return results


def _breakdown_results(
    segments: Sequence[Mapping[str, Any]], key: str
) -> list[dict[str, object]]:
    """Aggregate already-computed segment results for a public breakdown."""
    totals: dict[str, dict[str, float]] = {}
    for segment in segments:
        raw = str(segment.get(key) or "").strip()
        if not raw:
            continue
        name = raw.upper() if key == "sport" else raw.replace("_", " ").title()
        bucket = totals.setdefault(
            name, {"sampleSize": 0, "hits": 0, "roiWeighted": 0.0, "roiSample": 0}
        )
        sample = _count(segment.get("sampleSize"))
        bucket["sampleSize"] += sample
        bucket["hits"] += _count(segment.get("hits"))
        roi = _number(segment.get("simulatedRoi"))
        if roi is not None and sample:
            bucket["roiWeighted"] += roi * sample
            bucket["roiSample"] += sample

    rows: list[dict[str, object]] = []
    for label, bucket in totals.items():
        sample = int(bucket["sampleSize"])
        if sample <= 0:
            continue
        earned = sample >= MINIMUM_PUBLISHED_SAMPLE
        roi_sample = int(bucket["roiSample"])
        rows.append({
            "key": label,
            "label": label,
            "sampleSize": sample,
            "hits": int(bucket["hits"]),
            "winRate": round(bucket["hits"] / sample, 4) if earned else None,
            "simulatedRoi": (
                round(bucket["roiWeighted"] / roi_sample, 4)
                if earned and roi_sample else None
            ),
            "published": earned,
        })
    rows.sort(key=lambda row: (-int(row["sampleSize"]), str(row["label"])))
    return rows


def _calibration_curve(
    segments: Sequence[Mapping[str, Any]],
) -> list[dict[str, object]]:
    """Combine the performance service's confidence ranges into a public curve."""
    totals: dict[str, dict[str, float]] = {}
    for segment in segments:
        label = str(segment.get("confidenceRange") or "").strip()
        if not label:
            continue
        bucket = totals.setdefault(
            label, {"sampleSize": 0, "hits": 0, "confidenceWeighted": 0.0}
        )
        sample = _count(segment.get("sampleSize"))
        confidence = _number(segment.get("averageConfidence"))
        bucket["sampleSize"] += sample
        bucket["hits"] += _count(segment.get("hits"))
        if confidence is not None:
            bucket["confidenceWeighted"] += confidence * sample

    order = {"below-60%": 0, "60-69%": 1, "70-79%": 2, "80-100%": 3}
    rows: list[dict[str, object]] = []
    for label, bucket in totals.items():
        sample = int(bucket["sampleSize"])
        judged = sample >= 30
        rows.append({
            "label": label,
            "sampleSize": sample,
            "predicted": (
                round(bucket["confidenceWeighted"] / sample, 4) if sample else None
            ),
            "observed": round(bucket["hits"] / sample, 4) if sample else None,
            "judged": judged,
        })
    rows.sort(key=lambda row: order.get(str(row["label"]), 99))
    return rows

def public_track_record(model_version: str = MODEL_VERSION) -> dict[str, object]:
    """What the model has actually done, for anyone who asks."""

    try:
        performance = model_performance(model_version)
    except Exception as exc:  # noqa: BLE001 - the page must still answer
        _record_failure(exc)
        logger.exception("public track record unavailable")
        performance = {}
    else:
        with _failure_lock:
            globals()["_last_failure"] = ""
    sample_size = _count(performance.get("sampleSize"))
    published = sample_size >= MINIMUM_PUBLISHED_SAMPLE

    win_rate = _number(performance.get("accuracy"))
    roi = _number(performance.get("simulatedRoi"))
    clv = performance.get("clv")
    clv = clv if isinstance(clv, Mapping) else {}
    segments = performance.get("segments")
    segments = segments if isinstance(segments, Sequence) else []
    quality_segments = performance.get("qualitySegments")
    quality_segments = quality_segments if isinstance(quality_segments, Sequence) else []
    streak = performance.get("currentStreak")
    streak = streak if isinstance(streak, Mapping) else {"type": "NONE", "length": 0}

    return {
        # The reader needs to know how old this is before they trust it.
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "modelVersion": performance.get("modelVersion") or model_version,
        # Whether anything below is a claim or a progress report.
        "published": published,
        "sampleSize": sample_size,
        "minimumPublishedSample": MINIMUM_PUBLISHED_SAMPLE,
        "gradedPicksRemaining": max(0, MINIMUM_PUBLISHED_SAMPLE - sample_size),
        "winRate": win_rate if published else None,
        # Named for what it is. This is modelled from entry odds, not money
        # that was actually staked, and calling it plain ROI on a page aimed
        # at buyers would be a claim we cannot support.
        "simulatedRoi": roi if published else None,
        "closingLineValue": {
            "available": bool(clv.get("available")) and published,
            "sampleSize": _count(clv.get("sampleSize")),
            "beatClosingLineRate": (
                _number(clv.get("beatClosingLineRate")) if published else None
            ),
            # The denominator, without which the rate above is unreadable.
            # A prop line often does not move at all, and those are not
            # failures to price it well -- they are absence of evidence.
            "movedLineSampleSize": _count(clv.get("movedLineSampleSize")),
            "unchangedLineCount": _count(clv.get("unchangedLineCount")),
            "averageLinePoints": (
                _number(clv.get("averageLineClvPoints")) if published else None
            ),
            # Not closing-line value, despite living under this key.
            #
            # It divides the market's de-vigged closing probability by our
            # entry break-even, which still carries the vig, so it answers
            # "what was this bet worth at the price we took" rather than
            # "did we beat the close". The asymmetry is the point and must
            # not be tidied away: a bet at -110 needing 52.4% to break even
            # is genuinely losing if the true close is 50%.
            #
            # It is also the one measurement here that does not depend on
            # our own hit_probability -- both sides come from market prices
            # -- which makes it the most trustworthy number on this page and
            # the reason it is kept despite reading badly.
            "averageOddsValuePercent": (
                _number(clv.get("averageOddsClvExpectedValuePercent"))
                if published
                else None
            ),
            "reason": clv.get("reason"),
        },
        "confidenceTiers": _tier_results(segments),
        "sportBreakdown": _breakdown_results(segments, "sport"),
        "marketBreakdown": _breakdown_results(segments, "market"),
        "calibrationCurve": _calibration_curve(quality_segments),
        "currentStreak": {
            "type": str(streak.get("type") or "NONE").upper(),
            "length": _count(streak.get("length")),
        },
        "lastGradedAt": performance.get("lastGradedAt"),
        "historyPolicy": "APPEND_ONLY_GRADED_RESULTS",
        "losingPredictionsIncluded": True,
        # Kept because a reader who knows what it means can check our
        # calibration claim against it, and one who does not can ignore it.
        "brierScore": _number(performance.get("brierScore")) if published else None,
        "calibrated": bool(performance.get("calibrated")),
    }
