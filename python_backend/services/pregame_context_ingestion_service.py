"""Licensed pregame lineup and injury feeds with append-only observations."""

from __future__ import annotations

import hashlib
import json
import logging
import re
from datetime import date, datetime, timezone
from typing import Iterable

import requests

from config import (
    SPORTSDATAIO_API_KEY,
    SPORTRADAR_ACCESS_LEVEL,
    SPORTRADAR_WNBA_API_KEY,
)
from database.postgres import database_is_configured, get_database_pool

logger = logging.getLogger(__name__)
SPORTSDATAIO_MLB = "https://api.sportsdata.io/v3/mlb/projections/json"
SPORTRADAR_WNBA = f"https://api.sportradar.com/wnba/{SPORTRADAR_ACCESS_LEVEL}/v8/en"
MLB_STATS_API = "https://statsapi.mlb.com/api"
ESPN_SITE_API = "https://site.api.espn.com/apis/site/v2/sports"
ESPN_INJURY_LEAGUES = {
    "WNBA": ("basketball", "wnba"),
    "NBA": ("basketball", "nba"),
    "MLB": ("baseball", "mlb"),
    "NFL": ("football", "nfl"),
    "NHL": ("hockey", "nhl"),
}


def _text(row: dict[str, object], *keys: str) -> str:
    for key in keys:
        value = row.get(key)
        if value not in (None, ""):
            return str(value).strip()
    return ""


def _name(row: dict[str, object]) -> str:
    direct = _text(row, "Name", "PlayerName", "full_name", "FullName", "fullName")
    return direct or " ".join(filter(None, (
        _text(row, "FirstName", "first_name"),
        _text(row, "LastName", "last_name"),
    )))


def _bool(row: dict[str, object], *keys: str) -> bool:
    value = next((row[key] for key in keys if key in row), False)
    return value is True or str(value).strip().lower() in {"true", "1", "yes"}


def _handedness(row: dict[str, object], *keys: str) -> str:
    for key in keys:
        value = row.get(key)
        if isinstance(value, dict):
            text = _text(value, "code", "description")
        else:
            text = str(value or "").strip()
        upper = text.upper()
        if upper.startswith("L"):
            return "L"
        if upper.startswith("R"):
            return "R"
        if upper.startswith("S"):
            return "S"
    return ""


