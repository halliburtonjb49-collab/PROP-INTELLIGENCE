from __future__ import annotations

from datetime import date
from typing import Any


class ScoreboardProvider:
    async def get_games(self, selected_date: date) -> list[dict[str, Any]]:
        raise NotImplementedError
