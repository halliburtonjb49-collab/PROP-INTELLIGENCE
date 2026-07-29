import pytest

from services.provider_quality_service import (
    fetch_with_provider_fallback,
    provider_quality_score,
)


def test_rate_limit_penalizes_provider_quality() -> None:
    healthy = provider_quality_score(
        success_rate=.99, freshness_score=1, completeness_score=1,
    )
    limited = provider_quality_score(
        success_rate=.99, freshness_score=1, completeness_score=1,
        rate_limited=True,
    )
    assert healthy > limited


def test_provider_fallback_uses_next_healthy_source() -> None:
    def unavailable() -> list[int]:
        raise TimeoutError("provider timeout")

    result, audit = fetch_with_provider_fallback([
        ("primary", .95, unavailable),
        ("secondary", .8, lambda: [1, 2]),
    ], is_usable=bool)
    assert result == [1, 2]
    assert audit["selectedProvider"] == "secondary"
    assert audit["fallbackUsed"] is True


def test_provider_fallback_fails_closed_without_usable_data() -> None:
    with pytest.raises(RuntimeError, match="No provider returned usable data"):
        fetch_with_provider_fallback([
            ("empty", .9, list),
        ], is_usable=bool)
