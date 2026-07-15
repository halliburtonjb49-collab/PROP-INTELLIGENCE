from datetime import datetime, timezone
from typing import Any

from services.team_normalizer import normalize_team_name

MAX_TIME_DIFFERENCE_MINUTES = 180


def _parse_datetime(value: str) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(
            value.replace("Z", "+00:00")
        )
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return None


def _extract_api_sports_game(
    raw: dict[str, Any],
) -> dict[str, str]:
    teams = raw.get("teams", {})
    date_data = raw.get("date", {})
    return {
        "id": str(raw.get("id", "")),
        "home_team": str(
            teams.get("home", {}).get("name", "")
        ),
        "away_team": str(
            teams.get("away", {}).get("name", "")
        ),
        "start_time": str(
            date_data.get("date")
            or raw.get("date")
            or ""
        ),
    }


def match_wnba_game(
    *,
    odds_home_team: str,
    odds_away_team: str,
    odds_start_time: str,
    api_sports_games: list[dict[str, Any]],
) -> str | None:
    target_home = normalize_team_name(odds_home_team)
    target_away = normalize_team_name(odds_away_team)
    target_time = _parse_datetime(odds_start_time)

    best_game_id: str | None = None
    best_difference: float | None = None

    for raw_game in api_sports_games:
        game = _extract_api_sports_game(raw_game)
        game_id = game["id"]
        if not game_id:
            continue

        home = normalize_team_name(game["home_team"])
        away = normalize_team_name(game["away_team"])
        teams_match = (
            home == target_home
            and away == target_away
        )
        if not teams_match:
            continue

        game_time = _parse_datetime(game["start_time"])
        if target_time is None or game_time is None:
            return game_id

        difference = abs(
            (game_time - target_time).total_seconds()
        ) / 60
        if difference > MAX_TIME_DIFFERENCE_MINUTES:
            continue

        if (
            best_difference is None
            or difference < best_difference
        ):
            best_difference = difference
            best_game_id = game_id

    return best_game_id
