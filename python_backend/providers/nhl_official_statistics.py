"""NHL player game logs from the league's own public API.

Preferred over the ESPN box score for hockey because the field names here are
verified against live responses and because the goalie lines carry shots
against split by strength state, which the shots-faced model needs and no
box-score aggregate provides.

Two endpoints are used:

    /v1/schedule/{date}                    completed games for a date
    /v1/gamecenter/{gameId}/boxscore       player lines for one game

Skater ice time arrives as a single total. Splitting it by strength state
needs the shift charts cross-referenced against penalty windows, which this
module deliberately does not attempt: a guess at which shifts were on the
power play would be worse than an honest total.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Iterable, Mapping

import requests

from config import HTTP_TIMEOUT_SECONDS

_WEB_BASE = "https://api-web.nhle.com/v1"

# Game states the schedule uses for a finished game. "OFF" is the final state
# once the box score is official; "FINAL" appears briefly before it.
COMPLETED_GAME_STATES = {"OFF", "FINAL"}


def _number(value: object) -> float | None:
    text = str(value if value is not None else "").strip()
    if not text or text in {"-", "--"}:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _minutes_from_clock(value: object) -> float | None:
    """Convert "18:24" to decimal minutes, since every rate is per minute."""

    text = str(value if value is not None else "").strip()
    if not text:
        return None
    if ":" not in text:
        return _number(text)
    minutes, _, seconds = text.partition(":")
    whole = _number(minutes)
    part = _number(seconds)
    if whole is None:
        return None
    return round(whole + ((part or 0.0) / 60.0), 4)


def _saves_and_shots(value: object) -> tuple[float | None, float | None]:
    """Split a goalie's "20/26" saves-over-shots pair into its two numbers."""

    text = str(value if value is not None else "").strip()
    if "/" not in text:
        return None, None
    saves, _, shots = text.partition("/")
    return _number(saves), _number(shots)


def _player_name(value: object) -> str:
    """Names arrive as {"default": "K. Lankinen"} rather than a bare string."""

    if isinstance(value, Mapping):
        return str(value.get("default") or "").strip()
    return str(value or "").strip()


def parse_skater(line: Mapping[str, object]) -> dict[str, float]:
    stats: dict[str, float] = {}
    for source, target in (
        ("goals", "goals"),
        ("assists", "assists"),
        ("points", "points"),
        ("sog", "shots_on_goal"),
        ("hits", "hits"),
        ("blockedShots", "blocked_shots"),
        ("powerPlayGoals", "power_play_goals"),
        ("pim", "penalty_minutes"),
        ("shifts", "shifts"),
        ("giveaways", "giveaways"),
        ("takeaways", "takeaways"),
    ):
        value = _number(line.get(source))
        if value is not None:
            stats[target] = value
    ice_time = _minutes_from_clock(line.get("toi"))
    if ice_time is not None:
        stats["time_on_ice"] = ice_time
    return stats


def parse_goalie(line: Mapping[str, object]) -> dict[str, float]:
    stats: dict[str, float] = {}
    for source, target in (
        ("saves", "saves"),
        ("shotsAgainst", "shots_against"),
        ("goalsAgainst", "goals_against"),
    ):
        value = _number(line.get(source))
        if value is not None:
            stats[target] = value
    ice_time = _minutes_from_clock(line.get("toi"))
    if ice_time is not None:
        stats["time_on_ice"] = ice_time
    # Strength splits arrive as "saves/shots" strings. Shots against by state
    # is the term the saves model actually varies on.
    for source, prefix in (
        ("evenStrengthShotsAgainst", "even_strength"),
        ("powerPlayShotsAgainst", "power_play"),
        ("shorthandedShotsAgainst", "short_handed"),
    ):
        saves, shots = _saves_and_shots(line.get(source))
        if saves is not None:
            stats[f"{prefix}_saves"] = saves
        if shots is not None:
            stats[f"{prefix}_shots_against"] = shots
    return stats


def parse_boxscore(
    payload: Mapping[str, object],
    *,
    game_id: str,
    game_date: str,
) -> list[dict[str, object]]:
    """Turn one game's box score into per-player rows."""

    by_team = payload.get("playerByGameStats")
    if not isinstance(by_team, Mapping):
        return []

    rows: list[dict[str, object]] = []
    for team_key, team_field in (("awayTeam", "awayTeam"), ("homeTeam", "homeTeam")):
        side = by_team.get(team_key)
        if not isinstance(side, Mapping):
            continue
        team = payload.get(team_field)
        team_id = (
            str(team.get("id") or "") if isinstance(team, Mapping) else ""
        )
        for section, parser in (
            ("forwards", parse_skater),
            ("defense", parse_skater),
            ("goalies", parse_goalie),
        ):
            entries = side.get(section)
            for line in entries if isinstance(entries, list) else []:
                if not isinstance(line, Mapping):
                    continue
                player_id = str(line.get("playerId") or "").strip()
                name = _player_name(line.get("name"))
                stats = parser(line)
                if not player_id or not name or not stats:
                    continue
                rows.append({
                    "sport": "NHL",
                    "event_id": str(game_id),
                    "player_id": player_id,
                    "player_name": name,
                    "team_id": team_id,
                    "game_date": game_date,
                    "position": str(line.get("position") or ""),
                    "stats": stats,
                    "source": "NHL",
                })
    return rows


@dataclass(frozen=True)
class ScheduledGame:
    game_id: str
    game_date: str
    game_type: int


def parse_schedule(payload: Mapping[str, object]) -> list[ScheduledGame]:
    """Completed games from a schedule response.

    gameType is carried through because the postseason is type 3 and a caller
    may want to weight or separate it rather than blend it with the regular
    season.
    """

    games: list[ScheduledGame] = []
    for week in payload.get("gameWeek", []) if isinstance(payload, Mapping) else []:
        if not isinstance(week, Mapping):
            continue
        day = str(week.get("date") or "")
        for game in week.get("games", []) if isinstance(week.get("games"), list) else []:
            if not isinstance(game, Mapping):
                continue
            if str(game.get("gameState") or "").upper() not in COMPLETED_GAME_STATES:
                continue
            game_id = str(game.get("id") or "").strip()
            if not game_id:
                continue
            games.append(
                ScheduledGame(
                    game_id=game_id,
                    game_date=str(game.get("gameDate") or day),
                    game_type=int(game.get("gameType") or 0),
                )
            )
    return games


class NhlOfficialStatisticsProvider:
    """Fetch completed NHL player box scores from the league's public API."""

    def _json(self, url: str) -> dict:
        response = requests.get(
            url,
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

    def completed_games(self, target_date: date) -> list[ScheduledGame]:
        payload = self._json(f"{_WEB_BASE}/schedule/{target_date.isoformat()}")
        return [
            game
            for game in parse_schedule(payload)
            if game.game_date == target_date.isoformat()
        ]

    def daily_game_logs(
        self,
        *,
        target_date: date,
        include_postseason: bool = True,
    ) -> list[dict[str, object]]:
        rows: list[dict[str, object]] = []
        for game in self.completed_games(target_date):
            if not include_postseason and game.game_type == 3:
                continue
            payload = self._json(
                f"{_WEB_BASE}/gamecenter/{game.game_id}/boxscore"
            )
            rows.extend(
                parse_boxscore(
                    payload,
                    game_id=game.game_id,
                    game_date=game.game_date,
                )
            )
        return rows


def iter_daily_logs(
    provider: NhlOfficialStatisticsProvider,
    dates: Iterable[date],
) -> Iterable[dict[str, object]]:
    for target in dates:
        yield from provider.daily_game_logs(target_date=target)
