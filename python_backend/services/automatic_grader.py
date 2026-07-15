from calculations.slip_grader import grade_leg, grade_slip_status
from providers.base_player_stats import PlayerStatsProvider
from services.market_normalizer import normalize_market
from services.slip_service import update_slip_with_stat_results
from services.team_normalizer import normalize_team_name


def normalize_player_name(value: str) -> str:
    return normalize_team_name(value)


def grade_event_slips(
    *,
    sport_key: str,
    event_id: str,
    provider: PlayerStatsProvider,
) -> int:
    results = provider.fetch_event_player_stats(
        sport_key=sport_key,
        event_id=event_id,
    )
    if not results:
        return 0

    completed_results = [
        result
        for result in results
        if result.game_completed
    ]
    if not completed_results:
        return 0

    results_by_id = {
        (
            result.player_id,
            normalize_market(result.market),
        ): result
        for result in completed_results
        if result.player_id
    }
    results_by_name = {
        (
            normalize_player_name(result.player_name),
            normalize_market(result.market),
        ): result
        for result in completed_results
    }

    return update_slip_with_stat_results(
        event_id=event_id,
        stat_results={
            "by_id": results_by_id,
            "by_name": results_by_name,
        },
        grade_leg_fn=grade_leg,
        grade_slip_fn=grade_slip_status,
    )
