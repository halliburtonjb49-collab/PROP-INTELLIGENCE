"""Guarded promotion and rollback for verified PI recalculation outcomes."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
import os
from threading import Lock
from typing import Iterable


def _integer(name: str, default: int, minimum: int = 1) -> int:
    try:
        return max(minimum, int(os.getenv(name, str(default))))
    except ValueError:
        return default


def _ratio(name: str, default: float) -> float:
    try:
        return max(0.0, min(1.0, float(os.getenv(name, str(default)))))
    except ValueError:
        return default


MINIMUM_SAMPLE = _integer("PI_RECALC_MIN_SAMPLE", 30)
MINIMUM_ACCURACY = _ratio("PI_RECALC_MIN_ACCURACY", 0.55)
MINIMUM_MAE_IMPROVEMENT = _ratio("PI_RECALC_MIN_MAE_IMPROVEMENT", 0.05)
ROLLBACK_SAMPLE = _integer("PI_RECALC_ROLLBACK_SAMPLE", 15)
ROLLBACK_MINIMUM_ACCURACY = _ratio("PI_RECALC_ROLLBACK_MIN_ACCURACY", 0.50)
CACHE_TTL = timedelta(minutes=10)


@dataclass(frozen=True)
class RecalculationProfile:
    sport: str
    market: str
    sample_size: int = 0
    accuracy: float = 0.0
    entry_mae: float | None = None
    recalculated_mae: float | None = None
    mae_improvement: float = 0.0
    recent_sample_size: int = 0
    recent_accuracy: float = 0.0
    recent_entry_mae: float | None = None
    recent_recalculated_mae: float | None = None
    promoted: bool = False
    ranking_influence: int = 0
    reason: str = "insufficient-verified-sample"

    def api_payload(self) -> dict[str, object]:
        payload = asdict(self)
        return {
            "sport": payload["sport"],
            "market": payload["market"],
            "sampleSize": payload["sample_size"],
            "accuracy": round(float(payload["accuracy"]) * 100, 1),
            "entryMae": payload["entry_mae"],
            "recalculatedMae": payload["recalculated_mae"],
            "maeImprovement": round(float(payload["mae_improvement"]) * 100, 1),
            "recentSampleSize": payload["recent_sample_size"],
            "recentAccuracy": round(float(payload["recent_accuracy"]) * 100, 1),
            "recentEntryMae": payload["recent_entry_mae"],
            "recentRecalculatedMae": payload["recent_recalculated_mae"],
            "promoted": payload["promoted"],
            "rankingInfluence": payload["ranking_influence"],
            "reason": payload["reason"],
        }


def _key(sport: object, market: object) -> tuple[str, str]:
    return str(sport or "").strip().upper(), str(market or "").strip().lower()


def _instant(value: object) -> datetime:
    try:
        parsed = datetime.fromisoformat(str(value or "").replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)


def _mae(rows: list[tuple[datetime, float, float, bool]], index: int) -> float:
    return round(sum(row[index] for row in rows) / len(rows), 4)


def _fit(sport: str, market: str, rows: list[tuple[datetime, float, float, bool]]) -> RecalculationProfile:
    ordered = sorted(rows, key=lambda row: row[0])
    sample = len(ordered)
    accuracy = sum(int(row[3]) for row in ordered) / sample
    entry_mae = _mae(ordered, 1)
    recalculated_mae = _mae(ordered, 2)
    improvement = (entry_mae - recalculated_mae) / entry_mae if entry_mae > 0 else 0.0
    recent = ordered[-ROLLBACK_SAMPLE:]
    recent_accuracy = sum(int(row[3]) for row in recent) / len(recent)
    recent_entry_mae = _mae(recent, 1)
    recent_recalculated_mae = _mae(recent, 2)

    promoted = False
    reason = "insufficient-verified-sample"
    if sample >= MINIMUM_SAMPLE:
        if accuracy < MINIMUM_ACCURACY:
            reason = "accuracy-below-threshold"
        elif improvement < MINIMUM_MAE_IMPROVEMENT:
            reason = "mae-improvement-below-threshold"
        elif len(recent) >= ROLLBACK_SAMPLE and (
            recent_accuracy < ROLLBACK_MINIMUM_ACCURACY
            or recent_recalculated_mae >= recent_entry_mae
        ):
            reason = "recent-performance-rollback"
        else:
            promoted = True
            reason = "verified-mae-improvement"

    influence = 0
    if promoted:
        influence = min(3, max(1, round((accuracy - 0.5) * 10 + improvement * 5)))
    return RecalculationProfile(
        sport=sport, market=market, sample_size=sample, accuracy=accuracy,
        entry_mae=entry_mae, recalculated_mae=recalculated_mae,
        mae_improvement=improvement, recent_sample_size=len(recent),
        recent_accuracy=recent_accuracy, recent_entry_mae=recent_entry_mae,
        recent_recalculated_mae=recent_recalculated_mae, promoted=promoted,
        ranking_influence=influence, reason=reason,
    )


def profiles_from_slips(slips: Iterable[object]) -> dict[tuple[str, str], RecalculationProfile]:
    grouped: dict[tuple[str, str], list[tuple[datetime, float, float, bool]]] = {}
    for slip in slips:
        for leg in getattr(slip, "legs", ()):
            if getattr(leg, "result_verified", False) is not True:
                continue
            entry = getattr(leg, "pi_entry_error", None)
            recalculated = getattr(leg, "pi_recalculated_error", None)
            correct = getattr(leg, "pi_recalculation_correct", None)
            if entry is None or recalculated is None or correct is None:
                continue
            key = _key(getattr(leg, "sport", ""), getattr(leg, "market", ""))
            grouped.setdefault(key, []).append((
                _instant(getattr(leg, "result_verified_at", "")),
                float(entry), float(recalculated), bool(correct),
            ))
    return {key: _fit(*key, rows) for key, rows in grouped.items()}


_lock = Lock()
_cached_at: datetime | None = None
_cached_profiles: dict[tuple[str, str], RecalculationProfile] = {}


def current_profiles() -> dict[tuple[str, str], RecalculationProfile]:
    global _cached_at, _cached_profiles
    now = datetime.now(timezone.utc)
    with _lock:
        if _cached_at is not None and now - _cached_at < CACHE_TTL:
            return _cached_profiles
        from services.slip_service import get_slips
        _cached_profiles = profiles_from_slips(get_slips())
        _cached_at = now
        return _cached_profiles


def profile_for(sport: object, market: object) -> RecalculationProfile:
    key = _key(sport, market)
    return current_profiles().get(key, RecalculationProfile(*key))


def learning_summary(slips: Iterable[object]) -> list[dict[str, object]]:
    profiles = profiles_from_slips(slips)
    return [
        profile.api_payload()
        for profile in sorted(
            profiles.values(), key=lambda item: (-item.sample_size, item.sport, item.market)
        )
    ]


def learning_control_summary(slips: Iterable[object]) -> dict[str, object]:
    profiles = list(profiles_from_slips(slips).values())
    promoted = [profile for profile in profiles if profile.promoted]
    rolled_back = [
        profile for profile in profiles
        if profile.reason == "recent-performance-rollback"
    ]
    return {
        "minimumSample": MINIMUM_SAMPLE,
        "minimumAccuracy": round(MINIMUM_ACCURACY * 100, 1),
        "minimumMaeImprovement": round(MINIMUM_MAE_IMPROVEMENT * 100, 1),
        "rollbackSample": ROLLBACK_SAMPLE,
        "rollbackMinimumAccuracy": round(ROLLBACK_MINIMUM_ACCURACY * 100, 1),
        "segments": len(profiles),
        "promotedSegments": len(promoted),
        "rolledBackSegments": len(rolled_back),
        "collectingSegments": len(profiles) - len(promoted) - len(rolled_back),
        "verifiedSamples": sum(profile.sample_size for profile in profiles),
        "maximumRankingInfluence": 3,
        "automaticInfluenceEnabled": bool(promoted),
    }
