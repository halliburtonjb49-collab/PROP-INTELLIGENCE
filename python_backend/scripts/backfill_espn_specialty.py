"""Backfill completed ESPN ATP/WTA and PGA statistics."""

from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from providers.espn_specialty_statistics import golf_logs, tennis_logs, ufc_logs  # noqa: E402
from services.historical_ingestion_service import HistoricalRepository  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    days = max(1, min(args.days, 180))
    dates = [date.today() - timedelta(days=offset + 1) for offset in range(days)]
    print(json.dumps({"days": days, "start": min(dates).isoformat(),
                      "end": max(dates).isoformat(), "futureExcluded": True}, indent=2))
    if not args.execute:
        print("Dry run only. Add --execute to ingest completed ESPN statistics.")
        return 0
    with ThreadPoolExecutor(max_workers=4) as executor:
        batches = list(executor.map(
            lambda target: tennis_logs(tour="ATP", target_date=target)
            + tennis_logs(tour="WTA", target_date=target)
            + golf_logs(target_date=target)
            + ufc_logs(target_date=target), dates,
        ))
    rows = [row for batch in batches for row in batch]
    persisted = HistoricalRepository().upsert_player_game_logs(rows)
    by_sport = {sport: sum(row["sport"] == sport for row in rows) for sport in ("TENNIS", "PGA", "UFC")}
    print(json.dumps({"fetched": len(rows), "persisted": persisted,
                      "bySport": by_sport}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
