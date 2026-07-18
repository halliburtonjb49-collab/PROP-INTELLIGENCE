import argparse
import json
import logging
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.historical_ingestion_service import backfill_basketball_officiating, run_daily_historical_sync
from services.prediction_automation_service import grade_completed_predictions
from services.schedule_fatigue_service import sync_schedule_and_fatigue


def _run_stage(name: str, operation):
    """Keep an upstream provider outage from aborting unrelated daily work."""
    try:
        return operation()
    except Exception as exc:  # cron boundary: report the stage and continue
        logging.exception("Daily sync stage %s failed", name)
        return {"error": str(exc), "stage": name}


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync free NBA/WNBA/MLB historical data.")
    parser.add_argument("--date", type=date.fromisoformat, help="UTC date in YYYY-MM-DD format")
    parser.add_argument("--season", help="NBA season such as 2025-26")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    result = _run_stage(
        "historicalSync",
        lambda: run_daily_historical_sync(target_date=args.date, season=args.season),
    )
    if not isinstance(result, dict):
        result = {"historicalSync": {"error": "Historical sync returned an invalid result"}}
    target = args.date or date.today()
    nba_start = target.year if target.month >= 7 else target.year - 1
    result["scheduleFatigue"] = _run_stage(
        "scheduleFatigue",
        lambda: sync_schedule_and_fatigue(
            nba_season=args.season or f"{nba_start}-{str(nba_start + 1)[-2:]}",
            wnba_season=str(target.year),
        ),
    )
    result["wnbaOfficiatingBackfill"] = _run_stage(
        "wnbaOfficiatingBackfill",
        lambda: backfill_basketball_officiating(
            sport="WNBA", season=str(target.year), days=14,
        ),
    )
    result["predictionGrading"] = _run_stage(
        "predictionGrading", grade_completed_predictions,
    )
    print(json.dumps(result, indent=2))
    return 1 if all(isinstance(result.get(s), dict) and "error" in result[s] for s in ("NBA", "WNBA", "MLB")) else 0


if __name__ == "__main__":
    raise SystemExit(main())
