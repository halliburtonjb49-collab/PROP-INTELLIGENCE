from typing import Any

from providers.api_sports_basketball import (
    ApiSportsBasketballProvider,
)
from providers.base_player_stats import (
    PlayerStatResult,
    PlayerStatsProvider,
)


class WnbaPlayerStatsProvider(PlayerStatsProvider):
    def __init__(self) -> None:
        self.client = ApiSportsBasketballProvider()

    def fetch_event_player_stats(
        self,
        *,
        sport_key: str,
        event_id: str,
    ) -> list[PlayerStatResult]:
        payload = self.client.get_game_player_statistics(
            game_id=event_id,
        )
        raw_response = payload.get("response", [])
        if not isinstance(raw_response, list):
            return []

        results: list[PlayerStatResult] = []
        for team_block in raw_response:
            if not isinstance(team_block, dict):
                continue
            game_completed = self._is_game_completed(
                team_block
            )
            players = team_block.get("players", [])
            if not isinstance(players, list):
                continue

            for item in players:
                if not isinstance(item, dict):
                    continue

                player = item.get("player", {})
                if not isinstance(player, dict):
                    continue

                player_id = str(player.get("id", ""))
                player_name = str(player.get("name", ""))
                if not player_name:
                    continue

                stat_values = self._extract_stats(item)
                for market, value in stat_values.items():
                    if value is None:
                        continue
                    results.append(
                        PlayerStatResult(
                            event_id=event_id,
                            player_id=player_id,
                            player_name=player_name,
                            market=market,
                            value=value,
                            game_completed=game_completed,
                        )
                    )

        return results

    def _extract_stats(
        self,
        item: dict[str, Any],
    ) -> dict[str, float | None]:
        points = self._number(item.get("points"))
        assists = self._number(item.get("assists"))
        rebounds = self._number(
            item.get("totReb")
            or item.get("rebounds")
        )
        points_rebounds_assists = None
        if (
            points is not None
            and assists is not None
            and rebounds is not None
        ):
            points_rebounds_assists = (
                points + assists + rebounds
            )

        return {
            "points": points,
            "assists": assists,
            "rebounds": rebounds,
            "pra": points_rebounds_assists,
            "three_pointers_made": self._number(
                item.get("tpm")
                or item.get("threePointersMade")
            ),
            "steals": self._number(
                item.get("steals")
            ),
            "blocks": self._number(
                item.get("blocks")
            ),
            "turnovers": self._number(
                item.get("turnovers")
            ),
        }

    @staticmethod
    def _number(value: Any) -> float | None:
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            try:
                return float(value)
            except ValueError:
                return None
        return None

    @staticmethod
    def _is_game_completed(
        team_block: dict[str, Any],
    ) -> bool:
        game = team_block.get("game", {})
        game_status = ""
        if isinstance(game, dict):
            game_status = str(
                game.get("status")
                or game.get("short_status")
                or game.get("long_status")
                or ""
            )
        status = str(
            team_block.get("status")
            or game_status
            or ""
        ).lower()
        return status in {
            "finished",
            "final",
            "completed",
            "ft",
        }
