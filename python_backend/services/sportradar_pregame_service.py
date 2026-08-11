"""Quota-aware official Sportradar participation feeds."""
from __future__ import annotations

import logging
import os
import threading
import time
from datetime import date, datetime, timezone
from typing import Callable, Iterable

import requests

from config import SPORTRADAR_ACCESS_LEVEL, SPORTRADAR_API_KEY, SPORTRADAR_WNBA_API_KEY
from services.distributed_cache_service import get_json, set_json

LOGGER = logging.getLogger(__name__)
Persist = Callable[[str, Iterable[dict[str, object]]], int]
_REQUEST_LOCK = threading.Lock()
_LAST_REQUEST_AT = 0.0
_MIN_REQUEST_INTERVAL = max(
    0.0, float(os.getenv("SPORTRADAR_PREGAME_MIN_INTERVAL_SECONDS", "1.05")),
)
_SOCCER_COMPETITIONS = (
    "premier league", "major league soccer", "mls", "ligue 1",
    "bundesliga", "serie a", "laliga", "la liga",
)
_MAX_SOCCER_EVENTS = max(
    1, int(os.getenv("SPORTRADAR_PREGAME_MAX_SOCCER_EVENTS", "20")),
)


class NotEntitledError(RuntimeError):
    pass


def _text(row: dict[str, object], *keys: str) -> str:
    for key in keys:
        value = row.get(key)
        if value not in (None, ""):
            return str(value).strip()
    return ""


def _name(row: dict[str, object]) -> str:
    direct = _text(row, "full_name", "name", "display_name")
    return direct or " ".join(filter(None, (_text(row, "first_name"), _text(row, "last_name"))))


def _bool(row: dict[str, object], *keys: str) -> bool:
    value = next((row[key] for key in keys if key in row), False)
    return value is True or str(value).strip().lower() in {"true", "1", "yes"}


def _request_json(url: str) -> dict[str, object]:
    global _LAST_REQUEST_AT
    with _REQUEST_LOCK:
        wait = _MIN_REQUEST_INTERVAL - (time.monotonic() - _LAST_REQUEST_AT)
        if wait > 0:
            time.sleep(wait)
        response = requests.get(
            url,
            headers={"accept": "application/json", "x-api-key": SPORTRADAR_API_KEY},
            timeout=20,
        )
        _LAST_REQUEST_AT = time.monotonic()
    if response.status_code in {401, 403}:
        raise NotEntitledError(f"not entitled ({response.status_code})")
    if response.status_code == 404:
        return {}
    response.raise_for_status()
    payload = response.json()
    return payload if isinstance(payload, dict) else {}


def _cached_json(key: str, url: str) -> dict[str, object]:
    cached = get_json(key)
    if isinstance(cached, dict):
        return cached
    payload = _request_json(url)
    active = bool(payload.get("games") or payload.get("sport_events"))
    set_json(key, payload, ttl_seconds=600 if active else 14_400)
    return payload


def _inside_window(scheduled: object, *, before_seconds: int, now: datetime | None = None) -> bool:
    try:
        event_time = datetime.fromisoformat(str(scheduled).replace("Z", "+00:00"))
        if event_time.tzinfo is None:
            event_time = event_time.replace(tzinfo=timezone.utc)
    except ValueError:
        return False
    seconds = (event_time - (now or datetime.now(timezone.utc))).total_seconds()
    return -1800 <= seconds <= before_seconds


def _team_players(root: dict[str, object]):
    for side in ("home", "away"):
        team = root.get(side)
        if not isinstance(team, dict):
            continue
        opponent = root.get("away" if side == "home" else "home")
        yield team, opponent if isinstance(opponent, dict) else {}