def _fingerprint(item: dict[str, object]) -> str:
    stable = json.dumps(item, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(stable.encode()).hexdigest()


def normalize_sportsdataio_mlb_lineups(payload: object) -> list[dict[str, object]]:
    """Accept both game-nested and projection-style SportsDataIO responses."""
    games = payload if isinstance(payload, list) else []
    observations: list[dict[str, object]] = []
    for game in games:
        if not isinstance(game, dict):
            continue
        game_id = _text(game, "GameID", "GameId")
        event_time = _text(game, "DateTime", "Day")
        home, away = _text(game, "HomeTeam"), _text(game, "AwayTeam")
        nested_found = False
        for side, team, opponent in (("Home", home, away), ("Away", away, home)):
            candidates = game.get(f"{side}Lineup") or game.get(f"{side}TeamLineup") or []
            if isinstance(candidates, dict):
                candidates = list(candidates.values())
            for player in candidates if isinstance(candidates, list) else []:
                if not isinstance(player, dict):
                    continue
                nested_found = True
                observations.append(_mlb_player_observation(
                    player, game_id, event_time, team, opponent,
                    confirmed=_bool(game, "Confirmed", "LineupsConfirmed") or _bool(player, "Confirmed", "BattingOrderConfirmed"),
                ))
        for side, team, opponent in (("Home", home, away), ("Away", away, home)):
            pitcher = game.get(f"{side}TeamStartingPitcher") or game.get(f"{side}StartingPitcher")
            if isinstance(pitcher, dict):
                nested_found = True
                item = _mlb_player_observation(
                    pitcher, game_id, event_time, team, opponent,
                    confirmed=_bool(game, "Confirmed", "LineupsConfirmed") or _bool(pitcher, "Confirmed"),
                )
                item["status"] = "CONFIRMED_STARTER" if item["confirmed"] else "PROJECTED_STARTER"
                item["payload"] = {
                    **item["payload"],
                    "role": "STARTING_PITCHER",
                    "throws": _handedness(pitcher, "pitchHand", "throws"),
                }
                observations.append(item)
        if not nested_found and _name(game):
            observations.append(_mlb_player_observation(
                game, game_id, event_time, _text(game, "Team"), _text(game, "Opponent"),
                confirmed=_bool(game, "Confirmed", "BattingOrderConfirmed"),
            ))
    return [item for item in observations if item["event_id"] and item["player_name"]]


def normalize_official_mlb_schedule(payload: object) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    observations = []
    for day in root.get("dates", []) if isinstance(root.get("dates"), list) else []:
        for game in day.get("games", []) if isinstance(day, dict) else []:
            if not isinstance(game, dict):
                continue
            event_id, event_time = str(game.get("gamePk") or ""), _text(game, "gameDate")
            teams = game.get("teams") if isinstance(game.get("teams"), dict) else {}
            for side in ("home", "away"):
                entry = teams.get(side) if isinstance(teams.get(side), dict) else {}
                opponent_entry = teams.get("away" if side == "home" else "home")
                opponent_entry = opponent_entry if isinstance(opponent_entry, dict) else {}
                pitcher = entry.get("probablePitcher")
                team = entry.get("team") if isinstance(entry.get("team"), dict) else {}
                opponent = opponent_entry.get("team") if isinstance(opponent_entry.get("team"), dict) else {}
                if not isinstance(pitcher, dict):
                    continue
                observations.append({
                    "sport": "MLB", "event_id": event_id, "entity_type": "LINEUP",
                    "provider_player_id": _text(pitcher, "id"), "player_name": _name(pitcher),
                    "team": _text(team, "abbreviation", "name"),
                    "opponent": _text(opponent, "abbreviation", "name"), "event_time": event_time or None,
                    "status": "PROJECTED_STARTER", "confirmed": False,
                    "payload": {"role": "PROBABLE_PITCHER", "starting": True,
                                "throws": _handedness(pitcher, "pitchHand", "throws"),
                                "raw": pitcher},
                })
    return [item for item in observations if item["event_id"] and item["player_name"]]


def normalize_official_mlb_boxscore(
    payload: object, *, event_id: str, event_time: str,
) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    teams = root.get("teams") if isinstance(root.get("teams"), dict) else {}
    observations = []
    for side in ("home", "away"):
        team_row = teams.get(side) if isinstance(teams.get(side), dict) else {}
        opponent_row = teams.get("away" if side == "home" else "home")
        opponent_row = opponent_row if isinstance(opponent_row, dict) else {}
        team = team_row.get("team") if isinstance(team_row.get("team"), dict) else {}
        opponent = opponent_row.get("team") if isinstance(opponent_row.get("team"), dict) else {}
        players = team_row.get("players") if isinstance(team_row.get("players"), dict) else {}
        for row in players.values():
            if not isinstance(row, dict) or not row.get("battingOrder"):
                continue
            person = row.get("person") if isinstance(row.get("person"), dict) else {}
            order_text = str(row.get("battingOrder") or "")
            order = int(order_text) // 100 if order_text.isdigit() else None
            observations.append({
                "sport": "MLB", "event_id": event_id, "entity_type": "LINEUP",
                "provider_player_id": _text(person, "id"), "player_name": _name(person),
                "team": _text(team, "abbreviation", "name"),
                "opponent": _text(opponent, "abbreviation", "name"), "event_time": event_time or None,
                "status": "CONFIRMED_STARTER", "confirmed": True,
                "payload": {"battingOrder": order,
                            "position": _text((row.get("position") or {}), "abbreviation", "name")
                            if isinstance(row.get("position"), dict) else "",
                            "bats": _handedness(row, "batSide", "batHand"),
                            "starting": True, "raw": row},
            })
    return [item for item in observations if item["player_name"]]


def _mlb_player_observation(
    row: dict[str, object], event_id: str, event_time: str,
    team: str, opponent: str, *, confirmed: bool,
) -> dict[str, object]:
    starting = _bool(row, "Starting", "Starter")
    order = _text(row, "BattingOrder", "Order")
    if order and order not in {"0", "None"}:
        starting = True
    status = (
        "CONFIRMED_STARTER" if confirmed and starting
        else "PROJECTED_STARTER" if starting
        else "BENCH"
    )
    return {
        "sport": "MLB", "event_id": event_id, "entity_type": "LINEUP",
        "provider_player_id": _text(row, "PlayerID", "PlayerId"),
        "player_name": _name(row), "team": team or _text(row, "Team"),
        "opponent": opponent or _text(row, "Opponent"), "event_time": event_time or None,
        "status": status, "confirmed": confirmed, "payload": {
            "battingOrder": int(order) if order.isdigit() else None,
            "position": _text(row, "Position"),
            "bats": _handedness(row, "BatHand", "Bats", "batSide", "batHand"),
            "throws": _handedness(row, "PitchHand", "Throws", "pitchHand", "throws"),
            "starting": starting,
            "raw": row,
        },
    }


def normalize_sportradar_wnba_injuries(payload: object, day: date) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    injuries = list(_walk_injuries(root))
    observations = []
    for injury in injuries if isinstance(injuries, list) else []:
        if not isinstance(injury, dict):
            continue
        player = injury.get("player") if isinstance(injury.get("player"), dict) else injury
        status = _text(injury, "status", "desc", "description").upper() or "INJURY_REPORTED"
        observations.append({
            "sport": "WNBA", "event_id": day.isoformat(), "entity_type": "INJURY",
            "provider_player_id": _text(player, "id", "sr_id"), "player_name": _name(player),
            "team": _text(injury, "team", "team_alias"), "opponent": "",
            "event_time": None, "status": status, "confirmed": True,
            "payload": {"comment": _text(injury, "comment"), "description": _text(injury, "desc"),
                        "primaryPosition": _text(player, "primary_position"), "raw": injury},
        })
    return [item for item in observations if item["player_name"]]


def normalize_espn_injuries(
    payload: object, *, sport: str, observed_day: date,
) -> list[dict[str, object]]:
    """Normalize ESPN's current league injury report and its freshness marker."""
    root = payload if isinstance(payload, dict) else {}
    generated_at = _text(root, "timestamp")
    observations: list[dict[str, object]] = [{
        "sport": sport,
        "event_id": observed_day.isoformat(),
        "entity_type": "INJURY_FEED",
        "provider_player_id": "",
        "player_name": "ESPN Injury Report",
        "team": "",
        "opponent": "",
        "event_time": generated_at or None,
        "status": "REPORT_CURRENT",
        "confirmed": True,
        "payload": {"generatedAt": generated_at, "source": "ESPN"},
    }]
    teams = root.get("injuries") if isinstance(root.get("injuries"), list) else []
    for team_row in teams:
        if not isinstance(team_row, dict):
            continue
        team_name = _text(team_row, "displayName", "name")
        injuries = team_row.get("injuries")
        for injury in injuries if isinstance(injuries, list) else []:
            if not isinstance(injury, dict):
                continue
            athlete = injury.get("athlete") if isinstance(injury.get("athlete"), dict) else {}
            athlete_team = athlete.get("team") if isinstance(athlete.get("team"), dict) else {}
            details = injury.get("details") if isinstance(injury.get("details"), dict) else {}
            status = _text(injury, "status")
            if not status:
                injury_type = injury.get("type") if isinstance(injury.get("type"), dict) else {}
                status = _text(injury_type, "description", "name", "abbreviation")
            player_name = _text(athlete, "displayName", "fullName") or _name(athlete)
            if not player_name:
                continue
            observations.append({
                "sport": sport,
                "event_id": observed_day.isoformat(),
                "entity_type": "INJURY",
                "provider_player_id": _text(athlete, "id", "uid"),
                "player_name": player_name,
                "team": _text(athlete_team, "abbreviation", "displayName") or team_name,
                "opponent": "",
                "event_time": _text(injury, "date") or generated_at or None,
                "status": status.upper() or "INJURY_REPORTED",
                "confirmed": True,
                "payload": {
                    "shortComment": _text(injury, "shortComment"),
                    "longComment": _text(injury, "longComment"),
                    "injuryType": _text(details, "type"),
                    "injurySide": _text(details, "side"),
                    "returnDate": _text(details, "returnDate"),
                    "source": "ESPN",
                    "raw": injury,
                },
            })
    return observations


def _walk_injuries(value: object, team: str = ""):
    if isinstance(value, list):
        for item in value:
            yield from _walk_injuries(item, team)
        return
    if not isinstance(value, dict):
        return
    team_value = team or _text(value, "alias", "team_alias") if "players" in value else team
    player = value.get("player")
    if isinstance(player, dict) and any(key in value for key in ("desc", "comment", "status")):
        yield {**value, "team_alias": team_value}
    elif _name(value) and isinstance(value.get("injuries"), list):
        for injury in value["injuries"]:
            if isinstance(injury, dict):
                yield {**injury, "player": value, "team_alias": team_value}
    for key, child in value.items():
        if key == "player":
            continue
        if key == "injuries" and _name(value):
            continue
        yield from _walk_injuries(child, team_value)


def _inside_starter_window(scheduled: object, now: datetime | None = None) -> bool:
    try:
        event_time = datetime.fromisoformat(str(scheduled).replace("Z", "+00:00"))
        if event_time.tzinfo is None:
            event_time = event_time.replace(tzinfo=timezone.utc)
    except ValueError:
        return False
    current = now or datetime.now(timezone.utc)
    seconds = (event_time - current).total_seconds()
    return -1800 <= seconds <= 7200


def _inside_mlb_lineup_window(scheduled: object, now: datetime | None = None) -> bool:
    try:
        event_time = datetime.fromisoformat(str(scheduled).replace("Z", "+00:00"))
        if event_time.tzinfo is None:
            event_time = event_time.replace(tzinfo=timezone.utc)
    except ValueError:
        return False
    seconds = (event_time - (now or datetime.now(timezone.utc))).total_seconds()
    return -1800 <= seconds <= 21600


def normalize_sportradar_wnba_starters(
    payload: object, event_id: str, event_time: str,
) -> list[dict[str, object]]:
    root = payload if isinstance(payload, dict) else {}
    observations = []
    teams = []
    for side in ("home", "away"):
        team = root.get(side)
        if isinstance(team, dict):
            teams.append((team, root.get("away" if side == "home" else "home")))
    for team, opponent in teams:
        opponent = opponent if isinstance(opponent, dict) else {}
        for player in team.get("players", []) if isinstance(team.get("players"), list) else []:
            if not isinstance(player, dict) or not _bool(player, "starter"):
                continue
            observations.append({
                "sport": "WNBA", "event_id": event_id, "entity_type": "LINEUP",
                "provider_player_id": _text(player, "id", "sr_id"),
                "player_name": _name(player), "team": _text(team, "alias", "name"),
                "opponent": _text(opponent, "alias", "name"), "event_time": event_time or None,
                "status": "CONFIRMED_STARTER", "confirmed": True,
                "payload": {"position": _text(player, "primary_position", "position"), "raw": player},
            })
    return [item for item in observations if item["player_name"]]


def persist_pregame_observations(provider: str, observations: Iterable[dict[str, object]]) -> int:
    rows = []
    for observation in observations:
        payload = dict(observation)
        fingerprint = _fingerprint(payload)
        rows.append((payload.get("sport"), payload.get("event_id"), provider,
                     payload.get("entity_type"), payload.get("provider_player_id"),
                     payload.get("player_name"), payload.get("team"), payload.get("opponent"),
                     payload.get("event_time"), payload.get("status"), payload.get("confirmed", False),
                     fingerprint, json.dumps(payload.get("payload") or {}, default=str)))
    if not rows or not database_is_configured():
        return 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("""insert into pregame_context_observations
          (sport,event_id,provider,entity_type,provider_player_id,player_name,team,opponent,
           event_time,status,confirmed,fingerprint,payload)
          values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb)
          on conflict(provider,fingerprint) do nothing""", rows)
        inserted = cursor.rowcount
        connection.commit()
    return max(0, inserted)


def sync_sportsdataio_mlb_lineups(day: date | None = None) -> dict[str, object]:
    target = day or datetime.now(timezone.utc).date()
    if not SPORTSDATAIO_API_KEY:
        return {"provider": "sportsdataio-mlb", "created": 0, "skipped": "not configured"}
    try:
        response = requests.get(
            f"{SPORTSDATAIO_MLB}/StartingLineupsByDate/{target.isoformat()}",
            headers={"Ocp-Apim-Subscription-Key": SPORTSDATAIO_API_KEY}, timeout=20,
        )
        response.raise_for_status()
        observations = normalize_sportsdataio_mlb_lineups(response.json())
        if not observations:
            fallback = requests.get(
                f"{SPORTSDATAIO_MLB}/PlayerGameProjectionStatsByDate/{target.isoformat()}",
                headers={"Ocp-Apim-Subscription-Key": SPORTSDATAIO_API_KEY}, timeout=20,
            )
            fallback.raise_for_status()
            observations = normalize_sportsdataio_mlb_lineups(fallback.json())
        return {"provider": "sportsdataio-mlb", "observations": len(observations),
                "created": persist_pregame_observations("SPORTSDATAIO", observations)}
    except Exception as exc:
        logger.warning("SportsDataIO MLB lineup sync failed: %s", exc)
        return {"provider": "sportsdataio-mlb", "created": 0, "error": str(exc)}


def sync_official_mlb_context(day: date | None = None) -> dict[str, object]:
    target = day or datetime.now(timezone.utc).date()
    try:
        schedule = requests.get(
            f"{MLB_STATS_API}/v1/schedule",
            params={"sportId": 1, "date": target.isoformat(), "hydrate": "probablePitcher,team"},
            timeout=20,
        )
        schedule.raise_for_status()
        payload = schedule.json()
        observations = normalize_official_mlb_schedule(payload)
        games = [game for day_row in payload.get("dates", [])
                 for game in day_row.get("games", []) if isinstance(game, dict)]
        for game in games:
            game_pk = str(game.get("gamePk") or "")
            if not game_pk:
                continue
            if not _inside_mlb_lineup_window(game.get("gameDate")):
                continue
            boxscore = requests.get(f"{MLB_STATS_API}/v1/game/{game_pk}/boxscore", timeout=15)
            if boxscore.status_code in {404, 503}:
                continue
            boxscore.raise_for_status()
            observations.extend(normalize_official_mlb_boxscore(
                boxscore.json(), event_id=game_pk, event_time=_text(game, "gameDate"),
            ))
        return {"provider": "mlb-stats-api", "observations": len(observations),
                "created": persist_pregame_observations("MLB_STATS_API", observations)}
    except Exception as exc:
        logger.warning("Official MLB pregame sync failed: %s", exc)
        return {"provider": "mlb-stats-api", "created": 0, "error": str(exc)}


def sync_sportradar_wnba_injuries(day: date | None = None) -> dict[str, object]:
    target = day or datetime.now(timezone.utc).date()
    if not SPORTRADAR_WNBA_API_KEY:
        return {"provider": "sportradar-wnba", "created": 0, "skipped": "not configured"}
    try:
        response = requests.get(
            f"{SPORTRADAR_WNBA}/league/{target.year}/{target.month}/{target.day}/daily_injuries.json",
            params={"api_key": SPORTRADAR_WNBA_API_KEY}, timeout=20,
        )
        response.raise_for_status()
        observations = normalize_sportradar_wnba_injuries(response.json(), target)
        return {"provider": "sportradar-wnba", "observations": len(observations),
                "created": persist_pregame_observations("SPORTRADAR", observations)}
    except Exception as exc:
        logger.warning("Sportradar WNBA injury sync failed: %s", exc)
        return {"provider": "sportradar-wnba", "created": 0, "error": str(exc)}


def sync_espn_injuries(day: date | None = None) -> dict[str, object]:
    """Persist current ESPN injury reports for every supported major league."""
    target = day or datetime.now(timezone.utc).date()
    total_observations = 0
    total_created = 0
    errors: dict[str, str] = {}
    for sport, (category, league) in ESPN_INJURY_LEAGUES.items():
        try:
            response = requests.get(
                f"{ESPN_SITE_API}/{category}/{league}/injuries",
                timeout=20,
            )
            response.raise_for_status()
            observations = normalize_espn_injuries(
                response.json(), sport=sport, observed_day=target,
            )
            total_observations += len(observations)
            total_created += persist_pregame_observations("ESPN", observations)
        except Exception as exc:
            logger.warning("ESPN %s injury sync failed: %s", sport, exc)
            errors[sport] = str(exc)
    result: dict[str, object] = {
        "provider": "espn-injuries",
        "observations": total_observations,
        "created": total_created,
    }
    if errors:
        result["errors"] = errors
    return result


def sync_sportradar_wnba_starters(day: date | None = None) -> dict[str, object]:
    target = day or datetime.now(timezone.utc).date()
    if not SPORTRADAR_WNBA_API_KEY:
        return {"provider": "sportradar-wnba-starters", "created": 0, "skipped": "not configured"}
    try:
        schedule = requests.get(
            f"{SPORTRADAR_WNBA}/league/{target.year}/{target.month}/{target.day}/schedule.json",
            params={"api_key": SPORTRADAR_WNBA_API_KEY}, timeout=20,
        )
        schedule.raise_for_status()
        games = schedule.json().get("games", [])
        observations: list[dict[str, object]] = []
        for game in games if isinstance(games, list) else []:
            if not isinstance(game, dict) or not game.get("id"):
                continue
            if not _inside_starter_window(game.get("scheduled")):
                continue
            summary = requests.get(
                f"{SPORTRADAR_WNBA}/games/{game['id']}/summary.json",
                params={"api_key": SPORTRADAR_WNBA_API_KEY}, timeout=20,
            )
            if summary.status_code in {404, 429}:
                continue
            summary.raise_for_status()
            observations.extend(normalize_sportradar_wnba_starters(
                summary.json(), str(game["id"]), _text(game, "scheduled"),
            ))
        return {"provider": "sportradar-wnba-starters", "observations": len(observations),
                "created": persist_pregame_observations("SPORTRADAR", observations)}
    except Exception as exc:
        logger.warning("Sportradar WNBA starter sync failed: %s", exc)
        return {"provider": "sportradar-wnba-starters", "created": 0, "error": str(exc)}


def sync_pregame_context() -> list[dict[str, object]]:
    return [sync_official_mlb_context(), sync_sportsdataio_mlb_lineups(), sync_espn_injuries(), sync_sportradar_wnba_injuries(),
            sync_sportradar_wnba_starters()]


def _identity(value: object) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value or "").lower())


