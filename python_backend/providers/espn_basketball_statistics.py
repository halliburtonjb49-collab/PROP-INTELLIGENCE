"""ESPN basketball box-score fallback for NBA/WNBA historical logs."""

from __future__ import annotations

from datetime import date
from typing import Iterable

import requests

from config import HTTP_TIMEOUT_SECONDS

_BASE_URL = "https://site.api.espn.com/apis/site/v2/sports/basketball"
_LEAGUES = {"NBA": "nba", "WNBA": "wnba"}


def _number(value: object) -> float | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _made(value: object) -> float | None:
    text = str(value or "").strip()
    return _number(text.split("-", 1)[0])


def _attempted(value: object) -> float | None:
    text = str(value or "").strip()
    parts = text.split("-", 1)
    return _number(parts[1]) if len(parts) == 2 else None


class EspnBasketballStatisticsProvider:
    """Fetch completed daily player box scores from ESPN's site feed."""

    def _json(self, url: str, *, params: dict[str, object]) -> dict:
        response = requests.get(
            url,
            params=params,
            headers={
                "Accept": "application/json",
                "User-Agent": (
                    "Mozilla/5.0 (compatible; PropsIntell/1.0; "
                    "+https://propsintell.com)"
                ),
            },
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        return payload if isinstance(payload, dict) else {}

    def _event_logs(
        self,
        *,
        league: str,
        sport: str,
        target_date: date,
        event: dict,
    ) -> Iterable[dict[str, object]]:
        event_id = str(event.get("id") or "").strip()
        if not event_id:
            return []
        summary = self._json(
            f"{_BASE_URL}/{league}/summary",
            params={"event": event_id},
        )
        rows: list[dict[str, object]] = []
        boxscore = summary.get("boxscore")
        teams = boxscore.get("players", []) if isinstance(boxscore, dict) else []
        for team_box in teams if isinstance(teams, list) else []:
            if not isinstance(team_box, dict):
                continue
            team = team_box.get("team")
            team_id = str(team.get("id") or "") if isinstance(team, dict) else ""
            sections = team_box.get("statistics")
            for section in sections if isinstance(sections, list) else []:
                if not isinstance(section, dict):
                    continue
                keys = section.get("keys")
                athletes = section.get("athletes")
                if not isinstance(keys, list) or not isinstance(athletes, list):
                    continue
                for item in athletes:
                    if not isinstance(item, dict) or item.get("didNotPlay") is True:
                        continue
                    athlete = item.get("athlete")
                    values = item.get("stats")
                    if not isinstance(athlete, dict) or not isinstance(values, list):
                        continue
                    stats = {
                        str(key): values[index] if index < len(values) else None
                        for index, key in enumerate(keys)
                    }
                    player_id = str(athlete.get("id") or "").strip()
                    if not player_id:
                        continue
                    rows.append(
                        {
                            "PLAYER_ID": player_id,
                            "PLAYER_NAME": str(athlete.get("displayName") or ""),
                            "TEAM_ID": team_id,
                            "GAME_ID": event_id,
                            "GAME_DATE": target_date.isoformat(),
                            "MATCHUP": str(event.get("name") or ""),
                            "MIN": _number(stats.get("minutes")),
                            "PTS": _number(stats.get("points")),
                            "REB": _number(stats.get("rebounds")),
                            "AST": _number(stats.get("assists")),
                            "STL": _number(stats.get("steals")),
                            "BLK": _number(stats.get("blocks")),
                            "TOV": _number(stats.get("turnovers")),
                            "FG3M": _made(
                                stats.get(
                                    "threePointFieldGoalsMade-threePointFieldGoalsAttempted"
                                )
                            ),
                            "PF": _number(stats.get("fouls")),
                            "FTA": _attempted(
                                stats.get("freeThrowsMade-freeThrowsAttempted")
                            ),
                            "SOURCE": "ESPN",
                        }
                    )
        return rows

    def daily_game_logs(
        self,
        *,
        sport: str,
        target_date: date,
    ) -> list[dict[str, object]]:
        normalized_sport = sport.upper()
        league = _LEAGUES[normalized_sport]
        payload = self._json(
            f"{_BASE_URL}/{league}/scoreboard",
            params={"dates": target_date.strftime("%Y%m%d"), "limit": 100},
        )
        rows: list[dict[str, object]] = []
        for event in payload.get("events", []):
            if not isinstance(event, dict):
                continue
            status = event.get("status")
            status_type = status.get("type") if isinstance(status, dict) else {}
            if not isinstance(status_type, dict) or status_type.get("completed") is not True:
                continue
            rows.extend(
                self._event_logs(
                    league=league,
                    sport=normalized_sport,
                    target_date=target_date,
                    event=event,
                )
            )
        return rows
