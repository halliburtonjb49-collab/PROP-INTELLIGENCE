"""Explicit, budget-capped historical prop snapshot backfill."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from config import ODDS_REGIONS  # noqa: E402
from services.historical_odds_service import (  # noqa: E402
    attach_verified_clv, clv_checkpoint_times, historical_credit_cost,
    ingest_historical_event_snapshot,
)


def _instant(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sport", required=True)
    parser.add_argument("--event-id", required=True)
    parser.add_argument("--commence-time", required=True)
    parser.add_argument("--markets", required=True, help="Comma-separated Odds API market keys")
    parser.add_argument("--max-credits", type=int, required=True)
    parser.add_argument("--execute", action="store_true", help="Actually make paid API calls")
    args = parser.parse_args()
    markets = sorted({item.strip() for item in args.markets.split(",") if item.strip()})
    regions = [item.strip() for item in ODDS_REGIONS.split(",") if item.strip()]
    checkpoints = clv_checkpoint_times(_instant(args.commence_time))
    per_call = historical_credit_cost(markets, regions)
    estimated = per_call * len(checkpoints)
    plan = {"eventId": args.event_id, "markets": markets,
            "checkpoints": [item.isoformat() for item in checkpoints],
            "estimatedCredits": estimated, "maxCredits": args.max_credits}
    print(json.dumps(plan, indent=2))
    if estimated > args.max_credits:
        print("Credit cap exceeded; no paid calls were made.", file=sys.stderr)
        return 2
    if not args.execute:
        print("Dry run only. Add --execute to authorize paid historical calls.")
        return 0
    results = [ingest_historical_event_snapshot(
        sport_key=args.sport, event_id=args.event_id, markets=markets, requested_at=instant,
    ) for instant in checkpoints]
    print(json.dumps([{key: value for key, value in row.items() if key != "event"}
                      for row in results], indent=2, default=str))
    print(json.dumps({"verifiedClv": attach_verified_clv(args.event_id)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
