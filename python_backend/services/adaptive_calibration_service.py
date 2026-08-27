"""Guarded, out-of-sample calibration learned from settled prop results."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import logging
from threading import Lock

from database.postgres import database_is_configured, get_database_pool


LOGGER = logging.getLogger(__name__)
WINDOW_DAYS = 60
MINIMUM_SAMPLE = 100
MINIMUM_TEST_SAMPLE = 25
MINIMUM_BRIER_IMPROVEMENT = 0.002
MAXIMUM_ADJUSTMENT = 0.08
SHRINKAGE_SAMPLE = 50.0
CACHE_TTL = timedelta(minutes=15)


@dataclass(frozen=True)
class CalibrationProfile:
    adjustment: float = 0.0
    promoted: bool = False
    sample_size: int = 0
    test_sample_size: int = 0
    active_brier: float | None = None
    challenger_brier: float | None = None
    reason: str = "insufficient-settled-sample"


_lock = Lock()
_cached_at: datetime | None = None
_profiles: dict[tuple[str, str, str, str], CalibrationProfile] = {}


def _key(model_version: object, sport: object, market: object, side: object) -> tuple[str, str, str, str]:
    return (
        str(model_version or "").strip().lower(),
        str(sport or "").strip().upper(),
        str(market or "").strip().lower(),
        str(side or "").strip().upper(),
    )


def _clamp(value: float) -> float:
    return max(-MAXIMUM_ADJUSTMENT, min(MAXIMUM_ADJUSTMENT, value))


def _brier(rows: list[tuple[float, float]], adjustment: float = 0.0) -> float:
    return sum((max(0.01, min(0.99, probability + adjustment)) - result) ** 2 for probability, result in rows) / len(rows)


def _fit(rows: list[tuple[datetime, float, float]]) -> CalibrationProfile:
    if len(rows) < MINIMUM_SAMPLE:
        return CalibrationProfile(sample_size=len(rows))
    ordered = sorted(rows, key=lambda row: row[0])
    split = max(MINIMUM_SAMPLE - MINIMUM_TEST_SAMPLE, int(len(ordered) * 0.70))
    split = min(split, len(ordered) - MINIMUM_TEST_SAMPLE)
    train = [(probability, result) for _, probability, result in ordered[:split]]
    test = [(probability, result) for _, probability, result in ordered[split:]]
    if len(test) < MINIMUM_TEST_SAMPLE:
        return CalibrationProfile(sample_size=len(rows), test_sample_size=len(test))

    gap = sum(result - probability for probability, result in train) / len(train)
    adjustment = _clamp(gap * (len(train) / (len(train) + SHRINKAGE_SAMPLE)))
    active_brier = _brier(test)
    challenger_brier = _brier(test, adjustment)
    improvement = active_brier - challenger_brier
    promoted = improvement >= MINIMUM_BRIER_IMPROVEMENT
    return CalibrationProfile(
        adjustment=round(adjustment, 6) if promoted else 0.0,
        promoted=promoted,
        sample_size=len(rows),
        test_sample_size=len(test),
        active_brier=round(active_brier, 6),
        challenger_brier=round(challenger_brier, 6),
        reason="out-of-sample-improvement" if promoted else "challenger-did-not-beat-active",
    )


def _load_profiles() -> dict[tuple[str, str, str, str], CalibrationProfile]:
    if not database_is_configured():
        return {}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select s.model_version, s.sport, s.market, s.side,
                   coalesce(r.graded_at, s.event_time), s.hit_probability,
                   case when r.grade_state = 'WIN' then 1.0 else 0.0 end
              from public.prop_prediction_snapshots s
              join public.prop_results r on r.prop_prediction_snapshot_id = s.id
             where r.grade_state in ('WIN', 'LOSS')
               and s.hit_probability is not null
               and coalesce(r.graded_at, s.event_time) >= now() - %s::interval
             order by coalesce(r.graded_at, s.event_time)
            """,
            (f"{WINDOW_DAYS} days",),
        )
        rows = cursor.fetchall()

    grouped: dict[tuple[str, str, str, str], list[tuple[datetime, float, float]]] = {}
    for model_version, sport, market, side, occurred_at, probability, result in rows:
        exact = _key(model_version, sport, market, side)
        broad = _key(model_version, sport, market, "")
        item = (occurred_at, float(probability), float(result))
        grouped.setdefault(exact, []).append(item)
        grouped.setdefault(broad, []).append(item)
    return {key: _fit(values) for key, values in grouped.items()}


def _current_profiles() -> dict[tuple[str, str, str, str], CalibrationProfile]:
    global _cached_at, _profiles
    now = datetime.now(timezone.utc)
    with _lock:
        if _cached_at is not None and now - _cached_at < CACHE_TTL:
            return _profiles
        try:
            loaded = _load_profiles()
        except Exception as exc:
            LOGGER.warning("Adaptive calibration unavailable: %s", exc)
            loaded = {}
        _profiles = loaded
        _cached_at = now
        return _profiles


def adaptive_calibration_for(
    *, model_version: str, sport: str, market: str, side: str
) -> CalibrationProfile:
    """Return a promoted exact-segment profile, then a sport/market fallback."""

    profiles = _current_profiles()
    exact = profiles.get(_key(model_version, sport, market, side))
    if exact is not None and exact.promoted:
        return exact
    broad = profiles.get(_key(model_version, sport, market, ""))
    if broad is not None:
        return broad
    return exact or CalibrationProfile()


def adaptive_calibration_summary(model_version: str) -> dict[str, object]:
    profiles = _current_profiles()
    rows = [
        {
            "sport": sport,
            "market": market,
            "side": side or "ALL",
            "adjustment": profile.adjustment,
            "promoted": profile.promoted,
            "sampleSize": profile.sample_size,
            "testSampleSize": profile.test_sample_size,
            "activeBrier": profile.active_brier,
            "challengerBrier": profile.challenger_brier,
            "reason": profile.reason,
        }
        for (version, sport, market, side), profile in profiles.items()
        if version == str(model_version or "").strip().lower()
    ]
    return {
        "modelVersion": model_version,
        "windowDays": WINDOW_DAYS,
        "segments": len(rows),
        "promotedSegments": sum(1 for row in rows if row["promoted"]),
        "profiles": sorted(rows, key=lambda row: (-int(row["promoted"]), -int(row["sampleSize"])))[:100],
    }
