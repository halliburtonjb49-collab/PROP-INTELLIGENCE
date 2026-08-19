from services import distributed_cache_service


class _FailingClient:
    def set(self, *_args, **_kwargs):
        raise TimeoutError("Timeout reading from socket")


class _RecordingClient:
    def __init__(self):
        self.values: dict[str, str] = {}
        self.ttls: dict[str, int] = {}
        self.deleted: list[str] = []

    def set(self, key, value, ex=None):
        self.values[key] = value
        if ex is not None:
            self.ttls[key] = ex

    def scan_iter(self, match=None, count=None):
        prefix = str(match or "").rstrip("*")
        return [key for key in list(self.values) if key.startswith(prefix)]

    def ttl(self, key):
        return self.ttls.get(key, -1)

    def append(self, key, value):
        self.values[key] = self.values.get(key, "") + value

    def expire(self, _key, _ttl):
        return True

    def rename(self, source, destination):
        self.values[destination] = self.values.pop(source)
        if source in self.ttls:
            self.ttls[destination] = self.ttls.pop(source)

    def delete(self, key):
        self.deleted.append(key)
        self.values.pop(key, None)
        self.ttls.pop(key, None)


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


def test_builder_key_carries_its_expiry_from_the_first_write(monkeypatch):
    """A killed publisher must not strand a multi-megabyte key forever.

    The expiry used to be attached only after the final append, so a process
    that died mid-write left a builder key with no TTL. Under the production
    noeviction policy nothing reclaims those, and enough of them exhaust the
    instance until every later write fails.
    """

    client = _RecordingClient()
    monkeypatch.setattr(
        distributed_cache_service, "_streaming_client", lambda: client
    )

    distributed_cache_service.set_json_streaming_list(
        "props:catalog:test", [{"id": "p1"}], ttl_seconds=3600
    )

    assert client.ttls["props:catalog:test"] == 3600


def test_publication_reclaims_builders_left_by_a_killed_process(monkeypatch):
    client = _RecordingClient()
    # A builder with no TTL can only be residue from a process that died
    # before it could finish; a live publication now always carries one.
    client.values["props:catalog:test:building:deadbeef"] = "[{"
    client.values["props:catalog:test:building:inflight"] = "[{"
    client.ttls["props:catalog:test:building:inflight"] = 3600
    monkeypatch.setattr(
        distributed_cache_service, "_streaming_client", lambda: client
    )

    distributed_cache_service.set_json_streaming_list(
        "props:catalog:test", [{"id": "p1"}], ttl_seconds=3600
    )

    assert "props:catalog:test:building:deadbeef" in client.deleted
    assert "props:catalog:test:building:inflight" not in client.deleted


def test_reclaim_failure_never_blocks_the_publication(monkeypatch):
    client = _RecordingClient()
    client.scan_iter = lambda **_kwargs: (_ for _ in ()).throw(
        RuntimeError("scan unsupported")
    )
    monkeypatch.setattr(
        distributed_cache_service, "_streaming_client", lambda: client
    )

    assert distributed_cache_service.set_json_streaming_list(
        "props:catalog:test", [{"id": "p1"}], ttl_seconds=60
    ) is True
