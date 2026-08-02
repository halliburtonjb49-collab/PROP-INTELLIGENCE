"""Owner-only launch-day control panel aggregation."""

from __future__ import annotations

from datetime import datetime, timezone
import os

from database.postgres import database_is_configured, get_database_pool
from services.acceptance_service import production_acceptance_snapshot
from services.distributed_cache_service import health as cache_health
from services.game_market_service import game_market_health
from services.job_queue_service import health as queue_health
from services.pipeline_run_service import recent_pipeline_runs, summarize_pipeline_health
from services.scoreboard_metrics_service import scoreboard_latency_snapshot
from services.grading_review_service import grading_review_queue
from services.provider_quality_service import provider_quality_score
from services.model_performance_service import model_performance, operations_summary

FAILED_PAYMENT_EVENTS = ("BILLING_ISSUE", "SUBSCRIPTION_PAUSED")


def _database_counts() -> dict[str, object]:
    result: dict[str, object] = {
        "activeUsers": {
            "count": None,
            "windowMinutes": 15,
            "instrumented": False,
            "note": "No recent authenticated API activity has been recorded.",
        },
        "failedLogins": {
            "count": None,
            "windowHours": 24,
            "instrumented": False,
            "note": "Supabase failed-login telemetry is not connected.",
        },
        "failedPayments": {"count": None, "windowHours": 24},
        "unsettledSlips": {"count": None},
    }
    if not database_is_configured():
        return result
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                select count(distinct actor_hash)
                from public.security_events
                where occurred_at >= now() - interval '15 minutes'
                  and actor_hash is not null
                  and event_type = 'protected_feature_access'
                """
            )
            result["activeUsers"] = {
                "count": int(cursor.fetchone()[0] or 0),
                "windowMinutes": 15,
                "instrumented": True,
                "note": "Distinct users observed on protected API features.",
            }
            cursor.execute(
                """
                select count(*)
                from public.security_events
                where occurred_at >= now() - interval '24 hours'
                  and event_type = 'subscription_event_applied'
                  and upper(coalesce(metadata->>'eventType', '')) = any(%s)
                """,
                (list(FAILED_PAYMENT_EVENTS),),
            )
            result["failedPayments"] = {
                "count": int(cursor.fetchone()[0] or 0),
                "windowHours": 24,
            }
            cursor.execute("select count(*) from public.slips where status = 'active'")
            result["unsettledSlips"] = {"count": int(cursor.fetchone()[0] or 0)}
    except Exception as exc:
        result["databaseError"] = type(exc).__name__
    return result


def launch_control_snapshot() -> dict[str, object]:
    acceptance = production_acceptance_snapshot()
    runs = recent_pipeline_runs(25)
    pipeline_health = summarize_pipeline_health(runs)
    cache = cache_health()
    queue = queue_health()
    market = game_market_health()
    database_counts = _database_counts()
    provider_errors = int(market.get("errors") or 0) + sum(
        len(run.get("errors") or [])
        for run in pipeline_health["activeFailures"]
        if isinstance(run, dict)
    )
    provider_score = provider_quality_score(
        success_rate=float(market.get("successRate") or 0),
        freshness_score=1.0 if market.get("status") == "ok" else 0.4,
        completeness_score=0.0 if market.get("latestEmpty") else 1.0,
    )
    try:
        grading_review = grading_review_queue()
    except Exception as exc:
        grading_review = {
            "count": None,
            "unsettledCount": None,
            "questionableCount": None,
            "error": type(exc).__name__,
        }
    try:
        performance = model_performance()
        prediction_operations = operations_summary()
    except Exception as exc:
        performance = {
            "sampleSize": 0,
            "segments": [],
            "error": type(exc).__name__,
        }
        prediction_operations = {
            "databaseConfigured": database_is_configured(),
            "error": type(exc).__name__,
        }
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "api": {
            "status": "ok",
            "version": os.getenv(
                "RENDER_GIT_COMMIT",
                os.getenv("APP_VERSION", "unknown"),
            ),
        },
        "redis": cache,
        "workers": queue,
        "pipelines": {
            **pipeline_health,
            "recentRuns": runs,
        },
        "providers": {
            "status": market.get("status", "not_checked"),
            "errors": provider_errors,
            "remainingQuota": acceptance["providerQuota"].get("remaining"),
            "lowQuota": acceptance["providerQuota"].get("lowQuota"),
            "qualityScore": provider_score,
        },
        "propFreshness": acceptance["propFeed"],
        "scoreboardLatency": scoreboard_latency_snapshot(),
        "gradingReview": grading_review,
        "modelPerformance": performance,
        "predictionOperations": prediction_operations,
        **database_counts,
    }
