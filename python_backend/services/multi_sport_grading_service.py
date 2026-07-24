"""Automatic grading for sports with an authoritative live-stat provider."""

from collections import Counter
from datetime import datetime

from models.slip import LegResultUpdate
from services.live_stats_service import get_live_player_stat_snapshot
from services.slip_service import get_slips, update_slip_results


SUPPORTED_SPORTS = {"NBA", "WNBA", "MLB", "NHL", "PGA", "GOLF"}


def grade_active_slips(*, user_id: str) -> dict[str, object]:
    """Grade completed pending legs while leaving ambiguous data untouched."""
    active_slips = get_slips("active", user_id=user_id)
    updates: dict[str, LegResultUpdate] = {}
    checked = Counter()
    graded = Counter()
    pending_reasons = Counter()

    for slip in active_slips:
        for leg in slip.legs:
            if leg.result_status != "pending":
                continue
            sport = leg.sport.strip().upper()
            if sport not in SUPPORTED_SPORTS:
                pending_reasons["unsupported_sport"] += 1
                continue
            checked[sport] += 1
            season = _season_from_start(leg.game_start_time)
            snapshot = get_live_player_stat_snapshot(
                player_name=leg.player,
                team="",
                prop_type=leg.market,
                sport=sport,
                season=season,
                event_id=leg.event_id,
                matchup=leg.matchup,
                game_start_time=leg.game_start_time,
            )
            if snapshot.value is None or not snapshot.completed:
                pending_reasons[snapshot.status or "not_completed"] += 1
                continue
            updates[leg.prop_id] = LegResultUpdate(
                prop_id=leg.prop_id,
                result_value=snapshot.value,
            )
            graded[sport] += 1

    changed_slips = update_slip_results(
        list(updates.values()),
        user_id=user_id,
    ) if updates else 0
    return {
        "status": "complete",
        "slips_checked": len(active_slips),
        "slips_updated": changed_slips,
        "legs_checked": sum(checked.values()),
        "legs_graded": len(updates),
        "checked_by_sport": dict(checked),
        "graded_by_sport": dict(graded),
        "pending_reasons": dict(pending_reasons),
    }


def _season_from_start(value: str) -> str:
    try:
        return str(datetime.fromisoformat(value.replace("Z", "+00:00")).year)
    except (AttributeError, ValueError):
        return str(datetime.now().year)
