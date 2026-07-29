"""Create a PostgreSQL backup and restore it into an explicitly separate test DB."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit


def _database_identity(url: str) -> tuple[str, int | None, str]:
    parsed = urlsplit(url)
    return (
        (parsed.hostname or "").lower(),
        parsed.port,
        parsed.path.rstrip("/").lower(),
    )


def main() -> int:
    source = os.getenv("DATABASE_URL", "").strip()
    restore = os.getenv("RESTORE_DATABASE_URL", "").strip()
    if not source or not restore:
        print(
            "DATABASE_URL and RESTORE_DATABASE_URL are required.",
            file=sys.stderr,
        )
        return 2
    if os.getenv("ALLOW_RESTORE_TEST", "") != "YES":
        print(
            "Set ALLOW_RESTORE_TEST=YES only after confirming the restore "
            "target is disposable.",
            file=sys.stderr,
        )
        return 2
    if _database_identity(source) == _database_identity(restore):
        print("Refusing to restore into the source database.", file=sys.stderr)
        return 2
    for command in ("pg_dump", "pg_restore", "psql"):
        if shutil.which(command) is None:
            print(f"{command} is required.", file=sys.stderr)
            return 2

    with tempfile.TemporaryDirectory(prefix="prop-intelligence-restore-") as temp:
        backup = Path(temp) / "production.dump"
        subprocess.run(
            [
                "pg_dump",
                "--format=custom",
                "--no-owner",
                "--no-acl",
                "--file",
                str(backup),
                source,
            ],
            check=True,
        )
        subprocess.run(
            [
                "pg_restore",
                "--clean",
                "--if-exists",
                "--no-owner",
                "--no-acl",
                "--dbname",
                restore,
                str(backup),
            ],
            check=True,
        )
        subprocess.run(
            [
                "psql",
                restore,
                "--set",
                "ON_ERROR_STOP=1",
                "--command",
                (
                    "select count(*) as restored_public_tables "
                    "from pg_tables where schemaname = 'public';"
                ),
            ],
            check=True,
        )
    print("Backup restoration test completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
