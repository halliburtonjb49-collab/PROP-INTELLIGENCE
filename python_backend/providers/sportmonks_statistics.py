"""Completed-fixture player statistics from the licensed Sportmonks feed."""

from __future__ import annotations

from datetime import date

from services.sportmonks_headshot_service import _TARGET_LEAGUES, _get_all


class SportmonksStatisticsProvider:
    """Fetch only the player statistics used by supported soccer prop markets."""

    STAT_TYPE_IDS = (41, 42, 52, 79, 83, 84, 85, 86)

    def completed_fixtures(self, *, target_date: date) -> list[dict]:
        league_ids = ",".join(str(value) for value in _TARGET_LEAGUES.values())
        return _get_all(
            f"/fixtures/date/{target_date.isoformat()}",
            include="lineups.details",
            filters=(
                f"fixtureLeagues:{league_ids};"
                "fixtureStates:5,7,8;"
                f"lineupDetailTypes:{','.join(map(str, self.STAT_TYPE_IDS))}"
            ),
        )
