from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class PlayerStatResult:
    event_id: str
    player_id: str
    player_name: str
    market: str
    value: float
    game_completed: bool


class PlayerStatsProvider(ABC):
    @abstractmethod
    def fetch_event_player_stats(
        self,
        *,
        sport_key: str,
        event_id: str,
    ) -> list[PlayerStatResult]:
        """Return player statistics for one game."""
        raise NotImplementedError
