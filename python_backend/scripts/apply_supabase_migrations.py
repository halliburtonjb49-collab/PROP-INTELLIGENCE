"""Apply the repository's Supabase migrations in a tracked, deterministic order."""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / "python_backend" / ".env")

MIGRATIONS = (
    "supabase_user_tables_and_rls.sql",
    "supabase_owner_role_manager.sql",
    "supabase_add_is_premium_column.sql",
    "supabase_subscription_tiers.sql",
    "supabase_historical_data.sql",
    "supabase_intelligence_features.sql",
    "supabase_operational_pipeline.sql",
)


def main() -> int:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        print("DATABASE_URL is required; no database changes were made.", file=sys.stderr)
        return 2

    sslmode = os.getenv("DATABASE_SSLMODE", "require").strip() or "require"
    with psycopg.connect(database_url, sslmode=sslmode) as connection:
        connection.execute(
            """create table if not exists public.prop_intelligence_schema_migrations (
                filename text primary key,
                checksum text not null,
                applied_at timestamptz not null default now()
            )"""
        )
        connection.commit()

        for filename in MIGRATIONS:
            path = ROOT / filename
            sql = path.read_text(encoding="utf-8")
            checksum = hashlib.sha256(sql.encode("utf-8")).hexdigest()
            existing = connection.execute(
                "select checksum from public.prop_intelligence_schema_migrations where filename = %s",
                (filename,),
            ).fetchone()
            if existing:
                if existing[0] != checksum:
                    raise RuntimeError(
                        f"Previously applied migration changed: {filename}. "
                        "Create a new migration instead of editing deployed SQL."
                    )
                print(f"skip {filename}")
                continue

            print(f"apply {filename}")
            try:
                connection.execute(sql)
                connection.execute(
                    "insert into public.prop_intelligence_schema_migrations(filename, checksum) values (%s, %s)",
                    (filename, checksum),
                )
                connection.commit()
            except Exception:
                connection.rollback()
                raise

    print("Supabase migrations are current.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
