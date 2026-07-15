import json
import logging

from calculations.slip_grader import grade_leg
from models.grading_report import (
    GradingLegReport,
    GradingReport,
)
from providers.wnba_player_stats import (
    WnbaPlayerStatsProvider,
)
from services.automatic_grader import (
    grade_event_slips,
)
from services.market_normalizer import normalize_market
from services.team_normalizer import normalize_team_name
from services.slip_service import (
    _connect,
    initialize_slip_table,
)

logger = logging.getLogger(__name__)


def _normalize_player_name(value: str) -> str:
    return normalize_team_name(value)


def _log_unmatched_wnba_legs(
    *,
    game_id: str,
    provider: WnbaPlayerStatsProvider,
) -> None:
    stats = provider.fetch_event_player_stats(
        sport_key="basketball_wnba",
        event_id=game_id,
    )

    stats_by_id = {
        (
            stat.player_id,
            normalize_market(stat.market),
        ): stat
        for stat in stats
        if stat.player_id and stat.game_completed
    }
    stats_by_name = {
        (
            _normalize_player_name(stat.player_name),
            normalize_market(stat.market),
        ): stat
        for stat in stats
        if stat.game_completed
    }

    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT legs_json
            FROM slips
            WHERE status = 'active'
            """
        ).fetchall()

    for row in rows:
        legs = json.loads(row["legs_json"])
        for leg in legs:
            if str(
                leg.get("api_sports_game_id", "")
            ) != game_id:
                continue

            player_name = str(
                leg.get("player", "")
            )
            market = normalize_market(
                str(leg.get("market", ""))
            )
            player_id = str(
                leg.get("player_id", "")
            )

            matched = False
            if player_id and (
                player_id,
                market,
            ) in stats_by_id:
                matched = True
            elif (
                _normalize_player_name(player_name),
                market,
            ) in stats_by_name:
                matched = True

            if not matched:
                logger.warning(
                    "No matching WNBA stat found for player=%s market=%s game=%s",
                    player_name,
                    market,
                    game_id,
                )


def grade_active_wnba_slips() -> dict[str, int]:
    initialize_slip_table()
    provider = WnbaPlayerStatsProvider()

    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT legs_json
            FROM slips
            WHERE status = 'active'
            """
        ).fetchall()

    game_ids: set[str] = set()
    for row in rows:
        legs = json.loads(row["legs_json"])
        for leg in legs:
            if str(leg.get("sport", "")).upper() != "WNBA":
                continue
            game_id = str(
                leg.get("api_sports_game_id", "")
            )
            if game_id:
                game_ids.add(game_id)

    updated_slips = 0
    for game_id in game_ids:
        logger.info(
            "Grading WNBA game %s",
            game_id,
        )
        _log_unmatched_wnba_legs(
            game_id=game_id,
            provider=provider,
        )
        updated_slips += grade_event_slips(
            sport_key="basketball_wnba",
            event_id=game_id,
            provider=provider,
        )

    logger.info(
        "WNBA grading complete: games=%s updated_slips=%s",
        len(game_ids),
        updated_slips,
    )

    return {
        "games_checked": len(game_ids),
        "updated_slips": updated_slips,
    }


def diagnose_wnba_game(
    game_id: str,
) -> GradingReport:
    initialize_slip_table()
    provider = WnbaPlayerStatsProvider()
    stats = provider.fetch_event_player_stats(
        sport_key="basketball_wnba",
        event_id=game_id,
    )

    stats_by_id = {
        (
            stat.player_id,
            normalize_market(stat.market),
        ): stat
        for stat in stats
        if stat.player_id
    }
    stats_by_name = {
        (
            _normalize_player_name(stat.player_name),
            normalize_market(stat.market),
        ): stat
        for stat in stats
    }

    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT id, legs_json
            FROM slips
            WHERE status = 'active'
            """
        ).fetchall()

    reports: list[GradingLegReport] = []
    legs_updated = 0

    for row in rows:
        legs = json.loads(row["legs_json"])
        for leg in legs:
            if str(
                leg.get("api_sports_game_id", "")
            ) != game_id:
                continue

            market = normalize_market(
                str(leg.get("market", ""))
            )
            player_id = str(
                leg.get("player_id", "")
            )
            player_name = str(
                leg.get("player", "")
            )
            result = None

            if player_id:
                result = stats_by_id.get(
                    (player_id, market)
                )

            if result is None:
                result = stats_by_name.get(
                    (
                        _normalize_player_name(player_name),
                        market,
                    )
                )

            if result is None:
                reports.append(
                    GradingLegReport(
                        prop_id=str(
                            leg.get("prop_id", "")
                        ),
                        player=player_name,
                        market=str(
                            leg.get("market", "")
                        ),
                        line=float(
                            leg.get("line", 0)
                        ),
                        side=str(
                            leg.get("side", "")
                        ),
                        matched=False,
                        normalized_market=market,
                        reason=(
                            "No matching player-stat "
                            "record was found."
                        ),
                    )
                )
                continue

            result_status = grade_leg(
                side=str(leg.get("side", "")),
                line=float(leg.get("line", 0)),
                result_value=float(result.value),
            )
            reports.append(
                GradingLegReport(
                    prop_id=str(
                        leg.get("prop_id", "")
                    ),
                    player=player_name,
                    market=str(
                        leg.get("market", "")
                    ),
                    line=float(
                        leg.get("line", 0)
                    ),
                    side=str(
                        leg.get("side", "")
                    ),
                    matched=True,
                    matched_player=result.player_name,
                    normalized_market=market,
                    result_value=float(result.value),
                    result_status=result_status,
                )
            )
            legs_updated += 1

    return GradingReport(
        game_id=game_id,
        stats_found=len(stats),
        legs_checked=len(reports),
        legs_matched=sum(
            1 for report in reports if report.matched
        ),
        legs_updated=legs_updated,
        reports=reports,
    )
