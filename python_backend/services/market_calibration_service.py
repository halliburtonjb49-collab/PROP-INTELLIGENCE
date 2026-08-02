"""Cached out-of-sample probability corrections by sport, market, and model."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from threading import Lock

from database.postgres import database_is_configured, get_database_pool

_CACHE_TTL = timedelta(minutes=10)
_MINIMUM_SAMPLE = 30
_lock = Lock()
_loaded_at: datetime | None = None
_adjustments: dict[tuple[str, str, str, str], tuple[float, int]] = {}


def _eligible_adjustment(
    *, predicted: float, actual: float, sample_size: int,
) -> float:
    """Correct only audit segments labeled MONITOR or RECALIBRATE."""
    if sample_size < _MINIMUM_SAMPLE:
        return 0.0
    gap = predicted - actual
    should_recalibrate = actual < 0.50 or gap > 0.08
    should_monitor = abs(gap) > 0.05
    if not (should_recalibrate or should_monitor):
        return 0.0
    reliability = min(1.0, sample_size / 200.0)
    return max(-0.08, min(0.08, (actual - predicted) * reliability))


def _key(
    sport: str,
    market: str,
    model_version: str,
    side: str,
) -> tuple[str, str, str, str]:
    return (
        sport.strip().upper(),
        " ".join(market.lower().replace("_", " ").split()),
        model_version.strip().lower(),
        side.strip().upper(),
    )


def _refresh() -> None:
    global _loaded_at, _adjustments
    now = datetime.now(timezone.utc)
    if _loaded_at is not None and now - _loaded_at < _CACHE_TTL:
        return
    if not database_is_configured():
        _loaded_at = now
        return
    with _lock:
        if _loaded_at is not None and now - _loaded_at < _CACHE_TTL:
            return
        values: dict[tuple[str, str, str, str], tuple[float, int]] = {}
        try:
            with get_database_pool().connection() as connection, connection.cursor() as cursor:
                cursor.execute(
                    """select sport,market,model_version,side,count(*),
                        avg(hit_probability),avg(case when hit then 1.0 else 0.0 end)
                    from prediction_snapshots
                    where graded_at is not null and actual_value <> line
                    group by sport,market,model_version,side
                    having count(*) >= %s""",
                    (_MINIMUM_SAMPLE,),
                )
                for sport, market, version, side, count, predicted, actual in cursor.fetchall():
                    adjustment = _eligible_adjustment(
                        predicted=float(predicted),
                        actual=float(actual),
                        sample_size=int(count),
                    )
                    if adjustment == 0.0:
                        continue
                    values[_key(str(sport), str(market), str(version), str(side))] = (
                        adjustment,
                        int(count),
                    )
        except Exception:
            values = {}
        _adjustments = values
        _loaded_at = now


def market_calibration_adjustment(
    sport: str,
    market: str,
    model_version: str,
    side: str,
) -> tuple[float, int]:
    _refresh()
    return _adjustments.get(_key(sport, market, model_version, side), (0.0, 0))
