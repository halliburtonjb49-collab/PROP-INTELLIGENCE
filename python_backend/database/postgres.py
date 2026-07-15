"""Production PostgreSQL connectivity backed by the DATABASE_URL secret."""

import os
from threading import Lock

from psycopg_pool import ConnectionPool

from config import DATABASE_SSLMODE, DATABASE_URL

_pool: ConnectionPool | None = None
_pool_lock = Lock()


def database_is_configured() -> bool:
    """Return whether the deployment supplied a PostgreSQL connection URL."""
    return bool(DATABASE_URL)


def get_database_pool() -> ConnectionPool:
    """Return the lazy shared connection pool without exposing credentials."""
    global _pool

    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL is not configured.")

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
