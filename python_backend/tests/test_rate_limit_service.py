from services import rate_limit_service


def test_memory_token_bucket_enforces_limit(monkeypatch) -> None:
    monkeypatch.setattr(rate_limit_service, "REDIS_URL", "")
    monkeypatch.setattr(rate_limit_service, "ANONYMOUS_REQUESTS_PER_MINUTE", 2)
    rate_limit_service._memory_buckets.clear()

    first = rate_limit_service.allow_request(
        "anonymous:test", authenticated=False, now=100
    )
    second = rate_limit_service.allow_request(
        "anonymous:test", authenticated=False, now=100
    )
    blocked = rate_limit_service.allow_request(
        "anonymous:test", authenticated=False, now=100
    )

    assert first == (True, 1, 2)
    assert second == (True, 0, 2)
    assert blocked == (False, 0, 2)


def test_authenticated_bucket_uses_separate_configured_capacity(monkeypatch) -> None:
    monkeypatch.setattr(rate_limit_service, "REDIS_URL", "")
    monkeypatch.setattr(rate_limit_service, "AUTHENTICATED_REQUESTS_PER_MINUTE", 5)
    rate_limit_service._memory_buckets.clear()

    allowed, remaining, limit = rate_limit_service.allow_request(
        "bearer:test", authenticated=True, now=100
    )

    assert allowed is True
    assert remaining == 4
    assert limit == 5
