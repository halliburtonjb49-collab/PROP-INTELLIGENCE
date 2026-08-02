"""Cross-check completed tickets against authoritative league results."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from services.mlb_official_stats_service import official_mlb_result
from services.live_stats_service import get_live_player_stat_snapshot
from services.slip_service import get_slips, reconcile_verified_slip_results


def _recent_enough(value: str, *, days: int) -> bool:
    try:
        event_time = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if event_time.tzinfo is None:
            event_time = event_time.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return False
    return event_time >= datetime.now(timezone.utc) - timedelta(days=days)


def reconcile_user_slips(*, user_id: str, days: int = 14) -> dict[str, object]:
    verified: dict[str, tuple[float, str, str]] = {}
    checked = 0
    for slip in get_slips(user_id=user_id):
        for leg in slip.legs:
            if not _recent_enough(leg.game_start_time, days=days):
                continue
            sport = leg.sport.strip().upper()
            if sport not in {"MLB", "NBA", "WNBA"}:
                continue
            checked += 1
            if sport in {"NBA", "WNBA"}:
                snapshot = get_live_player_stat_snapshot(
                    player_name=leg.player,
                    team="",
                    prop_type=leg.market,
                    sport=sport,
                    event_id=leg.event_id,
                    matchup=leg.matchup,
                    game_start_time=leg.game_start_time,
                )
                if snapshot.value is not None and snapshot.completed:
                    verified[leg.prop_id] = (
                        snapshot.value,
                        snapshot.source or "authoritative-final-boxscore",
                        datetime.now(timezone.utc).isoformat(),
                    )
                continue
            result = official_mlb_result(
                player_name=leg.player,
                market=leg.market,
                matchup=leg.matchup,
                game_start_time=leg.game_start_time,
                api_sports_game_id=leg.api_sports_game_id,
            )
            if result is None:
                continue
            verified[leg.prop_id] = (
                result.value,
                result.source,
                datetime.now(timezone.utc).isoformat(),
            )
    summary = reconcile_verified_slip_results(verified, user_id=user_id)
    return {
        "authoritative_source": "official-final-stat-providers",
        "legs_checked": checked,
        **summary,
    }
