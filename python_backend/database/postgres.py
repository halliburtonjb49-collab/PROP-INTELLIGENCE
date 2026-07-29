"""Production PostgreSQL connectivity backed by the DATABASE_URL secret."""

import os
import logging
import time
from collections import deque
from threading import Lock

from psycopg import Cursor
from psycopg_pool import ConnectionPool

from config import DATABASE_SSLMODE, DATABASE_URL

_pool: ConnectionPool | None = None
_pool_lock = Lock()
_slow_queries: deque[dict[str, object]] = deque(maxlen=50)
_slow_query_lock = Lock()
_slow_query_ms = max(1, int(os.getenv("SLOW_QUERY_MS", "250")))
LOGGER = logging.getLogger(__name__)


class ProfilingCursor(Cursor):
    """Record slow SQL without logging parameters or user data."""

    def execute(self, query, params=None, *, prepare=None, binary=None):
        started = time.perf_counter()
        try:
            return super().execute(
                query,
                params,
                prepare=prepare,
                binary=binary,
            )
        finally:
            duration_ms = int((time.perf_counter() - started) * 1000)
            if duration_ms >= _slow_query_ms:
                statement = " ".join(str(query).split())[:180]
                item = {
                    "durationMs": duration_ms,
                    "recordedAt": time.time(),
                }
                with _slow_query_lock:
                    _slow_queries.append(item)
                LOGGER.warning(
                    "Slow database query duration_ms=%s statement=%s",
                    duration_ms,
                    statement,
                )


def database_performance_snapshot() -> dict[str, object]:
    with _slow_query_lock:
        rows = list(_slow_queries)
    return {
        "thresholdMs": _slow_query_ms,
        "slowQueryCount": len(rows),
        "recentSlowQueries": rows[-10:],
    }


def database_is_configured() -> bool:
    """Return whether the deployment supplied a PostgreSQL connection URL."""
    return bool(DATABASE_URL)


def get_database_pool() -> ConnectionPool:
    """Return the lazy shared connection pool without exposing credentials."""
    global _pool

    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL is not configured.")
    if DATABASE_SSLMODE.lower() not in {"require", "verify-ca", "verify-full"}:
        raise RuntimeError(
            "DATABASE_SSLMODE must enforce TLS in every environment."
        )

    with _pool_lock:
        if _pool is None:
            max_size = max(1, int(os.getenv("DATABASE_POOL_SIZE", "5")))
            _pool = ConnectionPool(
                conninfo=DATABASE_URL,
                min_size=0,
                max_size=max_size,
                open=True,
                kwargs={
                    "sslmode": DATABASE_SSLMODE,
                    "connect_timeout": 10,
                    "application_name": "prop-intelligence-api",
                    "cursor_factory": ProfilingCursor,
                },
            )
        return _pool


def check_database_connection() -> None:
    """Execute a minimal query for deployment health checks."""
    with get_database_pool().connection(timeout=10) as connection:
        with connection.cursor() as cursor:
            cursor.execute("select 1")
            result = cursor.fetchone()
            if result != (1,):
                raise RuntimeError("Unexpected PostgreSQL health response.")


def close_database_pool() -> None:
    """Close pooled connections during application shutdown."""
    global _pool

    with _pool_lock:
        if _pool is not None:
            _pool.close()
            _pool = None
