"""Data-free production readiness checks for prediction learning."""

from __future__ import annotations

from database.postgres import database_is_configured, get_database_pool


def model_learning_readiness() -> dict[str, object]:
    """Prove capture, grading, and learning have produced durable records.

    Only booleans and timestamps leave this service so the public synthetic
    monitor can verify production without exposing picks or model metrics.
    """
    if not database_is_configured():
        return {
            "status": "blocked",
            "checks": {"database": False},
            "latestSnapshotAt": None,
            "latestGradedAt": None,
            "latestLearningRunAt": None,
        }

    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """select to_regclass('public.prediction_snapshots') is not null,
                          to_regclass('public.pipeline_runs') is not null"""
            )
            ledger_exists, runs_exist = cursor.fetchone()
            if not ledger_exists:
                return {
                    "status": "blocked",
                    "checks": {"database": True, "predictionLedger": False},
                    "latestSnapshotAt": None,
                    "latestGradedAt": None,
                    "latestLearningRunAt": None,
                }
            cursor.execute(
                """select max(created_at), max(graded_at),
                          count(*) > 0,
                          count(*) filter(where graded_at is not null) > 0,
                          count(*) filter(where graded_at is not null
                            and created_at < event_time - interval '5 minutes') > 0
                     from public.prediction_snapshots"""
            )
            latest_snapshot, latest_graded, captured, graded, valid = cursor.fetchone()
            latest_learning_run = None
            learning_succeeded = False
            if runs_exist:
                cursor.execute(
                    """select started_at, status
                         from public.pipeline_runs
                        where pipeline = 'prop-learning'
                        order by started_at desc limit 1"""
                )
                run = cursor.fetchone()
                if run:
                    latest_learning_run, run_status = run
                    learning_succeeded = str(run_status) == "SUCCEEDED"
    except Exception:
        return {
            "status": "blocked",
            "checks": {"database": True, "query": False},
            "latestSnapshotAt": None,
            "latestGradedAt": None,
            "latestLearningRunAt": None,
        }

    checks = {
        "database": True,
        "predictionLedger": True,
        "captureObserved": bool(captured),
        "gradingObserved": bool(graded),
        "validPregameObserved": bool(valid),
        "learningRunObserved": latest_learning_run is not None,
        "latestLearningRunSucceeded": learning_succeeded,
    }
    return {
        "status": "ready" if all(checks.values()) else "warming",
        "checks": checks,
        "latestSnapshotAt": latest_snapshot.isoformat() if latest_snapshot else None,
        "latestGradedAt": latest_graded.isoformat() if latest_graded else None,
        "latestLearningRunAt": (
            latest_learning_run.isoformat() if latest_learning_run else None
        ),
    }
