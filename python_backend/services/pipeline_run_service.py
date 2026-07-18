"""Persistent operational telemetry for scheduled production pipelines."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from time import perf_counter
from uuid import UUID

from database.postgres import database_is_configured, get_database_pool
from services.operations_notification_service import notify_pipeline_issue


def start_pipeline_run(pipeline: str) -> tuple[UUID | None, float]:
    started = perf_counter()
    if not database_is_configured():
        return None, started
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            "insert into pipeline_runs(pipeline,status) values(%s,'RUNNING') returning id",
            (pipeline,),
        )
        identifier = cursor.fetchone()[0]
        connection.commit()
    return identifier, started


def finish_pipeline_run(
    identifier: UUID | None,
    started: float,
    *,
    metrics: dict[str, object],
    errors: list[dict[str, object]],
) -> dict[str, object]:
    duration_ms = int((perf_counter() - started) * 1000)
    status = "PARTIAL" if errors else "SUCCEEDED"
    pipeline = "unknown"
    if identifier is not None:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute("select pipeline from pipeline_runs where id=%s", (identifier,))
            row = cursor.fetchone()
            if row:
                pipeline = str(row[0])
            cursor.execute(
                """update pipeline_runs set status=%s,finished_at=now(),duration_ms=%s,
                   metrics=%s::jsonb,errors=%s::jsonb where id=%s""",
                (status, duration_ms, json.dumps(metrics, default=str),
                 json.dumps(errors, default=str), identifier),
            )
            connection.commit()
    notified = notify_pipeline_issue(pipeline, status, errors)
    return {"id": str(identifier) if identifier else None, "status": status,
            "durationMs": duration_ms, "metrics": metrics, "errors": errors,
            "alertNotified": notified,
            "finishedAt": datetime.now(timezone.utc).isoformat()}


def recent_pipeline_runs(limit: int = 25) -> list[dict[str, object]]:
    if not database_is_configured():
        return []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select id,pipeline,status,started_at,finished_at,duration_ms,metrics,errors
               from pipeline_runs order by started_at desc limit %s""", (limit,),
        )
        return [{"id": str(row[0]), "pipeline": row[1], "status": row[2],
                 "startedAt": row[3].isoformat(),
                 "finishedAt": row[4].isoformat() if row[4] else None,
                 "durationMs": row[5], "metrics": row[6], "errors": row[7]}
                for row in cursor.fetchall()]
