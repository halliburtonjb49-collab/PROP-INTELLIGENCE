import os
import asyncio
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import main


def test_startup_recovery_skips_sync_when_props_exist(monkeypatch):
    fresh = SimpleNamespace(lastUpdatedUtc=datetime.now(timezone.utc).isoformat())
    monkeypatch.setattr(main, "get_props", lambda: [fresh])
    called = False

    def unexpected_sync():
        nonlocal called
        called = True

    monkeypatch.setattr(main, "_enqueue_prop_refresh", unexpected_sync)

    asyncio.run(main._ensure_props_available())

    assert called is False


def test_startup_recovery_queues_empty_cache_without_running_sync(monkeypatch):
    monkeypatch.setattr(main, "get_props", lambda: [])
    queued = []
    monkeypatch.setattr(
        main,
        "_enqueue_prop_refresh",
        lambda: queued.append("worker") or {"id": "refresh-1"},
    )
    monkeypatch.setattr(main, "job_queue_health", lambda: {"workers": 1})

    asyncio.run(main._ensure_props_available())

    assert queued == ["worker"]


def test_startup_recovery_queues_stale_cache_without_blocking(monkeypatch):
    stale = SimpleNamespace(
        lastUpdatedUtc=(
            datetime.now(timezone.utc) - timedelta(hours=2)
        ).isoformat()
    )
    monkeypatch.setattr(main, "get_props", lambda: [stale])
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "45")
    queued = []
    monkeypatch.setattr(
        main,
        "_enqueue_prop_refresh",
        lambda: queued.append("worker") or {"id": "refresh-1"},
    )
    monkeypatch.setattr(main, "job_queue_health", lambda: {"workers": 1})

    asyncio.run(main._ensure_props_available())

    assert queued == ["worker"]


def test_startup_recovery_falls_back_once_without_an_active_worker(monkeypatch):
    props = []
    monkeypatch.setattr(main, "get_props", lambda: props)
    monkeypatch.setattr(main, "_enqueue_prop_refresh", lambda: {"id": "queued"})
    monkeypatch.setattr(main, "job_queue_health", lambda: {"workers": 0})

    def recover():
        props.append(
            SimpleNamespace(
                lastUpdatedUtc=datetime.now(timezone.utc).isoformat(),
                model_dump=lambda **_: {"id": "recovered"},
            )
        )
        main._sync_run_lock.release()

    monkeypatch.setattr(main, "_run_sync_background", recover)
    monkeypatch.setattr(main, "_cached_prop_catalog", lambda: props)
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda _rows: True)

    asyncio.run(main._ensure_props_available())

    assert len(props) == 1


def test_prop_cache_without_update_timestamp_requires_refresh():
    assert main._prop_cache_needs_refresh(
        [SimpleNamespace(lastUpdatedUtc="")]
    )


def test_watchdog_refreshes_well_before_the_deploy_gate_rejects(monkeypatch) -> None:
    """The refresh policy must be able to satisfy the gate that checks it.

    These lived in two files with independently chosen numbers: the watchdog
    let the feed reach 180 minutes while the deploy smoke check failed at 45,
    so deploys failed on staleness the system was configured to allow.
    """

    import sys
    from pathlib import Path

    tools = Path(__file__).resolve().parents[2] / "tools"
    sys.path.insert(0, str(tools))
    try:
        import post_deploy_smoke
    finally:
        sys.path.remove(str(tools))

    monkeypatch.delenv("PROP_FEED_REFRESH_AFTER_MINUTES", raising=False)
    refresh_after = max(5, int(os.getenv("PROP_FEED_REFRESH_AFTER_MINUTES", "30")))

    assert refresh_after < post_deploy_smoke.MAX_PROP_FEED_AGE_MINUTES
    # The gate must also cover the queueing delay, not just the trigger point.
    assert post_deploy_smoke.MAX_PROP_FEED_AGE_MINUTES >= (
        refresh_after + post_deploy_smoke.PROP_FEED_REFRESH_DEDUPE_MINUTES
    )


def test_refresh_trigger_is_independent_of_the_health_alarm(monkeypatch) -> None:
    # Production sets PROP_FEED_STALE_MINUTES=180 to quiet the health report.
    # That must not push the refresh trigger out to three hours with it.
    monkeypatch.setenv("PROP_FEED_STALE_MINUTES", "180")
    monkeypatch.delenv("PROP_FEED_REFRESH_AFTER_MINUTES", raising=False)

    stale_prop = SimpleNamespace(
        lastUpdatedUtc=(
            datetime.now(timezone.utc) - timedelta(minutes=60)
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    assert main._prop_cache_needs_refresh([stale_prop]) is True


def test_a_fresh_local_sync_persists_the_durable_snapshot(monkeypatch):
    """The snapshot must not depend on Redis being reachable.

    It was previously written only by the worker job and by the branch that
    reads the catalog back out of Redis. Both need Redis, so while it was
    down nothing persisted anything: an instance would sync fresh props, hold
    them in memory, and revert to an hours-old snapshot on its next restart.
    """

    saved = []
    prop = SimpleNamespace(
        lastUpdatedUtc=datetime.now(timezone.utc).isoformat(),
        model_dump=lambda mode=None: {"id": "p1"},
    )

    monkeypatch.setattr(main, "get_props", lambda: [prop])
    monkeypatch.setattr(main, "set_distributed_json", lambda *a, **k: True)
    monkeypatch.setattr(main, "_publish_prop_catalog_summary", lambda _props: None)
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda rows: saved.append(rows))

    # Persisting happens on a daemon thread; run it inline so the test is
    # deterministic rather than timing-dependent.
    class _Inline:
        def __init__(self, target=None, args=(), daemon=None):
            self._target = target
            self._args = args

        def start(self):
            self._target(*self._args)

    monkeypatch.setattr(main, "Thread", _Inline)

    result = main._rebuild_prop_catalog_from_local()

    assert result == [prop]
    assert saved and saved[0] == [{"id": "p1"}]


def test_intermediate_catalog_refresh_does_not_start_snapshot_write(monkeypatch):
    saved = []
    prop = SimpleNamespace(
        lastUpdatedUtc=datetime.now(timezone.utc).isoformat(),
        model_dump=lambda mode=None: {"id": "p1"},
    )
    monkeypatch.setattr(main, "get_props", lambda: [prop])
    monkeypatch.setattr(main, "set_distributed_json", lambda *a, **k: True)
    monkeypatch.setattr(main, "_publish_prop_catalog_summary", lambda _props: None)
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda rows: saved.append(rows))

    main._rebuild_prop_catalog_from_local(persist_snapshot=False)

    assert saved == []


