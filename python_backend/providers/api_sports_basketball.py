from typing import Any

import requests

from config import API_SPORTS_KEY


class ApiSportsBasketballProvider:
    BASE_URL = "https://v1.basketball.api-sports.io"

    def __init__(self) -> None:
        if not API_SPORTS_KEY:
            raise RuntimeError(
                "API_SPORTS_KEY is missing from .env"
            )
        self.headers = {
            "x-apisports-key": API_SPORTS_KEY,
        }

    def get(
        self,
        endpoint: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        response = requests.get(
            f"{self.BASE_URL}/{endpoint.lstrip('/')}",
            headers=self.headers,
            params=params or {},
            timeout=20,
        )
        response.raise_for_status()

        payload = response.json()
        if not isinstance(payload, dict):
            raise ValueError(
                "API-Sports returned an invalid response."
            )

        errors = payload.get("errors")
        if errors:
            raise RuntimeError(
                f"API-Sports error: {errors}"
            )

        return payload

    def status(self) -> dict[str, Any]:
        return self.get("status")

    def find_wnba_leagues(self) -> dict[str, Any]:
        return self.get(
            "leagues",
            params={
                "search": "WNBA",
                "country": "USA",
            },
        )

    def get_games(
        self,
        *,
        league_id: str,
        season: str,
    ) -> dict[str, Any]:
        return self.get(
            "games",
            params={
                "league": league_id,
                "season": season,
            },
        )

    def get_games_by_date(
        self,
        *,
        league_id: str,
        season: str,
        date: str,
    ) -> dict[str, Any]:
        return self.get(
            "games",
            params={
                "league": league_id,
                "season": season,
                "date": date,
            },
        )

    def get_game_player_statistics(
        self,
        *,
        game_id: str,
    ) -> dict[str, Any]:
        return self.get(
            "games/statistics/players",
            params={
                "id": game_id,
            },
        )
