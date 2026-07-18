"""Persist official basketball schedules and derive player travel/fatigue."""

from __future__ import annotations

import json
import math
import re
from datetime import datetime, timezone
from math import asin, cos, radians, sin, sqrt
from numbers import Real

from database.postgres import database_is_configured, get_database_pool
from models.intelligence import FatigueRequest, TravelLeg
from providers.historical_data import NbaHistoricalProvider
from services.intelligence_service import fatigue_index

# Arena coordinates are stable reference data; schedules and venue selection are
# refreshed from NBA.com on every run. Coordinates are approximate arena points.
VENUES: dict[str, tuple[float, float, str]] = {
    "ATL": (33.7573, -84.3963, "America/New_York"), "BKN": (40.6826, -73.9754, "America/New_York"),
    "BOS": (42.3662, -71.0621, "America/New_York"), "CHA": (35.2251, -80.8392, "America/New_York"),
    "CHI": (41.8807, -87.6742, "America/Chicago"), "CLE": (41.4965, -81.6882, "America/New_York"),
    "DAL": (32.7905, -96.8103, "America/Chicago"), "DEN": (39.7487, -105.0077, "America/Denver"),
    "DET": (42.3411, -83.0553, "America/Detroit"), "GSW": (37.7680, -122.3877, "America/Los_Angeles"),
    "GSV": (37.7680, -122.3877, "America/Los_Angeles"), "HOU": (29.7508, -95.3621, "America/Chicago"),
    "IND": (39.7640, -86.1555, "America/Indiana/Indianapolis"), "LAC": (33.9535, -118.3392, "America/Los_Angeles"),
    "LAL": (34.0430, -118.2673, "America/Los_Angeles"), "LAS": (34.0430, -118.2673, "America/Los_Angeles"),
    "LVA": (36.0908, -115.1786, "America/Los_Angeles"), "MEM": (35.1382, -90.0506, "America/Chicago"),
    "MIA": (25.7814, -80.1870, "America/New_York"), "MIL": (43.0451, -87.9172, "America/Chicago"),
    "MIN": (44.9795, -93.2760, "America/Chicago"), "NOP": (29.9490, -90.0821, "America/Chicago"),
    "NYK": (40.7505, -73.9934, "America/New_York"), "NYL": (40.6826, -73.9754, "America/New_York"),
    "OKC": (35.4634, -97.5151, "America/Chicago"), "ORL": (28.5392, -81.3839, "America/New_York"),
    "PHI": (39.9012, -75.1720, "America/New_York"), "PHX": (33.4457, -112.0712, "America/Phoenix"),
    "POR": (45.5316, -122.6668, "America/Los_Angeles"), "PDX": (45.5316, -122.6668, "America/Los_Angeles"),
    "SAC": (38.5802, -121.4997, "America/Los_Angeles"), "SAS": (29.4270, -98.4375, "America/Chicago"),
    "SEA": (47.6221, -122.3540, "America/Los_Angeles"), "TOR": (43.6435, -79.3791, "America/Toronto"),
    "UTA": (40.7683, -111.9011, "America/Denver"), "WAS": (38.8981, -77.0209, "America/New_York"),
    "CON": (41.4910, -72.0906, "America/New_York"),
}


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def _json_safe(value: object) -> object:
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    if isinstance(value, Real) and not isinstance(value, bool):
        return value if math.isfinite(float(value)) else None
    return value


def _distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(radians, (*a, *b))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 3958.8 * 2 * asin(sqrt(h))


def sync_schedule_and_fatigue(*, nba_season: str, wnba_season: str) -> dict[str, object]:
    if not database_is_configured():
        return {"persisted": False, "reason": "DATABASE_URL is not configured"}
    provider = NbaHistoricalProvider()
    normalized: list[dict[str, object]] = []
    venues: dict[str, tuple[str, float, float, str]] = {}
    provider_errors: list[dict[str, str]] = []
    for sport, league, season in (("NBA", "00", nba_season), ("WNBA", "10", wnba_season)):
        try:
            schedule = provider.league_schedule(season=season, league_id=league, timeout=20)
        except Exception as exc:
            provider_errors.append({"sport": sport, "error": str(exc)})
            continue
        for row in schedule:
            game_id = str(row.get("gameId") or "").strip()
            home_id, away_id = str(row.get("homeTeam_teamId") or ""), str(row.get("awayTeam_teamId") or "")
            home_code = str(row.get("homeTeam_teamTricode") or "").upper()
            coords = VENUES.get(home_code)
            if not game_id or not home_id or not away_id or coords is None:
                continue
            venue_name = str(row.get("arenaName") or f"{home_code} home venue")
            venue_id = f"{sport.lower()}-{_slug(venue_name)}"
            venues[venue_id] = (venue_name, *coords)
            starts_at = row.get("gameDateTimeUTC") or row.get("gameDateUTC")
            for team_id, opponent_id, is_home in ((home_id, away_id, True), (away_id, home_id, False)):
                normalized.append({"id": f"{sport.lower()}-{game_id}-{team_id}", "sport": sport,
                    "team_id": team_id, "opponent_id": opponent_id, "venue_id": venue_id,
                    "starts_at": starts_at, "is_home": is_home,
                    "status": str(row.get("gameStatusText") or "SCHEDULED"), "raw": _json_safe(row)})
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("""insert into sports_venues(id,name,latitude,longitude,timezone)
            values(%s,%s,%s,%s,%s) on conflict(id) do update set name=excluded.name,
            latitude=excluded.latitude,longitude=excluded.longitude,timezone=excluded.timezone""",
            [(key, *value) for key, value in venues.items()])
        cursor.executemany("""insert into team_schedule(id,sport,team_id,opponent_id,venue_id,starts_at,is_home,status,raw)
            values(%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb) on conflict(id) do update set
            venue_id=excluded.venue_id,starts_at=excluded.starts_at,status=excluded.status,raw=excluded.raw""",
            [(r["id"], r["sport"], r["team_id"], r["opponent_id"], r["venue_id"], r["starts_at"],
              r["is_home"], r["status"], json.dumps(r["raw"], default=str)) for r in normalized])
        connection.commit()
    fatigue_count = _compute_fatigue()
    return {"persisted": True, "venues": len(venues), "scheduleRows": len(normalized),
            "fatigueFeatures": fatigue_count, "providerErrors": provider_errors,
            "usedCachedSchedule": bool(provider_errors)}


