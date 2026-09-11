from services import job_queue_service as queue_service


def test_superseded_pending_jobs_are_removed(monkeypatch) -> None:
    class Job:
        def __init__(self, job_id, release):
            self.id = job_id
            self.meta = {"release": release}
            self.cancelled = False
            self.deleted = False

        def cancel(self):
            self.cancelled = True

        def delete(self):
            self.deleted = True

    old_queued = Job("old-queued", "old-release")
    active = Job("active", "new-release")
    old_retry = Job("old-retry", "old-release")

    class Queue:
        def __init__(self, *_args, **_kwargs):
            self.name = queue_service.QUEUE_NAME

        def get_jobs(self):
            return [old_queued, active]

        def fetch_job(self, job_id):
            return old_retry if job_id == old_retry.id else None

    class Registry:
        def __init__(self, *_args, **_kwargs):
            pass

        def get_job_ids(self):
            return [old_retry.id]

    monkeypatch.setattr(queue_service, "Queue", Queue)
    monkeypatch.setattr(queue_service, "ScheduledJobRegistry", Registry)
    monkeypatch.setattr(queue_service, "DeferredJobRegistry", Registry)

    removed = queue_service._remove_superseded_pending_jobs(
        object(),
        "new-release",
    )

    assert removed == 2
    assert old_queued.cancelled and old_queued.deleted
    assert old_retry.cancelled and old_retry.deleted
    assert not active.cancelled and not active.deleted


def test_job_release_fence_rejects_superseded_job(monkeypatch) -> None:
    class Connection:
        def get(self, _key):
            return b"new-release"

    class Job:
        id = "old-job"
        meta = {"release": "old-release"}
        connection = Connection()

    monkeypatch.setattr(queue_service, "REDIS_URL", "redis://configured")
    assert queue_service.job_matches_active_release(Job()) is False


def test_job_release_fence_accepts_active_job(monkeypatch) -> None:
    class Connection:
        def get(self, _key):
            return b"active-release"

    class Job:
        id = "current-job"
        meta = {"release": "active-release"}
        connection = Connection()

    monkeypatch.setattr(queue_service, "REDIS_URL", "redis://configured")
    assert queue_service.job_matches_active_release(Job()) is True


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

    def eval(self, _script, _keys, _key, token, *args):
        if args:
            assert args == (queue_service.SYNC_LOCK_TTL_SECONDS,)
            return int(type(self).value == token)
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


def test_global_sync_lock_renews_only_for_owner(monkeypatch) -> None:
    _FakeLockRedis.value = None
    monkeypatch.setattr(queue_service, "REDIS_URL", "redis://example")
    monkeypatch.setattr(queue_service, "Redis", _FakeLockRedis)

    owner = queue_service.acquire_global_sync_lock()
    assert queue_service.refresh_global_sync_lock(owner) is True
    assert queue_service.refresh_global_sync_lock("not-the-owner") is False


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
    assert _CaptureQueue.received["timeout"] == queue_service.BACKGROUND_JOB_TIMEOUT_SECONDS


class _StartedJob:
    id = "prop-request-release-456"

    def get_status(self, *, refresh=False):
        assert refresh is True
        return type("_StartedStatus", (), {"value": "started"})()


class _StatusQueue:
    def fetch_job(self, job_id):
        assert job_id == _StartedJob.id
        return _StartedJob()


def test_job_status_looks_up_exact_normalized_job(monkeypatch) -> None:
    monkeypatch.setattr(queue_service, "_queue", lambda: _StatusQueue())

    result = queue_service.job_status("prop-request:release:456")

    assert result["found"] is True
    assert result["id"] == _StartedJob.id
    assert result["status"] == "started"
