import logging
from pathlib import Path

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


def test_health_is_basic_liveness_only() -> None:
    response = TestClient(main.app).get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert "cache" not in payload
    assert "database" not in payload
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


def test_queue_logs_enqueue_failures(monkeypatch, caplog) -> None:
    class BrokenQueue:
        @staticmethod
        def enqueue_call(**_kwargs):
            raise RuntimeError("credential unavailable")

    monkeypatch.setattr(job_queue_service, "_queue", lambda: BrokenQueue())

    with caplog.at_level(logging.WARNING):
        result = job_queue_service.enqueue(
            "jobs.run_prop_sync",
            job_id="freshness-1",
        )

    assert result is None
    assert "Unable to enqueue background job" in caplog.text
    assert "jobs.run_prop_sync" in caplog.text
    assert "freshness-1" in caplog.text
    assert "credential unavailable" in caplog.text


def test_worker_blueprint_validates_config_without_forking_sync_jobs() -> None:
    blueprint = (Path(__file__).parents[2] / "render.yaml").read_text(
        encoding="utf-8"
    )

    assert "python -c \"import main\"" in blueprint
    assert "-w rq.worker.SimpleWorker" in blueprint


def test_large_responses_support_brotli() -> None:
    response = TestClient(main.app).get(
        "/openapi.json",
        headers={"Accept-Encoding": "br"},
    )

    assert response.status_code == 200
    assert response.headers.get("content-encoding") == "br"


class _StreamingRedis:
    def __init__(self) -> None:
        self.values = {"catalog": "[{\"old\":true}]"}
        self.append_calls = 0
        self.previous_visible_at_rename = False

    def set(self, key, value):
        self.values[key] = value

    def append(self, key, value):
        self.append_calls += 1
        self.values[key] += value

    def expire(self, _key, _ttl):
        return True

    def rename(self, source, destination):
        self.previous_visible_at_rename = self.values[destination] == "[{\"old\":true}]"
        self.values[destination] = self.values.pop(source)

    def delete(self, key):
        self.values.pop(key, None)


def test_large_json_list_is_published_in_bounded_atomic_chunks(monkeypatch) -> None:
    client = _StreamingRedis()
    monkeypatch.setattr(distributed_cache_service, "_client", lambda: client)

    published = distributed_cache_service.set_json_streaming_list(
        "catalog",
        ({"id": index, "name": "x" * 20} for index in range(5)),
        ttl_seconds=60,
        chunk_chars=30,
    )

    assert published is True
    assert client.previous_visible_at_rename is True
    assert client.append_calls > 2
    assert distributed_cache_service.json.loads(client.values["catalog"]) == [
        {"id": index, "name": "x" * 20} for index in range(5)
    ]


def test_streaming_publish_preserves_previous_value_on_failure(monkeypatch) -> None:
    client = _StreamingRedis()
    client.append = lambda *_args: (_ for _ in ()).throw(RuntimeError("oom"))
    monkeypatch.setattr(distributed_cache_service, "_client", lambda: client)

    published = distributed_cache_service.set_json_streaming_list(
        "catalog", [{"id": 1}], ttl_seconds=60
    )

    assert published is False
    assert client.values["catalog"] == "[{\"old\":true}]"