def normalize_basketball_summary(payload: object, *, sport: str, event_id: str, event_time: str) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    observations: list[dict[str, object]] = []
    for team, opponent in _team_players(root):
        players = team.get("players") if isinstance(team.get("players"), list) else []
        for player in players:
            if not isinstance(player, dict) or not _name(player):
                continue
            active = _bool(player, "active")
            starter = _bool(player, "starter")
            inactive_reason = _text(player, "not_playing_reason", "not_playing_description")
            if inactive_reason or ("active" in player and not active):
                status = "INACTIVE"
            elif starter:
                status = "CONFIRMED_STARTER"
            elif active:
                status = "BENCH"
            else:
                status = "UNKNOWN"
            observations.append({
                "sport": sport, "event_id": event_id, "entity_type": "LINEUP",
                "provider_player_id": _text(player, "id", "sr_id"), "player_name": _name(player),
                "team": _text(team, "alias", "name"), "opponent": _text(opponent, "alias", "name"),
                "event_time": event_time or None, "status": status, "confirmed": status != "UNKNOWN",
                "payload": {"role": status, "position": _text(player, "primary_position", "position"), "inactiveReason": inactive_reason, "raw": player},
            })
    return observations


def normalize_nfl_roster(payload: object, *, event_id: str, event_time: str) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    observations: list[dict[str, object]] = []
    for team, opponent in _team_players(root):
        players = team.get("players") if isinstance(team.get("players"), list) else team.get("roster")
        players = players if isinstance(players, list) else []
        for player in players:
            if not isinstance(player, dict) or not _name(player):
                continue
            game_status = _text(player, "in_game_status", "game_status", "status").lower()
            started = _bool(player, "starter", "started") or game_status == "started"
            inactive = game_status in {"deactivated", "dnp", "inactive", "out"}
            active = game_status in {"active", "played", "probable"}
            status = "INACTIVE" if inactive else "CONFIRMED_STARTER" if started else "CONFIRMED_ACTIVE" if active else "UNKNOWN"
            observations.append({
                "sport": "NFL", "event_id": event_id, "entity_type": "ACTIVE_LIST",
                "provider_player_id": _text(player, "id", "sr_id"), "player_name": _name(player),
                "team": _text(team, "alias", "name"), "opponent": _text(opponent, "alias", "name"),
                "event_time": event_time or None, "status": status, "confirmed": status != "UNKNOWN",
                "payload": {"role": status, "position": _text(player, "position", "primary_position"), "raw": player},
            })
    return observations


def normalize_nhl_summary(payload: object, *, event_id: str, event_time: str) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    observations: list[dict[str, object]] = []
    for team, opponent in _team_players(root):
        players = team.get("players") if isinstance(team.get("players"), list) else []
        for player in players:
            if not isinstance(player, dict) or not _name(player):
                continue
            scratched = _bool(player, "scratched")
            starter = _bool(player, "starter")
            played = _bool(player, "played")
            position = _text(player, "primary_position", "position")
            status = "SCRATCHED" if scratched else "CONFIRMED_STARTER" if starter else "CONFIRMED_ACTIVE" if played else "UNKNOWN"
            observations.append({
                "sport": "NHL", "event_id": event_id, "entity_type": "LINEUP",
                "provider_player_id": _text(player, "id", "sr_id"), "player_name": _name(player),
                "team": _text(team, "alias", "name"), "opponent": _text(opponent, "alias", "name"),
                "event_time": event_time or None, "status": status, "confirmed": status != "UNKNOWN",
                "payload": {"role": "STARTING_GOALIE" if starter and position == "G" else status, "position": position, "raw": player},
            })
    return observations