def test_an_empty_sync_does_not_overwrite_a_good_snapshot(monkeypatch):
    saved = []
    monkeypatch.setattr(main, "get_props", lambda: [])
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda rows: saved.append(rows))

    main._rebuild_prop_catalog_from_local()

    # Persisting nothing would replace a working catalog with an empty one.
    assert saved == []


def test_a_failed_snapshot_write_is_recorded_not_swallowed(monkeypatch):
    """A best-effort write that fails silently is undiagnosable.

    The snapshot stopped updating for hours and the only trace was a log line
    naming the exception type, which never leaves the process.
    """

    from services import prop_catalog_snapshot_service as snapshots

    monkeypatch.setattr(snapshots, "database_is_configured", lambda: True)

    class _Boom:
        def connection(self, timeout=None):
            raise RuntimeError("pool exhausted")

    monkeypatch.setattr(snapshots, "get_database_pool", lambda: _Boom())

    assert snapshots.save_catalog_snapshot([{"id": "a"}]) is False

    status = snapshots.catalog_snapshot_status()
    assert status["succeeded"] is False
    # The message, not just the class name.
    assert "pool exhausted" in status["error"]
    assert status["attemptedAt"] is not None
    assert status["rows"] == 1


def test_a_successful_snapshot_write_is_recorded(monkeypatch):
    from services import prop_catalog_snapshot_service as snapshots

    class _Cursor:
        def execute(self, *_a, **_k):
            return None

        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    class _Connection:
        def cursor(self):
            return _Cursor()

        def __enter__(self):
            return self

        def __exit__(self, *_):
            return False

    class _Pool:
        def connection(self, timeout=None):
            return _Connection()

    monkeypatch.setattr(snapshots, "database_is_configured", lambda: True)
    monkeypatch.setattr(snapshots, "get_database_pool", lambda: _Pool())

    assert snapshots.save_catalog_snapshot([{"id": "a"}, {"id": "b"}]) is True

    status = snapshots.catalog_snapshot_status()
    assert status["succeeded"] is True
    assert status["error"] is None
    assert status["rows"] == 2
    assert status["payloadBytes"] > 0
    assert status["durationMs"] is not None


def test_refusing_to_persist_nothing_is_reported_as_such(monkeypatch):
    from services import prop_catalog_snapshot_service as snapshots

    assert snapshots.save_catalog_snapshot([]) is False
    # Distinguishable from a real failure: an empty sync must never overwrite
    # a good snapshot, and that is a refusal rather than an error.
    assert snapshots.catalog_snapshot_status()["error"] == "no_rows"


def test_reconciliation_writes_when_the_snapshot_is_behind(monkeypatch):
    """Fresh props in memory do not imply a fresh snapshot on disk.

    This is the hole the whole failure fell through: the durable write only
    ever happened as a side effect of the worker job or of reading the catalog
    back out of Redis, so an instance could serve current props for hours
    while the snapshot it would restore from stayed hours behind.
    """

    saved = []
    prop = SimpleNamespace(model_dump=lambda mode=None: {"id": "p1"})
    monkeypatch.setattr(main, "get_props", lambda: [prop])
    monkeypatch.setattr(main, "snapshot_is_behind", lambda _rows: True)
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda rows: saved.append(rows) or True)

    assert main._reconcile_catalog_snapshot() is True
    assert saved == [[{"id": "p1"}]]


def test_reconciliation_does_not_rewrite_a_current_snapshot(monkeypatch):
    saved = []
    prop = SimpleNamespace(model_dump=lambda mode=None: {"id": "p1"})
    monkeypatch.setattr(main, "get_props", lambda: [prop])
    monkeypatch.setattr(main, "snapshot_is_behind", lambda _rows: False)
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda rows: saved.append(rows))

    assert main._reconcile_catalog_snapshot() is False
    # A multi-megabyte write every five minutes for no reason is its own bug.
    assert saved == []


def test_reconciliation_never_persists_an_empty_catalog(monkeypatch):
    saved = []
    monkeypatch.setattr(main, "get_props", lambda: [])
    monkeypatch.setattr(main, "save_catalog_snapshot", lambda rows: saved.append(rows))

    assert main._reconcile_catalog_snapshot() is False
    assert saved == []


def test_reconciliation_failure_does_not_break_the_caller(monkeypatch):
    def _boom():
        raise RuntimeError("database gone")

    monkeypatch.setattr(main, "get_props", _boom)

    # Startup and the watchdog both call this; neither may die because a
    # best-effort snapshot write failed.
    assert main._reconcile_catalog_snapshot() is False
