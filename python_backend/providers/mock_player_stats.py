from providers.base_player_stats import (
    PlayerStatResult,
    PlayerStatsProvider,
)


class MockPlayerStatsProvider(PlayerStatsProvider):
    def fetch_event_player_stats(
        self,
        *,
        sport_key: str,
        event_id: str,
    ) -> list[PlayerStatResult]:
        return [
            PlayerStatResult(
                event_id=event_id,
                player_id="shohei-ohtani",
                player_name="Shohei Ohtani",
                market="Total Bases",
                value=2.0,
                game_completed=True,
            ),
            PlayerStatResult(
                event_id=event_id,
                player_id="example-pitcher",
                player_name="Example Pitcher",
                market="Pitcher Strikeouts",
                value=7.0,
                game_completed=True,
            ),
        ]
