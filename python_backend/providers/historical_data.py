"""Free historical-data collectors with lazy optional dependencies."""

from __future__ import annotations

from datetime import date
from typing import Any
import requests


class MissingHistoricalDependency(RuntimeError):
    pass


def _records(frame: Any) -> list[dict[str, object]]:
    if frame is None or getattr(frame, "empty", True):
        return []
    clean = frame.where(frame.notna(), None)
    return [dict(row) for row in clean.to_dict(orient="records")]


class NbaHistoricalProvider:
    """NBA/WNBA game logs and NBA tracking data from stats.nba.com."""

    def _endpoints(self) -> Any:
        try:
            from nba_api.stats import endpoints
        except ImportError as exc:
            raise MissingHistoricalDependency(
                "Install requirements-historical.txt to enable nba_api ingestion."
            ) from exc
        return endpoints

    def league_game_logs(
        self,
        *,
        season: str,
        league_id: str,
        season_type: str = "Regular Season",
        timeout: int = 60,
    ) -> list[dict[str, object]]:
        endpoint = self._endpoints().LeagueGameLog(
            season=season,
            league_id=league_id,
            season_type_all_star=season_type,
            player_or_team_abbreviation="P",
            timeout=timeout,
        )
        return _records(endpoint.get_data_frames()[0])

    def league_schedule(self, *, season: str, league_id: str,
                        timeout: int = 60) -> list[dict[str, object]]:
        endpoint = self._endpoints().ScheduleLeagueV2(
            season=season, league_id=league_id, timeout=timeout,
        )
        return _records(endpoint.get_data_frames()[0])

    def player_tracking(
        self,
        *,
        season: str,
        measure_type: str = "Drives",
        league_id: str = "00",
        timeout: int = 60,
    ) -> list[dict[str, object]]:
        endpoint = self._endpoints().LeagueDashPtStats(
            season=season,
            league_id_nullable=league_id,
            pt_measure_type=measure_type,
            per_mode_simple="PerGame",
            season_type_all_star="Regular Season",
            timeout=timeout,
        )
        return _records(endpoint.get_data_frames()[0])

    def game_officials(self, *, game_id: str, timeout: int = 60) -> list[dict[str, object]]:
        endpoint = self._endpoints().BoxScoreSummaryV3(game_id=game_id, timeout=timeout)
        for frame in endpoint.get_data_frames():
            columns = set(getattr(frame, "columns", []))
            if "personId" in columns and {"firstName", "familyName"} <= columns:
                return [
                    {
                        "PERSON_ID": row.get("personId"),
                        "FIRST_NAME": row.get("firstName"),
                        "LAST_NAME": row.get("familyName"),
                    }
                    for row in _records(frame)
                ]
        return []

    def defensive_synergy(self, *, season: str, league_id: str, play_type: str,
                          timeout: int = 60) -> list[dict[str, object]]:
        endpoint = self._endpoints().SynergyPlayTypes(
            league_id=league_id, per_mode_simple="PerGame",
            player_or_team_abbreviation="T", season_type_all_star="Regular Season",
            season=season, type_grouping_nullable="Defensive",
            play_type_nullable=play_type, timeout=timeout,
        )
        return _records(endpoint.get_data_frames()[0])


class MlbHistoricalProvider:
    """Pitch-level Statcast collector from Baseball Savant via pybaseball."""

    def statcast(self, *, start: date, end: date) -> list[dict[str, object]]:
        try:
            from pybaseball import cache, statcast
        except ImportError as exc:
            raise MissingHistoricalDependency(
                "Install requirements-historical.txt to enable pybaseball ingestion."
            ) from exc
        cache.enable()
        return _records(statcast(start.isoformat(), end.isoformat()))

    def umpire_assignments(self, *, start: date, end: date,
                           timeout: int = 30) -> list[dict[str, object]]:
        response = requests.get(
            "https://statsapi.mlb.com/api/v1/schedule",
            params={"sportId": 1, "startDate": start.isoformat(),
                    "endDate": end.isoformat(), "hydrate": "officials"},
            timeout=timeout,
        )
        response.raise_for_status()
        payload = response.json()
        assignments = []
        for day in payload.get("dates", []):
            for game in day.get("games", []):
                for row in game.get("officials", []):
                    if row.get("officialType") != "Home Plate":
                        continue
                    official = row.get("official") or {}
                    assignments.append({
                        "game_pk": str(game.get("gamePk") or ""),
                        "game_date": game.get("officialDate") or day.get("date"),
                        "official_id": str(official.get("id") or ""),
                        "official_name": str(official.get("fullName") or ""),
                        "source": "MLB Stats API",
                        "raw": row,
                    })
        return [row for row in assignments if row["game_pk"] and row["official_id"]]