def normalize_soccer_lineups(payload: object, *, event_id: str, event_time: str) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    conditions = root.get("sport_event_conditions") if isinstance(root.get("sport_event_conditions"), dict) else {}
    lineup_conditions = conditions.get("lineups") if isinstance(conditions.get("lineups"), dict) else {}
    confirmed = _bool(lineup_conditions, "confirmed")
    lineups = root.get("lineups") if isinstance(root.get("lineups"), list) else []
    teams: list[dict[str, object]] = [row for row in lineups if isinstance(row, dict)]
    observations: list[dict[str, object]] = []
    for lineup in teams:
        competitor = lineup.get("competitor") if isinstance(lineup.get("competitor"), dict) else {}
        opponent = next((row.get("competitor") for row in teams if row is not lineup and isinstance(row.get("competitor"), dict)), {})
        formation = lineup.get("formation") if isinstance(lineup.get("formation"), dict) else {}
        formation_type = _text(formation, "type") or _text(lineup, "formation")
        players = lineup.get("players") if isinstance(lineup.get("players"), list) else []
        for player in players:
            if not isinstance(player, dict) or not _name(player):
                continue
            status = "STARTING_XI" if _bool(player, "starter") else "SUBSTITUTE"
            observations.append({
                "sport": "SOCCER", "event_id": event_id, "entity_type": "TEAM_SHEET",
                "provider_player_id": _text(player, "id", "sr_id"), "player_name": _name(player),
                "team": _text(competitor, "abbreviation", "name"), "opponent": _text(opponent, "abbreviation", "name"),
                "event_time": event_time or None, "status": status, "confirmed": confirmed,
                "payload": {"role": status, "position": _text(player, "position", "type"), "formation": formation_type, "raw": player},
            })
        if formation_type:
            observations.append({
                "sport": "SOCCER", "event_id": event_id, "entity_type": "TEAM_SHEET",
                "provider_player_id": "", "player_name": f"{_text(competitor, 'name')} formation",
                "team": _text(competitor, "abbreviation", "name"), "opponent": _text(opponent, "abbreviation", "name"),
                "event_time": event_time or None, "status": "TEAM_CONFIRMED", "confirmed": confirmed,
                "payload": {"formation": formation_type},
            })
    return observations


def _sync_scheduled_summaries(*, sport: str, target: date, base: str, schedule_path: str, normalizer: Callable[..., list[dict[str, object]]], persist: Persist) -> dict[str, object]:
    schedule = _cached_json(f"pregame:sportradar:{sport}:schedule:{target.isoformat()}", f"{base}/{schedule_path}")
    games = schedule.get("games") if isinstance(schedule.get("games"), list) else []
    observations: list[dict[str, object]] = []
    attempted = 0
    for game in games:
        if not isinstance(game, dict) or not game.get("id") or not _inside_window(game.get("scheduled"), before_seconds=7200):
            continue
        attempted += 1
        summary = _request_json(f"{base}/games/{game['id']}/summary.json")
        kwargs = {"event_id": str(game["id"]), "event_time": _text(game, "scheduled")}
        if sport in {"NBA", "WNBA"}:
            kwargs["sport"] = sport
        observations.extend(normalizer(summary, **kwargs))
    return {"provider": f"sportradar-{sport.lower()}-pregame", "games": len(games), "attempted": attempted, "observations": len(observations), "created": persist("SPORTRADAR", observations)}


def _sync_nfl(persist: Persist) -> dict[str, object]:
    base = f"https://api.sportradar.com/nfl/official/{SPORTRADAR_ACCESS_LEVEL}/v7/en"
    schedule = _cached_json("pregame:sportradar:nfl:current-week", f"{base}/games/current_week/schedule.json")
    games = schedule.get("games") if isinstance(schedule.get("games"), list) else []
    observations: list[dict[str, object]] = []
    attempted = 0
    for game in games:
        if not isinstance(game, dict) or not game.get("id") or not _inside_window(game.get("scheduled"), before_seconds=10_800):
            continue
        attempted += 1
        roster = _request_json(f"{base}/games/{game['id']}/roster.json")
        observations.extend(normalize_nfl_roster(roster, event_id=str(game["id"]), event_time=_text(game, "scheduled")))
    return {"provider": "sportradar-nfl-pregame", "games": len(games), "attempted": attempted, "observations": len(observations), "created": persist("SPORTRADAR", observations)}


