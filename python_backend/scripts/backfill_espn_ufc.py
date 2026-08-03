"""Backfill completed UFC fighter statistics from ESPN."""

from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from providers.espn_specialty_statistics import ufc_logs  # noqa: E402
from services.historical_ingestion_service import HistoricalRepository  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=365)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    days = max(1, min(args.days, 730))
    targets = [date.today() - timedelta(days=offset + 1) for offset in range(days)]
    print(json.dumps({"days": days, "start": min(targets).isoformat(),
                      "end": max(targets).isoformat(), "completedOnly": True}))
    if not args.execute:
        print("Dry run only. Add --execute to ingest completed UFC statistics.")
        return 0
    with ThreadPoolExecutor(max_workers=4) as executor:
        batches = list(executor.map(lambda target: ufc_logs(target_date=target), targets))
    rows = [row for batch in batches for row in batch]
    persisted = HistoricalRepository().upsert_player_game_logs(rows)
    print(json.dumps({"fetched": len(rows), "persisted": persisted,
                      "fighters": len({row['player_id'] for row in rows}),
                      "fights": len({row['event_id'] for row in rows})}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
