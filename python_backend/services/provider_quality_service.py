"""Provider quality scoring and deterministic source selection."""

from __future__ import annotations

from collections.abc import Callable
from typing import TypeVar

T = TypeVar("T")


def provider_quality_score(
    *,
    success_rate: float,
    freshness_score: float,
    completeness_score: float,
    rate_limited: bool = False,
) -> float:
    score = (
        max(0.0, min(1.0, success_rate)) * 0.45
        + max(0.0, min(1.0, freshness_score)) * 0.3
        + max(0.0, min(1.0, completeness_score)) * 0.25
    )
    if rate_limited:
        score *= 0.35
    return round(score, 4)


def fetch_with_provider_fallback(
    providers: list[tuple[str, float, Callable[[], T]]],
    *,
    is_usable: Callable[[T], bool] | None = None,
) -> tuple[T, dict[str, object]]:
    """Try healthy providers in score order and retain an audit trail."""
    attempts: list[dict[str, object]] = []
    usable = is_usable or (lambda result: result is not None)
    for name, score, fetcher in sorted(providers, key=lambda item: item[1], reverse=True):
        try:
            result = fetcher()
            if usable(result):
                return result, {
                    "selectedProvider": name,
                    "selectedScore": score,
                    "fallbackUsed": bool(attempts),
                    "attempts": attempts,
                }
            attempts.append({"provider": name, "score": score, "reason": "empty_or_unusable"})
        except Exception as exc:
            attempts.append({"provider": name, "score": score, "reason": type(exc).__name__})
    raise RuntimeError(f"No provider returned usable data: {attempts}")
