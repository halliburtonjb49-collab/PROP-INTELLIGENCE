"""Cross-sport performance drift profiles and conservative live guardrails."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import logging
from threading import Lock

from database.postgres import database_is_configured, get_database_pool


LOGGER = logging.getLogger(__name__)
RECENT_DAYS = 7
BASELINE_DAYS = 30
MINIMUM_SAMPLE = 30
CACHE_TTL = timedelta(minutes=15)


@dataclass(frozen=True)
class DriftProfile:
    status: str = "COLLECTING"
    penalty: float = 0.0
    recent_sample: int = 0
    baseline_sample: int = 0
    recent_accuracy: float | None = None
    baseline_accuracy: float | None = None
    calibration_gap: float | None = None
    reason: str = "Insufficient settled results for drift evaluation."


_lock = Lock()
_cached_at: datetime | None = None
_profiles: dict[tuple[str, str, str, str, str], DriftProfile] = {}


def _key(model: object, sport: object, market: object, side: object, provider: object) -> tuple[str, str, str, str, str]:
    return (
        str(model or "").strip().lower(), str(sport or "").strip().upper(),
        str(market or "").strip().lower(), str(side or "").strip().upper(),
        str(provider or "").strip().lower(),
    )


def _evaluate(recent: list[tuple[float, bool]], baseline: list[tuple[float, bool]]) -> DriftProfile:
    if len(recent) < MINIMUM_SAMPLE or len(baseline) < MINIMUM_SAMPLE:
        return DriftProfile(recent_sample=len(recent), baseline_sample=len(baseline))
    recent_accuracy = sum(hit for _, hit in recent) / len(recent)
    baseline_accuracy = sum(hit for _, hit in baseline) / len(baseline)
    average_confidence = sum(probability for probability, _ in recent) / len(recent)
    gap = average_confidence - recent_accuracy
    decline = baseline_accuracy - recent_accuracy
    if recent_accuracy < .50 or gap > .08 or decline > .08:
        status, penalty = "RECALIBRATE", -.08
        reason = "Recent verified accuracy or calibration moved beyond the safety range."
    elif abs(gap) > .05 or decline > .05:
        status, penalty = "MONITOR", -.04
        reason = "Recent performance is outside the normal monitoring range."
    else:
        status, penalty = "HEALTHY", 0.0
        reason = "Recent verified performance remains inside drift guardrails."
    return DriftProfile(
        status=status, penalty=penalty, recent_sample=len(recent),
        baseline_sample=len(baseline), recent_accuracy=round(recent_accuracy, 4),
        baseline_accuracy=round(baseline_accuracy, 4), calibration_gap=round(gap, 4),
        reason=reason,
    )


def _load() -> dict[tuple[str, str, str, str, str], DriftProfile]:
    if not database_is_configured():
        return {}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            select model_version, sport, market, side,
                   coalesce(nullif(inputs->>'sourceProvider',''), 'unknown'),
                   graded_at, hit_probability, hit
              from public.prediction_snapshots
             where hit is not null and hit_probability is not null
               and graded_at >= now() - %s::interval
               and created_at < event_time - interval '5 minutes'
            """,
            (f"{BASELINE_DAYS + RECENT_DAYS} days",),
        )
        rows = cursor.fetchall()
    now = datetime.now(timezone.utc)
    recent_cutoff = now - timedelta(days=RECENT_DAYS)
    baseline_cutoff = recent_cutoff - timedelta(days=BASELINE_DAYS)
    recent: dict[tuple[str, str, str, str, str], list[tuple[float, bool]]] = defaultdict(list)
    baseline: dict[tuple[str, str, str, str, str], list[tuple[float, bool]]] = defaultdict(list)
    for model, sport, market, side, provider, graded_at, probability, hit in rows:
        occurred = graded_at.astimezone(timezone.utc) if graded_at.tzinfo else graded_at.replace(tzinfo=timezone.utc)
        item = (float(probability), bool(hit))
        keys = (
            _key(model, sport, market, side, provider),
            _key(model, sport, market, side, ""),
            _key(model, sport, market, "", ""),
        )
        target = recent if occurred >= recent_cutoff else baseline if occurred >= baseline_cutoff else None
        if target is not None:
            for segment in keys:
                target[segment].append(item)
    return {
        segment: _evaluate(values, baseline.get(segment, []))
        for segment, values in recent.items()
    }


def _current() -> dict[tuple[str, str, str, str, str], DriftProfile]:
    global _cached_at, _profiles
    now = datetime.now(timezone.utc)
    with _lock:
        if _cached_at is not None and now - _cached_at < CACHE_TTL:
            return _profiles
        try:
            _profiles = _load()
        except Exception as exc:
            LOGGER.warning("PI drift profiles unavailable: %s", exc)
            _profiles = {}
        _cached_at = now
        return _profiles


def drift_profile_for(*, model_version: str, sport: str, market: str, side: str, provider: str) -> DriftProfile:
    profiles = _current()
    candidates = (
        _key(model_version, sport, market, side, provider),
        _key(model_version, sport, market, side, ""),
        _key(model_version, sport, market, "", ""),
    )
    for candidate in candidates:
        profile = profiles.get(candidate)
        if profile is not None and profile.status != "COLLECTING":
            return profile
    return next((profiles[key] for key in candidates if key in profiles), DriftProfile())
