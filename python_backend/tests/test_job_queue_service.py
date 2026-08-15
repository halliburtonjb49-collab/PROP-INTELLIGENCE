from services import job_queue_service as queue_service


class _FakeLockRedis:
    value = None

    @classmethod
    def from_url(cls, *_args, **_kwargs):
        return cls()

    def set(self, _key, value, *, nx, ex):
        assert nx is True
        assert ex == queue_service.SYNC_LOCK_TTL_SECONDS
        if type(self).value is not None:
            return False
        type(self).value = value
        return True

    def eval(self, _script, _keys, _key, token):
        if type(self).value == token:
            type(self).value = None
            return 1
        return 0


def test_global_sync_lock_prevents_overlapping_workers(monkeypatch) -> None:
    _FakeLockRedis.value = None
    monkeypatch.setattr(queue_service, "REDIS_URL", "redis://example")
    monkeypatch.setattr(queue_service, "Redis", _FakeLockRedis)

    owner = queue_service.acquire_global_sync_lock()
    assert owner
    assert queue_service.acquire_global_sync_lock() is None

    queue_service.release_global_sync_lock("not-the-owner")
    assert queue_service.acquire_global_sync_lock() is None

    queue_service.release_global_sync_lock(owner)
    assert queue_service.acquire_global_sync_lock()


class _Status:
    value = "queued"


class _ExistingJob:
    id = "prop-freshness-release-123"

    def get_status(self, *, refresh=False):
        assert refresh is True
        return _Status()


class _DuplicateQueue:
    def enqueue_call(self, **_kwargs):
        raise RuntimeError("job already exists")

    def fetch_job(self, job_id):
        assert job_id == _ExistingJob.id
        return _ExistingJob()


def test_enqueue_returns_existing_deduplicated_job(monkeypatch) -> None:
    monkeypatch.setattr(queue_service, "_queue", lambda: _DuplicateQueue())

    result = queue_service.enqueue(
        "jobs.run_prop_sync",
        job_id="prop-freshness:release:123",
    )

    assert result == {
        "id": _ExistingJob.id,
        "status": "queued",
        "queue": queue_service.QUEUE_NAME,
        "deduplicated": True,
    }


class _QueuedJob:
    id = "headshots-espn-456"

    def get_status(self):
        return "queued"


class _CaptureQueue:
    received = None

    def enqueue_call(self, **kwargs):
        type(self).received = kwargs
        return _QueuedJob()


def test_enqueue_normalizes_rq_reserved_colons(monkeypatch) -> None:
    _CaptureQueue.received = None
    monkeypatch.setattr(queue_service, "_queue", lambda: _CaptureQueue())

    result = queue_service.enqueue(
        "jobs.refresh_espn_headshots",
        job_id="headshots:espn:456",
    )

    assert _CaptureQueue.received["job_id"] == "headshots-espn-456"
    assert result["id"] == "headshots-espn-456"
    assert result["status"] == "queued"
