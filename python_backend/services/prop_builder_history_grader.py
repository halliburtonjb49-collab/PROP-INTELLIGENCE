import json
import logging
from typing import Any

from calculations.slip_grader import grade_leg
from providers.wnba_player_stats import (
    WnbaPlayerStatsProvider,
)
from services.market_normalizer import (
    normalize_market,
)
from services.prop_builder_history_service import (
    _connect,
    initialize_prop_builder_history,
)
from services.team_normalizer import (
    normalize_team_name,
)

logger = logging.getLogger(__name__)


def _normalize_player(value: str) -> str:
    return normalize_team_name(value)


def _group_stats_by_game(
    legs: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[
        str,
        list[dict[str, Any]],
    ] = {}
    for leg in legs:
        sport = str(
            leg.get("sport", "")
        ).upper()
        if sport != "WNBA":
            continue
        game_id = str(
            leg.get(
                "api_sports_game_id",
                "",
            )
        )
        if not game_id:
            continue
        grouped.setdefault(
            game_id,
            [],
        ).append(leg)
    return grouped


def grade_prop_builder_history() -> dict[str, int]:
    initialize_prop_builder_history()
    provider = WnbaPlayerStatsProvider()
    with _connect() as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM prop_builder_history
            WHERE status = 'pending'
            ORDER BY created_at ASC
            """
        ).fetchall()

    histories_checked = 0
    histories_updated = 0
    legs_updated = 0

    for row in rows:
        histories_checked += 1
        history_id = int(row["id"])
        legs = json.loads(
            row["legs_json"]
        )
        grouped_games = _group_stats_by_game(
            legs
        )

        stats_by_id: dict[
            tuple[str, str],
            Any,
        ] = {}
        stats_by_name: dict[
            tuple[str, str],
            Any,
        ] = {}

        for game_id in grouped_games:
            stats = provider.fetch_event_player_stats(
                sport_key="basketball_wnba",
                event_id=game_id,
            )
            for stat in stats:
                market = normalize_market(
                    stat.market
                )
                if stat.player_id:
                    stats_by_id[(
                        stat.player_id,
                        market,
                    )] = stat
                stats_by_name[(
                    _normalize_player(
                        stat.player_name
                    ),
                    market,
                )] = stat

        build_changed = False
        for leg in legs:
            current_status = str(
                leg.get(
                    "result_status",
                    "pending",
                )
            )
            if current_status != "pending":
                continue
            if str(leg.get("sport", "")).upper() != "WNBA":
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
                result = stats_by_id.get((
                    player_id,
                    market,
                ))
            if result is None:
                result = stats_by_name.get((
                    _normalize_player(
                        player_name
                    ),
                    market,
                ))
            if result is None:
                continue
            if not result.game_completed:
                continue

            status = grade_leg(
                side=str(leg.get("side", "")),
                line=float(leg.get("line", 0)),
                result_value=float(result.value),
            )
            leg["result_value"] = float(
                result.value
            )
            leg["result_status"] = status
            leg["game_completed"] = True
            build_changed = True
            legs_updated += 1

        if not build_changed:
            continue

        won = sum(
            1
            for leg in legs
            if leg.get("result_status") == "won"
        )
        lost = sum(
            1
            for leg in legs
            if leg.get("result_status") == "lost"
        )
        pushed = sum(
            1
            for leg in legs
            if leg.get("result_status") == "push"
        )
        pending = sum(
            1
            for leg in legs
            if leg.get("result_status", "pending") == "pending"
        )

        resolved = won + lost + pushed
        hit_rate = (
            round(
                (won / resolved) * 100,
                1,
            )
            if resolved > 0
            else 0
        )

        if lost > 0:
            build_status = "lost"
        elif pending > 0:
            build_status = "pending"
        elif won > 0:
            build_status = "won"
        elif pushed > 0:
            build_status = "push"
        else:
            build_status = "pending"

        with _connect() as connection:
            connection.execute(
                """
                UPDATE prop_builder_history
                SET
                    legs_json = ?,
                    status = ?,
                    legs_won = ?,
                    legs_lost = ?,
                    legs_pushed = ?,
                    legs_pending = ?,
                    hit_rate = ?
                WHERE id = ?
                """,
                (
                    json.dumps(legs),
                    build_status,
                    won,
                    lost,
                    pushed,
                    pending,
                    hit_rate,
                    history_id,
                ),
            )
        histories_updated += 1

    logger.info(
        (
            "Builder history grading complete: "
            "checked=%s updated=%s legs=%s"
        ),
        histories_checked,
        histories_updated,
        legs_updated,
    )
    return {
        "histories_checked": histories_checked,
        "histories_updated": histories_updated,
        "legs_updated": legs_updated,
    }
