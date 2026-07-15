from datetime import date
from typing import Any

import requests

from config import API_SPORTS_BASEBALL_KEY, HTTP_TIMEOUT_SECONDS


class ApiSportsBaseballProvider:
    BASE_URL = "https://v1.baseball.api-sports.io"

    def get_games_by_date(self, target_date: date) -> list[dict[str, object]]:
        if not API_SPORTS_BASEBALL_KEY:
            return []

        response = requests.get(
            f"{self.BASE_URL}/games",
            headers={"x-apisports-key": API_SPORTS_BASEBALL_KEY},
            params={"date": target_date.isoformat()},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        if not isinstance(payload, dict) or payload.get("errors"):
            return []

        games = payload.get("response")
        if not isinstance(games, list):
            return []

        normalized: list[dict[str, object]] = []
        for raw in games:
            if not isinstance(raw, dict):
                continue
            league = raw.get("league")
            league_name = (
                str(league.get("name") or "").strip().upper()
                if isinstance(league, dict)
                else ""
            )
            if league_name != "MLB":
                continue

            teams = raw.get("teams")
            scores = raw.get("scores")
            status = raw.get("status")
            if not isinstance(teams, dict):
                continue
            away = teams.get("away")
            home = teams.get("home")
            away_name = (
                str(away.get("name") or "").strip()
                if isinstance(away, dict)
                else ""
            )
            home_name = (
                str(home.get("name") or "").strip()
                if isinstance(home, dict)
                else ""
            )
            if not away_name or not home_name:
                continue

            away_score = _score_total(scores, "away")
            home_score = _score_total(scores, "home")
            status_long = (
                str(status.get("long") or "").strip()
                if isinstance(status, dict)
                else ""
            )
            status_short = (
                str(status.get("short") or "").strip().upper()
                if isinstance(status, dict)
                else ""
            )
            completed = status_short in {"FT", "AET", "AP"} or status_long.lower() in {
                "finished",
                "game finished",
            }

            game_id = str(raw.get("id") or "").strip()
            normalized.append(
                {
                    "id": f"api-sports-baseball-{game_id}",
                    "identity": f"{away_name.upper()}|{home_name.upper()}",
                    "away_team": away_name,
                    "home_team": home_name,
                    "commence_time": str(raw.get("date") or ""),
                    "completed": completed,
                    "detail": status_long,
                    "scores": [
                        {"name": away_name, "score": away_score},
                        {"name": home_name, "score": home_score},
                    ],
                }
            )
        return normalized


def _score_total(scores: Any, side: str) -> str:
    if not isinstance(scores, dict):
        return ""
    value = scores.get(side)
    if isinstance(value, dict):
        total = value.get("total")
    else:
        total = value
    return "" if total is None else str(total)
