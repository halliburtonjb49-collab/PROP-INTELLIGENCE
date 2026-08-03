"""Completed ESPN tennis, PGA, and UFC statistical history."""

from __future__ import annotations

from datetime import date, datetime, timedelta
import hashlib
from typing import Any

import requests

from config import HTTP_TIMEOUT_SECONDS

BASE = "https://site.api.espn.com/apis/site/v2/sports"
CORE = "https://sports.core.api.espn.com/v2/sports"


def _id(sport: str, event: object, player: object) -> str:
    return hashlib.sha256(f"{sport}|{event}|{player}".encode()).hexdigest()[:32]


def _get(sport: str, league: str, target: date) -> list[dict[str, Any]]:
    response = requests.get(
        f"{BASE}/{sport}/{league}/scoreboard",
        params={"dates": target.strftime("%Y%m%d"), "limit": 100},
        headers={"User-Agent": "PropsIntell/1.0 (+https://propsintell.com)"},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    return payload.get("events", []) if isinstance(payload, dict) else []


def tennis_logs(*, tour: str, target_date: date) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for event in _get("tennis", tour.lower(), target_date):
        for grouping in event.get("groupings", []):
            for competition in grouping.get("competitions", []):
                status = competition.get("status", {}).get("type", {})
                try:
                    played = datetime.fromisoformat(
                        str(competition.get("date", "")).replace("Z", "+00:00")
                    ).date()
                except ValueError:
                    continue
                competitors = competition.get("competitors", [])
                if status.get("completed") is not True or played != target_date or len(competitors) != 2:
                    continue
                set_scores = [
                    [float(item.get("value") or 0) for item in player.get("linescores", [])]
                    for player in competitors
                ]
                for index, player in enumerate(competitors):
                    athlete = player.get("athlete", {})
                    opponent_scores = set_scores[1 - index]
                    sets_won = sum(
                        score > (opponent_scores[position] if position < len(opponent_scores) else score)
                        for position, score in enumerate(set_scores[index])
                    )
                    event_id = str(competition.get("id") or "")
                    player_id = str(player.get("id") or athlete.get("id") or "")
                    rows.append({
                        "id": _id("TENNIS", event_id, player_id),
                        "sport": "TENNIS", "league": tour.upper(),
                        "event_id": event_id,
                        "player_id": player_id,
                        "player_name": str(athlete.get("displayName") or ""),
                        "team_id": "", "game_date": played,
                        "stats": {"sets_won": float(sets_won),
                                  "games_won": float(sum(set_scores[index])),
                                  "match_win": float(bool(player.get("winner")))},
                        "source": "ESPN", "raw": competition,
                    })
    return [row for row in rows if row["event_id"] and row["player_id"] and row["player_name"]]


def golf_logs(*, target_date: date) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for event in _get("golf", "pga", target_date):
        event_start = datetime.fromisoformat(str(event.get("date", "")).replace("Z", "+00:00")).date()
        for competition in event.get("competitions", []):
            for player in competition.get("competitors", []):
                athlete = player.get("athlete", {})
                for round_row in player.get("linescores", []):
                    period = int(round_row.get("period") or 0)
                    played = event_start + timedelta(days=max(0, period - 1))
                    if played != target_date:
                        continue
                    holes = round_row.get("linescores", [])
                    relative = [
                        str(hole.get("scoreType", {}).get("displayValue") or "E")
                        for hole in holes
                    ]
                    event_id = f"{event.get('id')}-r{period}"
                    player_id = str(player.get("id") or "")
                    rows.append({
                        "id": _id("PGA", event_id, player_id),
                        "sport": "PGA", "league": "PGA",
                        "event_id": event_id,
                        "player_id": player_id,
                        "player_name": str(athlete.get("displayName") or ""),
                        "team_id": "", "game_date": played,
                        "stats": {
                            "round_score": float(round_row.get("value") or 0),
                            "birdies": float(sum(value.startswith("-") for value in relative)),
                            "bogeys": float(sum(value.startswith("+") for value in relative)),
                            "pars": float(sum(value in {"E", "0"} for value in relative)),
                        },
                        "source": "ESPN", "raw": round_row,
                    })
    return [row for row in rows if row["player_id"] and row["player_name"]]


def _ufc_statistics(*, event_id: str, competition_id: str,
                    player_id: str) -> dict[str, float]:
    response = requests.get(
        f"{CORE}/mma/leagues/ufc/events/{event_id}/competitions/"
        f"{competition_id}/competitors/{player_id}/statistics",
        params={"lang": "en", "region": "us"},
        headers={"User-Agent": "PropsIntell/1.0 (+https://propsintell.com)"},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    values: dict[str, float] = {}
    for category in (payload.get("splits") or {}).get("categories", []):
        for stat in category.get("stats", []):
            try:
                values[str(stat.get("name") or "")] = float(stat.get("value"))
            except (TypeError, ValueError):
                continue
    return values


def ufc_logs(*, target_date: date) -> list[dict[str, object]]:
    """Return completed UFC fighter totals; never use an upcoming event."""
    rows: list[dict[str, object]] = []
    for event in _get("mma", "ufc", target_date):
        event_id = str(event.get("id") or "")
        for competition in event.get("competitions", []):
            status = competition.get("status", {})
            try:
                played = datetime.fromisoformat(
                    str(competition.get("date", "")).replace("Z", "+00:00")
                ).date()
            except ValueError:
                continue
            if status.get("type", {}).get("completed") is not True or played != target_date:
                continue
            competition_id = str(competition.get("id") or "")
            period = max(1, int(status.get("period") or 1))
            elapsed = max(0.0, min(300.0, float(status.get("clock") or 0)))
            fight_time_seconds = float((period - 1) * 300) + elapsed
            for competitor in competition.get("competitors", []):
                athlete = competitor.get("athlete", {})
                player_id = str(competitor.get("id") or athlete.get("id") or "")
                if not event_id or not competition_id or not player_id:
                    continue
                stats = _ufc_statistics(
                    event_id=event_id, competition_id=competition_id,
                    player_id=player_id,
                )
                rows.append({
                    "id": _id("UFC", competition_id, player_id),
                    "sport": "UFC", "league": "UFC",
                    "event_id": competition_id, "player_id": player_id,
                    "player_name": str(athlete.get("displayName") or ""),
                    "team_id": "", "game_date": played,
                    "stats": {
                        "significant_strikes": stats.get("sigStrikesLanded", 0.0),
                        "total_strikes": stats.get("totalStrikesLanded", 0.0),
                        "takedowns": stats.get("takedownsLanded", 0.0),
                        "knockdowns": stats.get("knockDowns", 0.0),
                        "submission_attempts": stats.get("submissions", 0.0),
                        "fight_time_seconds": fight_time_seconds,
                        "fight_win": float(bool(competitor.get("winner"))),
                    },
                    "source": "ESPN", "raw": {
                        "competition": competition, "statistics": stats,
                    },
                })
    return [row for row in rows if row["player_name"]]