def _compute_fatigue() -> int:
    values = []
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select s.id,s.sport,s.team_id,s.starts_at,s.is_home,v.latitude,v.longitude,v.timezone
            from team_schedule s join sports_venues v on v.id=s.venue_id
            where s.starts_at between now() - interval '1 day' and now() + interval '14 days'
            order by s.team_id,s.starts_at""")
        games = cursor.fetchall()
        cursor.execute("""select s.sport,s.team_id,s.starts_at,v.latitude,v.longitude,v.timezone,s.is_home
            from team_schedule s join sports_venues v on v.id=s.venue_id
            where s.starts_at between now() - interval '30 days' and now() + interval '14 days'
            order by s.team_id,s.starts_at""")
        schedule_by_team: dict[tuple[str, str], list[tuple[object, ...]]] = {}
        for row in cursor.fetchall():
            schedule_by_team.setdefault((str(row[0]), str(row[1])), []).append(row[2:])
        cursor.execute("""select sport,team_id,player_id,minutes from historical_basketball_game_logs
            where game_date >= current_date - interval '365 days' and minutes is not null
            order by sport,team_id,player_id,game_date desc""")
        minutes_by_player: dict[tuple[str, str], dict[str, list[float]]] = {}
        for sport, team_id, player_id, minutes in cursor.fetchall():
            team = minutes_by_player.setdefault((str(sport), str(team_id)), {})
            recent = team.setdefault(str(player_id), [])
            if len(recent) < 5:
                recent.append(float(minutes))
        for game_id, sport, team_id, starts_at, is_home, lat, lon, zone in games:
            history = schedule_by_team.get((str(sport), str(team_id)), [])
            prior = [row for row in history if row[0] < starts_at][-5:][::-1]
            legs, previous = [], (float(lat), float(lon), zone)
            for _, plat, plon, pzone, road in reversed(prior):
                current = (float(plat), float(plon), pzone)
                legs.append(TravelLeg(miles=_distance(previous[:2], current[:2]),
                                      timezone_change_hours=abs(_zone_offset(previous[2]) - _zone_offset(current[2])),
                                      is_road_game=not bool(road)))
                previous = current
            rest_days = max(0, (starts_at - prior[0][0]).total_seconds() / 86400) if prior else 3
            consecutive = 1 + sum(1 for row in prior[:3] if (starts_at - row[0]).days <= 4)
            road_games = 0
            for row in prior:
                if row[4]: break
                road_games += 1
            for player_id, minutes in minutes_by_player.get((str(sport), str(team_id)), {}).items():
                result = fatigue_index(FatigueRequest(rest_days=min(14, rest_days), recent_minutes=minutes,
                    travel_legs=legs, consecutive_games=min(10, consecutive)))
                values.append((player_id, game_id, rest_days, sum(x.miles for x in legs),
                               sum(x.timezone_change_hours for x in legs), consecutive, road_games,
                               json.dumps(minutes), result["score"], result["projectionMultiplier"]))
        cursor.executemany("""insert into player_fatigue_features(player_id,game_id,rest_days,travel_miles,
            timezone_change_hours,consecutive_games,consecutive_road_games,recent_minutes,fatigue_score,
            projection_multiplier) values(%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s,%s)
            on conflict(player_id,game_id) do update set rest_days=excluded.rest_days,
            travel_miles=excluded.travel_miles,timezone_change_hours=excluded.timezone_change_hours,
            consecutive_games=excluded.consecutive_games,consecutive_road_games=excluded.consecutive_road_games,
            recent_minutes=excluded.recent_minutes,fatigue_score=excluded.fatigue_score,
            projection_multiplier=excluded.projection_multiplier,computed_at=now()""", values)
        connection.commit()
    return len(values)


def _zone_offset(zone: str) -> float:
    from zoneinfo import ZoneInfo
    offset = datetime.now(timezone.utc).astimezone(ZoneInfo(zone)).utcoffset()
    return (offset.total_seconds() / 3600) if offset else 0.0
