from services import job_queue_service as queue_service


class _Status:
    value = "queued"


class _ExistingJob:
    id = "prop-freshness:release:123"

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
        job_id=_ExistingJob.id,
    )

    assert result == {
        "id": _ExistingJob.id,
        "status": "queued",
        "queue": queue_service.QUEUE_NAME,
        "deduplicated": True,
    }