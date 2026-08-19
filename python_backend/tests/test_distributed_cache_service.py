from services import distributed_cache_service


class _FailingClient:
    def set(self, *_args, **_kwargs):
        raise TimeoutError("Timeout reading from socket")


class _RecordingClient:
    def __init__(self):
        self.values: dict[str, str] = {}

    def set(self, key, value):
        self.values[key] = value

    def append(self, key, value):
        self.values[key] = self.values.get(key, "") + value

    def expire(self, _key, _ttl):
        return True

    def rename(self, source, destination):
        self.values[destination] = self.values.pop(source)

    def delete(self, key):
        self.values.pop(key, None)


def test_streaming_publication_records_why_it_failed(monkeypatch):
    """The boolean return stranded the real cause in a warning line.

    Catalog publication failures surfaced to the cron as "could not be
    published to Redis" with nothing to act on; the timeout or out-of-memory
    that actually caused it lived only in the API's own log stream.
    """

    monkeypatch.setattr(
        distributed_cache_service, "_streaming_client", lambda: _FailingClient()
    )

    published = distributed_cache_service.set_json_streaming_list(
        "props:catalog:test", [{"id": "p1"}], ttl_seconds=60
    )

    assert published is False
    assert "Timeout reading from socket" in (
        distributed_cache_service.last_write_error("props:catalog:test")
    )


def test_successful_publication_clears_the_previous_failure(monkeypatch):
    client = _RecordingClient()
    monkeypatch.setattr(
        distributed_cache_service, "_streaming_client", lambda: client
    )
    distributed_cache_service._LAST_WRITE_ERROR["props:catalog:test"] = "stale"

    published = distributed_cache_service.set_json_streaming_list(
        "props:catalog:test",
        [{"id": "p1"}, {"id": "p2"}],
        ttl_seconds=60,
    )

    assert published is True
    assert client.values["props:catalog:test"] == '[{"id":"p1"},{"id":"p2"}]'
    assert distributed_cache_service.last_write_error("props:catalog:test") == ""


def test_missing_redis_url_is_reported_as_the_cause(monkeypatch):
    monkeypatch.setattr(distributed_cache_service, "_streaming_client", lambda: None)

    published = distributed_cache_service.set_json_streaming_list(
        "props:catalog:test", [{"id": "p1"}], ttl_seconds=60
    )

    assert published is False
    assert distributed_cache_service.last_write_error("props:catalog:test") == (
        "REDIS_URL is not configured"
    )
