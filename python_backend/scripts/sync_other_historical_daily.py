"""Run non-MLB historical, fatigue, officiating, and grading stages."""

import argparse
import json
import logging
import sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.historical_ingestion_service import (
    HistoricalRepository, backfill_basketball_officiating,
    run_daily_historical_sync,
)
from providers.espn_specialty_statistics import golf_logs, tennis_logs
from services.pipeline_run_service import finish_pipeline_run, start_pipeline_run
from services.prediction_automation_service import grade_completed_predictions
from services.schedule_fatigue_service import sync_schedule_and_fatigue
from services.defender_matchup_service import sync_defender_matchups


def _run_stage(name: str, operation):
    """Keep an upstream provider outage from aborting unrelated daily work."""
    try:
        return operation()
    except Exception as exc:
        logging.exception("Daily sync stage %s failed", name)
        return {"error": str(exc), "stage": name}


def _sync_specialty_history(target: date) -> dict[str, object]:
    rows = (
        tennis_logs(tour="ATP", target_date=target)
        + tennis_logs(tour="WTA", target_date=target)
        + golf_logs(target_date=target)
    )
    return {
        "fetched": len(rows),
        "upserted": HistoricalRepository().upsert_player_game_logs(rows),
        "source": "ESPN",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date", type=date.fromisoformat)
    parser.add_argument("--season")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    identifier, started = start_pipeline_run("historical-sync")
    target = args.date or date.today()
    result = _run_stage(
        "historicalSync",
        lambda: run_daily_historical_sync(
            target_date=args.date,
            season=args.season,
            include_mlb=False,
        ),
    )
    result["specialtyHistory"] = _run_stage(
        "specialtyHistory",
        lambda: _sync_specialty_history(args.date or (date.today() - timedelta(days=1))),
    )
    if not isinstance(result, dict):
        result = {
            "historicalSync": {
                "error": "Historical sync returned an invalid result"
            }
        }
    nba_start = target.year if target.month >= 7 else target.year - 1
    result["scheduleFatigue"] = _run_stage(
        "scheduleFatigue",
        lambda: sync_schedule_and_fatigue(
            nba_season=args.season
            or f"{nba_start}-{str(nba_start + 1)[-2:]}",
            wnba_season=str(target.year),
        ),
    )
    result["wnbaDefenderMatchups"] = _run_stage(
        "wnbaDefenderMatchups",
        lambda: sync_defender_matchups(sport="WNBA", season=str(target.year)),
    )
    result["wnbaOfficiatingBackfill"] = _run_stage(
        "wnbaOfficiatingBackfill",
        lambda: backfill_basketball_officiating(
            sport="WNBA",
            season=str(target.year),
            days=14,
        ),
    )
    result["predictionGrading"] = _run_stage(
        "predictionGrading",
        grade_completed_predictions,
    )
    errors: list[dict[str, object]] = []
    for stage in ("NBA", "WNBA", "SOCCER", "wnbaOfficiatingBackfill"):
        stage_result = result.get(stage)
        if isinstance(stage_result, dict) and stage_result.get("error"):
            errors.append(
                {
                    "stage": stage,
                    "error": stage_result.get("error"),
                    "providers": stage_result.get("providers"),
                }
            )
    schedule_result = result.get("scheduleFatigue")
    if (
        isinstance(schedule_result, dict)
        and schedule_result.get("persisted") is not True
    ):
        errors.append(
            {
                "stage": "scheduleFatigue",
                "error": schedule_result.get("reason")
                or schedule_result.get("error")
                or "Schedule and fatigue persistence failed",
            }
        )
    grading_result = result.get("predictionGrading")
    if isinstance(grading_result, dict) and grading_result.get("error"):
        errors.append(
            {
                "stage": "predictionGrading",
                "error": grading_result.get("error"),
            }
        )
    telemetry = finish_pipeline_run(
        identifier,
        started,
        metrics=result,
        errors=errors,
    )
    print(
        json.dumps(
            {"results": result, "pipeline": telemetry},
            indent=2,
            default=str,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
