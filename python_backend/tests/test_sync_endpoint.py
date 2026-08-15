from datetime import datetime, timedelta, timezone

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
		lambda: {
			"status": "running",
			"queuedJobId": "active-job",
			"startedAt": datetime.now(timezone.utc).isoformat(),
		},
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
        "deduplicated": True,
    }
    assert enqueue_calls == []


def test_requested_sync_recovers_orphaned_shared_state(monkeypatch) -> None:
	state_updates = []
	started_at = datetime.now(timezone.utc) - timedelta(minutes=5)
	monkeypatch.setattr(
		main,
		"_sync_state_snapshot",
		lambda: {
			"status": "running",
			"startedAt": started_at.isoformat(),
		},
	)
	monkeypatch.setattr(
		main,
		"job_queue_health",
		lambda: {"queued": 0, "started": 0, "workers": 1},
	)
	monkeypatch.setattr(
		main,
		"enqueue_background_job",
		lambda *_args, **_kwargs: {"id": "recovery-job", "status": "queued"},
	)
	monkeypatch.setattr(
		main,
		"_set_sync_state",
		lambda **changes: state_updates.append(changes),
	)

	queued = main._enqueue_requested_prop_sync()

	assert queued["id"] == "recovery-job"
	assert state_updates[0]["queuedJobId"] == "recovery-job"
	assert state_updates[0]["status"] == "queued"


def test_requested_sync_recovers_when_exact_job_is_missing_despite_other_started_jobs(
    monkeypatch,
) -> None:
    state_updates = []
    started_at = datetime.now(timezone.utc) - timedelta(minutes=5)
    monkeypatch.setattr(
        main,
        "_sync_state_snapshot",
        lambda: {
            "status": "running",
            "queuedJobId": "missing-job",
            "startedAt": started_at.isoformat(),
            "jobHeartbeatAt": started_at.isoformat(),
        },
    )
    monkeypatch.setattr(
        main,
        "background_job_status",
        lambda _job_id: {
            "available": True,
            "found": False,
            "id": "missing-job",
        },
    )
    # This is the production regression: unrelated stale started jobs must not
    # make the missing exact job look alive.
    monkeypatch.setattr(
        main,
        "job_queue_health",
        lambda: {"queued": 0, "started": 12, "workers": 13},
    )
    monkeypatch.setattr(
        main,
        "enqueue_background_job",
        lambda *_args, **_kwargs: {"id": "replacement-job", "status": "queued"},
    )
    monkeypatch.setattr(
        main,
        "_set_sync_state",
        lambda **changes: state_updates.append(changes),
    )

    queued = main._enqueue_requested_prop_sync()

    assert queued["id"] == "replacement-job"
    assert state_updates[0]["queuedJobId"] == "replacement-job"


def test_requested_sync_keeps_exact_started_job_with_fresh_heartbeat(
    monkeypatch,
) -> None:
    started_at = datetime.now(timezone.utc) - timedelta(minutes=5)
    heartbeat_at = datetime.now(timezone.utc) - timedelta(seconds=15)
    monkeypatch.setattr(
        main,
        "_sync_state_snapshot",
        lambda: {
            "status": "running",
            "queuedJobId": "healthy-job",
            "startedAt": started_at.isoformat(),
            "jobHeartbeatAt": heartbeat_at.isoformat(),
        },
    )
    monkeypatch.setattr(
        main,
        "background_job_status",
        lambda _job_id: {
            "available": True,
            "found": True,
            "id": "healthy-job",
            "status": "started",
        },
    )
    enqueue_calls = []
    monkeypatch.setattr(
        main,
        "enqueue_background_job",
        lambda *_args, **_kwargs: enqueue_calls.append(True),
    )

    queued = main._enqueue_requested_prop_sync()

    assert queued == {
        "id": "healthy-job",
        "status": "running",
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
    monkeypatch.setattr(main, "_invalidate_prop_catalog", lambda **_kwargs: None)
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
