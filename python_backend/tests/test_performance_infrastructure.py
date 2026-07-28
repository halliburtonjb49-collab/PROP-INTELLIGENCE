from fastapi.testclient import TestClient

import main
from database.postgres import database_performance_snapshot
from services import distributed_cache_service, job_queue_service


def test_optional_redis_services_fail_open_without_configuration(monkeypatch) -> None:
    monkeypatch.setattr(distributed_cache_service, "REDIS_URL", "")
    distributed_cache_service._client.cache_clear()
    monkeypatch.setattr(job_queue_service, "REDIS_URL", "")

    assert distributed_cache_service.get_json("missing") is None
    assert distributed_cache_service.set_json("key", {"ok": True}, ttl_seconds=10) is False
    assert distributed_cache_service.health()["mode"] == "local"
    assert job_queue_service.enqueue("jobs.run_prop_sync") is None
    assert job_queue_service.health()["mode"] == "in-process"


def test_health_exposes_cache_queue_and_query_performance() -> None:
    response = TestClient(main.app).get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert "cache" in payload
    assert "backgroundQueue" in payload
    assert "ingestionPipeline" in payload
    assert payload["databasePerformance"]["thresholdMs"] >= 1
    assert "recentSlowQueries" in database_performance_snapshot()


def test_queue_uses_explicit_rq_call_arguments(monkeypatch) -> None:
    captured: dict[str, object] = {}

    class FakeJob:
        id = "job-1"

        @staticmethod
        def get_status() -> str:
            return "queued"

    class FakeQueue:
        def enqueue_call(self, **kwargs):
            captured.update(kwargs)
            return FakeJob()

    monkeypatch.setattr(job_queue_service, "_queue", lambda: FakeQueue())

    result = job_queue_service.enqueue(
        "jobs.fetch_sport_raw",
        args=("baseball_mlb",),
        kwargs={"force": True},
        job_id="fetch-1",
    )

    assert result == {
        "id": "job-1",
        "status": "queued",
        "queue": job_queue_service.QUEUE_NAME,
    }
    assert captured["func"] == "jobs.fetch_sport_raw"
    assert captured["args"] == ("baseball_mlb",)
    assert captured["kwargs"] == {"force": True}
    assert captured["timeout"] == 1800


def test_large_responses_support_brotli() -> None:
    response = TestClient(main.app).get(
        "/openapi.json",
        headers={"Accept-Encoding": "br"},
    )

    assert response.status_code == 200
    assert response.headers.get("content-encoding") == "br"
