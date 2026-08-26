"""Automatic grading for sports with an authoritative live-stat provider."""

from collections import Counter
from datetime import datetime, timezone

from models.slip import LegResultUpdate
from services.live_stats_service import get_live_player_stat_snapshot
from services.slip_service import (
    _connect,
    get_slips,
    initialize_slip_table,
    update_slip_results,
)
from services.result_reconciliation_service import reconcile_user_slips


SUPPORTED_SPORTS = {"NBA", "WNBA", "MLB", "NFL", "NHL"}


def grade_all_active_slips() -> dict[str, object]:
    """Settle every user's active slips during the background sync cycle."""
    initialize_slip_table()
    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT DISTINCT user_id
            FROM slips
            WHERE status = 'active'
              AND user_id IS NOT NULL
              AND TRIM(user_id) <> ''
            """
        ).fetchall()

    totals = Counter()
    pending_reasons = Counter()
    failures: list[dict[str, str]] = []
    for row in rows:
        user_id = str(row["user_id"])
        try:
            result = grade_active_slips(user_id=user_id)
            totals["users_checked"] += 1
            totals["slips_checked"] += int(result["slips_checked"])
            totals["slips_updated"] += int(result["slips_updated"])
            totals["legs_checked"] += int(result["legs_checked"])
            totals["legs_graded"] += int(result["legs_graded"])
            pending_reasons.update(result.get("pending_reasons", {}))
        except Exception as exc:
            failures.append({"error": f"{type(exc).__name__}: {exc}"})

    return {
        "status": "partial" if failures else "complete",
        **dict(totals),
        "pending_reasons": dict(pending_reasons),
        "failures": failures,
    }


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
                result_verified=True,
                result_source=snapshot.source or "authoritative-final-boxscore",
                result_verified_at=datetime.now(timezone.utc).isoformat(),
            )
            graded[sport] += 1

    changed_slips = update_slip_results(
        list(updates.values()),
        user_id=user_id,
    ) if updates else 0
    reconciliation = reconcile_user_slips(user_id=user_id)
    return {
        "status": "complete",
        "slips_checked": len(active_slips),
        "slips_updated": changed_slips,
        "legs_checked": sum(checked.values()),
        "legs_graded": len(updates),
        "checked_by_sport": dict(checked),
        "graded_by_sport": dict(graded),
        "pending_reasons": dict(pending_reasons),
        "reconciliation": reconciliation,
    }


def _season_from_start(value: str) -> str:
    try:
        return str(datetime.fromisoformat(value.replace("Z", "+00:00")).year)
    except (AttributeError, ValueError):
        return str(datetime.now().year)
