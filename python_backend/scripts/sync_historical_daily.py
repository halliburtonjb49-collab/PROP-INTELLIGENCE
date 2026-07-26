"""Memory-bounded coordinator for the daily historical-data cron."""

import argparse
import os
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", type=date.fromisoformat)
    parser.add_argument("--season")
    parser.add_argument(
        "--mlb-backfill-days",
        type=int,
        default=max(1, int(os.getenv("HISTORICAL_MLB_LOOKBACK_DAYS", "120"))),
    )
    parser.add_argument("--mlb-chunk-days", type=int, default=7)
    args = parser.parse_args()

    scripts = Path(__file__).resolve().parent
    end = args.date or (date.today() - timedelta(days=1))
    start = end - timedelta(days=max(1, args.mlb_backfill_days) - 1)
    chunk_days = max(1, min(args.mlb_chunk_days, 14))
    chunk_start = start

    # This coordinator intentionally imports no pandas, pybaseball, nba_api,
    # or application services. Render measures the whole process group against
    # 512 MiB, so only one data-heavy child may exist at a time.
    while chunk_start <= end:
        chunk_end = min(
            end,
            chunk_start + timedelta(days=chunk_days - 1),
        )
        subprocess.run(
            [
                sys.executable,
                str(scripts / "sync_mlb_statcast_chunk.py"),
                "--start-date",
                chunk_start.isoformat(),
                "--end-date",
                chunk_end.isoformat(),
            ],
            check=True,
        )
        chunk_start = chunk_end + timedelta(days=1)

    other_command = [
        sys.executable,
        str(scripts / "sync_other_historical_daily.py"),
    ]
    if args.date is not None:
        other_command.extend(["--date", args.date.isoformat()])
    if args.season:
        other_command.extend(["--season", args.season])
    return subprocess.run(other_command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
