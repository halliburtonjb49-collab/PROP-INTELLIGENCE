"""Fetch and persist one memory-bounded Statcast date range."""

import argparse
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from providers.historical_data import MlbHistoricalProvider
from services.historical_ingestion_service import (
    HistoricalRepository,
    normalize_statcast,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-date", type=date.fromisoformat, required=True)
    parser.add_argument("--end-date", type=date.fromisoformat, required=True)
    args = parser.parse_args()
    pitches = normalize_statcast(
        MlbHistoricalProvider().statcast(
            start=args.start_date,
            end=args.end_date,
        )
    )
    upserted = HistoricalRepository().upsert_mlb_pitches(pitches)
    print(json.dumps({"fetched": len(pitches), "upserted": upserted}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
