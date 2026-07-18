import argparse
import json
import logging
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.historical_ingestion_service import run_daily_historical_sync


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync free NBA/WNBA/MLB historical data.")
    parser.add_argument("--date", type=date.fromisoformat, help="UTC date in YYYY-MM-DD format")
    parser.add_argument("--season", help="NBA season such as 2025-26")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    result = run_daily_historical_sync(target_date=args.date, season=args.season)
    print(json.dumps(result, indent=2))
    return 1 if all(isinstance(result.get(s), dict) and "error" in result[s] for s in ("NBA", "WNBA", "MLB")) else 0


if __name__ == "__main__":
    raise SystemExit(main())
