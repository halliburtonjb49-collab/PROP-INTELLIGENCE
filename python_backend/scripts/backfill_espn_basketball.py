"""Reconcile completed ESPN box scores into basketball projection history."""

from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from providers.espn_basketball_statistics import EspnBasketballStatisticsProvider  # noqa: E402
from providers.historical_data import NbaHistoricalProvider  # noqa: E402
from services.historical_ingestion_service import (  # noqa: E402
    HistoricalRepository, normalize_basketball_logs, reconcile_basketball_logs,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sport", choices=("NBA", "WNBA"), required=True)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    days = max(1, min(args.days, 180))
    end = date.today() - timedelta(days=1)
    dates = [end - timedelta(days=offset) for offset in range(days)]
    print(json.dumps({"sport": args.sport, "start": min(dates).isoformat(),
                      "end": max(dates).isoformat(), "days": days,
                      "futureGamesExcluded": True}, indent=2))
    if not args.execute:
        print("Dry run only. Add --execute to fetch completed ESPN box scores.")
        return 0
    espn = EspnBasketballStatisticsProvider()
    with ThreadPoolExecutor(max_workers=4) as executor:
        daily = list(executor.map(
            lambda target: espn.daily_game_logs(sport=args.sport, target_date=target), dates,
        ))
    espn_logs = normalize_basketball_logs(
        [row for result in daily for row in result], args.sport,
    )
    season_year = end.year if args.sport == "WNBA" else (end.year if end.month >= 7 else end.year - 1)
    season = str(season_year) if args.sport == "WNBA" else f"{season_year}-{str(season_year + 1)[-2:]}"
    primary = normalize_basketball_logs(
        NbaHistoricalProvider().league_game_logs(
            season=season, league_id="10" if args.sport == "WNBA" else "00",
        ), args.sport,
    )
    merged, reconciliation = reconcile_basketball_logs(primary, espn_logs)
    upserted = HistoricalRepository().upsert_basketball_logs(merged)
    print(json.dumps({"espnRows": len(espn_logs), "officialRows": len(primary),
                      "reconciliation": reconciliation, "upserted": upserted}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

