from __future__ import annotations

from datetime import date
from typing import Any

from .scoreboard_provider import ScoreboardProvider


class SportsService(ScoreboardProvider):
    async def get_games(self, selected_date: date) -> list[dict[str, Any]]:
        # Adapter entry point for the existing/future provider client.
        _ = selected_date
        return []

    async def get_scoreboard_games(self, selected_date: date) -> list[dict[str, Any]]:
        response = await self.get_games(selected_date)
        if isinstance(response, list):
            return response
        if isinstance(response, dict):
            games = response.get("games") or response.get("events") or response.get("data") or []
            if isinstance(games, list):
                return games
        return []


sports_service = SportsService()
