import pytest
from fastapi import HTTPException

import main


def test_manual_sync_runs_on_dedicated_worker(monkeypatch) -> None:
    monkeypatch.setattr(main, "_sync_is_fresh", lambda: False)
    monkeypatch.setattr(
        main,
        "_enqueue_requested_prop_sync",
        lambda: {"id": "prop-refresh-1", "status": "queued"},
    )

    payload = main.sync_props()

    assert payload["status"] == "queued"
    assert payload["job"]["id"] == "prop-refresh-1"
    assert "dedicated worker" in payload["message"]


def test_manual_sync_never_falls_back_to_web_process(monkeypatch) -> None:
    monkeypatch.setattr(main, "_sync_is_fresh", lambda: False)
    monkeypatch.setattr(main, "_enqueue_requested_prop_sync", lambda: None)
    ran_in_web = []
    monkeypatch.setattr(
        main,
        "_run_sync_background",
        lambda: ran_in_web.append(True),
    )

    with pytest.raises(HTTPException) as error:
        main.sync_props()

    assert error.value.status_code == 503
    assert ran_in_web == []


def test_requested_sync_publishes_queued_state(monkeypatch) -> None:
    state_updates = []
    monkeypatch.setattr(main, "_sync_state_snapshot", lambda: {"status": "complete"})
    monkeypatch.setattr(
        main,
        "enqueue_background_job",
        lambda *_args, **_kwargs: {"id": "requested-job", "status": "queued"},
    )
    monkeypatch.setattr(main, "_set_sync_state", lambda **changes: state_updates.append(changes))

    queued = main._enqueue_requested_prop_sync()

    assert queued["id"] == "requested-job"
    assert state_updates[0]["status"] == "queued"
    assert state_updates[0]["queuedJobId"] == "requested-job"
    assert state_updates[0]["finishedAt"] is None


def test_requested_sync_deduplicates_active_shared_run(monkeypatch) -> None:
    enqueue_calls = []
    monkeypatch.setattr(
        main,
        "_sync_state_snapshot",
        lambda: {"status": "running", "queuedJobId": "active-job"},
    )
    monkeypatch.setattr(
        main,
        "enqueue_background_job",
        lambda *_args, **_kwargs: enqueue_calls.append(True),
    )

    queued = main._enqueue_requested_prop_sync()

    assert queued == {
        "id": "active-job",
        "status": "running",
        "queue": "prop-intelligence",
        "deduplicated": True,
    }
    assert enqueue_calls == []


def test_primary_lane_completes_before_background_coverage(monkeypatch) -> None:
    observed = {}
    coverage_observed = {}
    provider_observed = {}

    def fake_pipeline(
        fast_callback,
        coverage_callback,
        progress_callback,
        sportsgameodds_started,
        sportsgameodds_complete,
        post_processing_progress,
    ):
        fast_callback([{"sport": "primary", "props": 10}])
        observed.update(main._sync_state_snapshot())
        progress_callback({"currentSport": "coverage", "completedSports": 1, "totalSports": 1})
        coverage_results = [
            {"sport": "primary", "props": 10},
            {"sport": "coverage", "props": 0},
        ]
        coverage_callback(coverage_results)
        coverage_observed.update(main._sync_state_snapshot())
        sportsgameodds_started()
        sportsgameodds_complete({"sport": "sportsgameodds", "events": 1, "props": 4})
        provider_observed.update(main._sync_state_snapshot())
        post_processing_progress("model_recalculation")
        return [
            *coverage_results,
            {"sport": "model_recalculation", "props": 10},
        ]

    monkeypatch.setattr(main, "run_global_sync_pipeline", fake_pipeline)
    refreshes = []
    monkeypatch.setattr(
        main,
        "_refresh_prop_catalog_now",
        lambda **kwargs: refreshes.append(kwargs),
    )
    monkeypatch.setattr(main, "get_props", lambda: [])
    monkeypatch.setattr(main, "capture_closing_lines_from_props", lambda _props: {})
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 1000})
    main._mark_sync_running()

    main._run_sync_background(release_local_lock=False)

    assert observed["status"] == "complete"
    assert observed["coverageStatus"] == "running"
    assert observed["postProcessingStatus"] == "pending"
    assert coverage_observed["coverageStatus"] == "complete"
    assert coverage_observed["postProcessingStatus"] == "pending"
    assert coverage_observed["sportsGameOddsStatus"] == "pending"
    assert provider_observed["sportsGameOddsStatus"] == "complete"
    assert provider_observed["postProcessingStatus"] == "running"
    assert provider_observed["postProcessingStep"] == "catalog_refresh"
    final = main._sync_state_snapshot()
    assert final["status"] == "complete"
    assert final["coverageStatus"] == "complete"
    assert final["sportsGameOddsStatus"] == "complete"
    assert final["postProcessingStatus"] == "complete"
    assert len(final["coverageResults"]) == 2
    assert len(final["results"]) == 3
    assert refreshes == [
        {"persist_snapshot": False},
        {"persist_snapshot": True},
    ]


def test_post_processing_failure_preserves_completed_coverage(monkeypatch) -> None:
    def fake_pipeline(
        fast_callback,
        coverage_callback,
        _progress_callback,
        sportsgameodds_started,
        sportsgameodds_complete,
        post_processing_progress,
    ):
        results = [{"sport": "primary", "props": 10}]
        fast_callback(results)
        coverage_callback(results)
        sportsgameodds_started()
        sportsgameodds_complete({"sport": "sportsgameodds", "events": 1, "props": 4})
        post_processing_progress("model_recalculation")
        raise RuntimeError("model recalculation failed")

    monkeypatch.setattr(main, "run_global_sync_pipeline", fake_pipeline)
    monkeypatch.setattr(main, "_invalidate_prop_catalog", lambda: None)
    monkeypatch.setattr(main, "_refresh_prop_catalog_now", lambda **_kwargs: [])
    monkeypatch.setattr(main, "quota_snapshot", lambda: {"remaining": 1000})
    main._mark_sync_running()

    main._run_sync_background(release_local_lock=False)

    final = main._sync_state_snapshot()
    assert final["status"] == "complete"
    assert final["coverageStatus"] == "complete"
    assert final["sportsGameOddsStatus"] == "complete"
    assert final["coverageError"] is None
    assert final["postProcessingStatus"] == "failed"
    assert final["postProcessingStep"] == "failed"
    assert final["postProcessingError"] == "model recalculation failed"
