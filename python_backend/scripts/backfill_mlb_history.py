"""Backfill the rolling MLB history required by the baseline projection model."""

import argparse
import json
import logging
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.historical_ingestion_service import run_mlb_historical_backfill


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=21)
    parser.add_argument("--end-date", type=date.fromisoformat)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    result = run_mlb_historical_backfill(
        end_date=args.end_date,
        days=max(1, args.days),
    )
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
