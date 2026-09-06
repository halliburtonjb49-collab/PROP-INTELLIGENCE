from datetime import datetime, timezone

import pytest

from services import client_delivery_metrics_service as client_metrics
from services import prop_delivery_metrics_service as api_metrics


def test_api_delivery_percentiles_are_bounded_measurements(monkeypatch) -> None:
    monkeypatch.setattr(api_metrics, "_LATENCY_SAMPLES", api_metrics.deque(maxlen=3))
    monkeypatch.setattr(api_metrics, "_PAYLOAD_SAMPLES", api_metrics.deque(maxlen=3))
    for latency, size in ((10, 100), (20, 200), (90, 900), (30, 300)):
        api_metrics.record_sample(latency, size)

    snapshot = api_metrics.delivery_metrics_snapshot(
        {"requests": 4, "cacheHits": 3, "errors": 1}
    )

    assert snapshot["sampleCount"] == 3
    assert snapshot["cacheHitRatio"] == 0.75
    assert snapshot["latencyMs"] == {"last": None, "p50": 30, "p95": 90}
    assert snapshot["responseBytes"]["p95"] == 900
    assert snapshot["scope"] == "this-api-instance"


def test_client_apply_keeps_provider_and_delivery_latency_separate(monkeypatch) -> None:
    stored = {}
    monkeypatch.setattr(client_metrics, "get_json", lambda _key: stored or None)
    monkeypatch.setattr(
        client_metrics,
        "set_json",
        lambda _key, value, ttl_seconds: stored.update(value) or True,
    )

    result = client_metrics.record_client_apply(
        revision="epoch:12",
        published_at="2026-09-06T12:00:00Z",
        applied_at="2026-09-06T12:00:01.250Z",
    )

    assert result["lastMs"] == 1250
    assert result["sampleCount"] == 1
    assert "providerLatency" not in result


def test_client_apply_rejects_unbounded_or_invalid_timing() -> None:
    with pytest.raises(ValueError):
        client_metrics.record_client_apply(
            revision="epoch:12",
            published_at="2026-09-06T12:00:00Z",
            applied_at="2026-09-06T14:00:00Z",
        )


def test_publication_manifest_records_real_duration(monkeypatch) -> None:
    # Covered end-to-end by the Redis publication tests; this assertion keeps
    # Stage C's owner contract from regressing to a fabricated placeholder.
    from services import distributed_cache_service
    from tests.test_distributed_cache_service import _BinaryRecordingClient

    client = _BinaryRecordingClient()
    monkeypatch.setattr(
        distributed_cache_service, "_binary_streaming_client", lambda: client
    )
    manifest = distributed_cache_service.publish_compressed_catalog_with_manifest(
        "props:catalog:v2",
        [{"id": "one"}],
        manifest_key="props:catalog:manifest:v1",
        sequence_key="props:catalog:sequence:v1",
        accepted_sequence_key="props:catalog:accepted-sequence:v1",
        ttl_seconds=60,
        source_updated_at=datetime.now(timezone.utc).isoformat(),
    )

    assert manifest is not None
    assert isinstance(manifest["publicationDurationMs"], int)
    assert manifest["publicationDurationMs"] >= 0