def _current_injury_matches(
    matches: list[dict[str, object]],
    current_espn_event_id: str,
) -> list[dict[str, object]]:
    return [
        item
        for item in matches
        if item["entityType"] == "INJURY"
        and (
            item["provider"] != "ESPN"
            or (
                current_espn_event_id
                and item["eventId"] == current_espn_event_id
            )
        )
    ]


def apply_latest_pregame_context(props: list[object]) -> None:
    if not props or not database_is_configured():
        return
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute("""select distinct on(sport,provider,entity_type,event_id,lower(player_name))
                sport,event_id,provider,entity_type,provider_player_id,player_name,team,opponent,event_time,
                status,confirmed,fingerprint,payload,observed_at
                from pregame_context_observations
                where observed_at>=now()-interval '3 days'
                order by sport,provider,entity_type,event_id,lower(player_name),observed_at desc""")
            rows = cursor.fetchall()
    except Exception as exc:
        logger.warning("pregame context lookup unavailable: %s", exc)
        return
    by_player: dict[tuple[str, str], list[dict[str, object]]] = {}
    by_event: dict[tuple[str, str], list[dict[str, object]]] = {}
    current_espn_injury_reports: dict[str, tuple[str, object]] = {}
    for row in rows:
        item = {"sport": row[0], "eventId": row[1], "provider": row[2],
            "entityType": row[3], "providerPlayerId": row[4],
            "playerName": row[5], "team": row[6],
            "opponent": row[7], "eventTime": row[8], "status": row[9],
            "confirmed": bool(row[10]), "payload": row[12] if isinstance(row[12], dict) else {},
            "observedAt": row[13]}
        by_player.setdefault((str(row[0]), _identity(row[5])), []).append(item)
        by_event.setdefault((str(row[0]), str(row[1])), []).append(item)
        if row[2] == "ESPN" and row[3] == "INJURY_FEED":
            report_sport = str(row[0]).upper()
            current = current_espn_injury_reports.get(report_sport)
            if current is None or row[13] > current[1]:
                current_espn_injury_reports[report_sport] = (
                    str(row[1]), row[13]
                )
    for prop in props:
        sport = str(getattr(prop, "sport", "")).upper()
        matches = by_player.get((sport, _identity(getattr(prop, "player", ""))), [])
        current_report = current_espn_injury_reports.get(sport)
        injury_matches = _current_injury_matches(
            matches,
            current_report[0] if current_report else "",
        )
        lineup_matches = [item for item in matches if item["entityType"] == "LINEUP"]
        if injury_matches:
            injury = max(injury_matches, key=lambda item: item["observedAt"])
            injury_status = str(injury["status"] or "").upper()
            prop.injuryStatus = (
                "out" if "OUT" in injury_status or "INACTIVE" in injury_status
                else "doubtful" if "DOUBTFUL" in injury_status
                else "questionable" if "QUESTIONABLE" in injury_status
                else "day-to-day" if "DAY-TO-DAY" in injury_status or "DAY TO DAY" in injury_status
                else "probable" if "PROBABLE" in injury_status
                else "injury reported"
            )
        elif current_report is not None:
            # Absence from a freshly retrieved report is not a medical claim of
            # perfect health; it means the league report lists no current injury.
            prop.injuryStatus = "no injury reported"
        if not matches:
            continue
        latest = max(
            lineup_matches or matches,
            key=lambda item: (
                bool(item["confirmed"]),
                item["provider"] == "MLB_STATS_API",
                item["observedAt"],
            ),
        )
        status = str(latest["status"] or "").upper()
        if sport == "WNBA" and lineup_matches:
            prop.lineupStatus = "confirmed"
        if sport != "MLB" or latest["entityType"] != "LINEUP":
            continue
        prop.lineupStatus = (
            "confirmed" if latest["confirmed"] and "STARTER" in status
            else "projected" if "STARTER" in status
            else "bench"
        )
        event_rows = by_event.get((sport, str(latest["eventId"])), [])
        opponent_team = str(latest["opponent"] or "")
        opposing = [row for row in event_rows if row["entityType"] == "LINEUP"
                    and (not opponent_team or str(row["team"]) == opponent_team)
                    and "STARTER" in str(row["status"])]
        ordered = sorted(opposing, key=lambda row: int(row["payload"].get("battingOrder") or 99))
        prop.mlbProjectedLineupMatchup = {
            "provider": latest["provider"], "eventId": latest["eventId"],
            "playerStatus": status, "confirmed": bool(latest["confirmed"]),
            "team": latest["team"], "opponent": opponent_team,
            "providerPlayerId": latest.get("providerPlayerId") or latest["payload"].get("providerPlayerId"),
            "battingOrder": latest["payload"].get("battingOrder"),
            "position": latest["payload"].get("position"),
            "bats": latest["payload"].get("bats"),
            "throws": latest["payload"].get("throws"),
            "opposingLineup": [{"player": row["playerName"],
                                  "providerPlayerId": row.get("providerPlayerId"),
                                  "battingOrder": row["payload"].get("battingOrder"),
                                  "position": row["payload"].get("position"),
                                  "bats": row["payload"].get("bats"),
                                  "confirmed": row["confirmed"]} for row in ordered],
            "observedAt": latest["observedAt"].isoformat(),
        }