def _supported_soccer_event(event: dict[str, object]) -> bool:
    context = event.get("sport_event_context") if isinstance(event.get("sport_event_context"), dict) else {}
    competition = context.get("competition") if isinstance(context.get("competition"), dict) else {}
    season = context.get("season") if isinstance(context.get("season"), dict) else {}
    label = f"{_text(competition, 'name')} {_text(season, 'name')}".lower()
    return any(name in label for name in _SOCCER_COMPETITIONS)


def _sync_soccer(target: date, persist: Persist) -> dict[str, object]:
    base = f"https://api.sportradar.com/soccer/{SPORTRADAR_ACCESS_LEVEL}/v4/en"
    schedule = _cached_json(f"pregame:sportradar:soccer:schedule:{target.isoformat()}", f"{base}/schedules/{target.isoformat()}/schedule.json")
    events = schedule.get("sport_events") if isinstance(schedule.get("sport_events"), list) else []
    supported_events = [event for event in events if isinstance(event, dict) and _supported_soccer_event(event)]
    supported_events = sorted(supported_events, key=lambda event: _text(event, "start_time"))[:_MAX_SOCCER_EVENTS]
    observations: list[dict[str, object]] = []
    attempted = 0
    for event in supported_events:
        if not isinstance(event, dict) or not event.get("id") or not _inside_window(event.get("start_time"), before_seconds=7200):
            continue
        attempted += 1
        lineup = _request_json(f"{base}/sport_events/{event['id']}/lineups.json")
        observations.extend(normalize_soccer_lineups(lineup, event_id=str(event["id"]), event_time=_text(event, "start_time")))
    return {"provider": "sportradar-soccer-pregame", "events": len(events), "supportedEvents": len(supported_events), "attempted": attempted, "observations": len(observations), "created": persist("SPORTRADAR", observations)}


def sync_sportradar_pregame(persist: Persist, day: date | None = None) -> list[dict[str, object]]:
    if not SPORTRADAR_API_KEY:
        return [{"provider": "sportradar-pregame", "created": 0, "skipped": "not configured"}]
    target = day or datetime.now(timezone.utc).date()
    jobs: list[tuple[str, Callable[[], dict[str, object]]]] = [
        ("nba", lambda: _sync_scheduled_summaries(sport="NBA", target=target, base=f"https://api.sportradar.com/nba/{SPORTRADAR_ACCESS_LEVEL}/v8/en", schedule_path=f"games/{target.year}/{target.month}/{target.day}/schedule.json", normalizer=normalize_basketball_summary, persist=persist)),
        ("nfl", lambda: _sync_nfl(persist)),
        ("nhl", lambda: _sync_scheduled_summaries(sport="NHL", target=target, base=f"https://api.sportradar.com/nhl/{SPORTRADAR_ACCESS_LEVEL}/v7/en", schedule_path=f"games/{target.year}/{target.month}/{target.day}/schedule.json", normalizer=normalize_nhl_summary, persist=persist)),
        ("soccer", lambda: _sync_soccer(target, persist)),
    ]
    if not SPORTRADAR_WNBA_API_KEY:
        jobs.insert(0, ("wnba", lambda: _sync_scheduled_summaries(sport="WNBA", target=target, base=f"https://api.sportradar.com/wnba/{SPORTRADAR_ACCESS_LEVEL}/v8/en", schedule_path=f"games/{target.year}/{target.month}/{target.day}/schedule.json", normalizer=normalize_basketball_summary, persist=persist)))
    results: list[dict[str, object]] = []
    for label, job in jobs:
        try:
            results.append(job())
        except NotEntitledError as exc:
            results.append({"provider": f"sportradar-{label}-pregame", "created": 0, "skipped": str(exc)})
        except Exception as exc:
            LOGGER.warning("Sportradar %s pregame sync failed: %s", label, exc)
            results.append({"provider": f"sportradar-{label}-pregame", "created": 0, "error": str(exc)})
    return results
