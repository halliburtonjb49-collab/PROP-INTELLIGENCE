"""Memory-bounded coordinator for the daily historical-data cron."""

import argparse
import json
import os
import subprocess
import sys
import time
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
    parser.add_argument("--mlb-chunk-days", type=int, default=1)
    args = parser.parse_args()

    scripts = Path(__file__).resolve().parent
    end = args.date or (date.today() - timedelta(days=1))
    start = end - timedelta(days=max(1, args.mlb_backfill_days) - 1)
    chunk_days = max(1, min(args.mlb_chunk_days, 14))
    chunk_start = start
    failed_chunks: list[dict[str, str]] = []

    # This coordinator intentionally imports no pandas, pybaseball, nba_api,
    # or application services. Render measures the whole process group against
    # 512 MiB, so only one data-heavy child may exist at a time.
    while chunk_start <= end:
        chunk_end = min(
            end,
            chunk_start + timedelta(days=chunk_days - 1),
        )
        command = [
            sys.executable,
            str(scripts / "sync_mlb_statcast_chunk.py"),
            "--start-date",
            chunk_start.isoformat(),
            "--end-date",
            chunk_end.isoformat(),
        ]
        last_error = ""
        for attempt in range(1, 4):
            completed = subprocess.run(command, check=False)
            if completed.returncode == 0:
                last_error = ""
                break
            last_error = f"exit_status_{completed.returncode}"
            if attempt < 3:
                time.sleep(attempt * 3)
        if last_error:
            failed_chunks.append(
                {
                    "startDate": chunk_start.isoformat(),
                    "endDate": chunk_end.isoformat(),
                    "error": last_error,
                }
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
    other_result = subprocess.run(other_command, check=False).returncode
    print(
        json.dumps(
            {
                "mlbBackfill": {
                    "startDate": start.isoformat(),
                    "endDate": end.isoformat(),
                    "failedChunks": failed_chunks,
                },
                "otherStagesExitStatus": other_result,
            }
        )
    )
    return other_result


if __name__ == "__main__":
    raise SystemExit(main())
