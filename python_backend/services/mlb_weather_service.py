"""Cached MLB game-weather lookups for strikeout enrichment."""

from __future__ import annotations

from datetime import datetime, timezone
from functools import lru_cache

import requests

from config import HTTP_TIMEOUT_SECONDS
from services.team_normalizer import normalize_team_name

_ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

_MLB_PARK_COORDS: dict[str, tuple[float, float]] = {
    "arizona diamondbacks": (33.4455, -112.0667),
    "athletics": (38.1876, -85.7480),
    "atlanta braves": (33.8908, -84.4677),
    "baltimore orioles": (39.2838, -76.6217),
    "boston red sox": (42.3467, -71.0972),
    "chicago cubs": (41.9484, -87.6553),
    "chicago white sox": (41.8300, -87.6338),
    "cincinnati reds": (39.0979, -84.5082),
    "cleveland guardians": (41.4962, -81.6852),
    "colorado rockies": (39.7559, -104.9942),
    "detroit tigers": (42.3390, -83.0485),
    "houston astros": (29.7573, -95.3555),
    "kansas city royals": (39.0517, -94.4803),
    "los angeles angels": (33.8003, -117.8827),
    "los angeles dodgers": (34.0739, -118.2400),
    "miami marlins": (25.7781, -80.2197),
    "milwaukee brewers": (43.0280, -87.9712),
    "minnesota twins": (44.9817, -93.2776),
    "new york mets": (40.7571, -73.8458),
    "new york yankees": (40.8296, -73.9262),
    "philadelphia phillies": (39.9057, -75.1665),
    "pittsburgh pirates": (40.4469, -80.0057),
    "san diego padres": (32.7076, -117.1570),
    "san francisco giants": (37.7786, -122.3893),
    "seattle mariners": (47.5914, -122.3325),
    "st louis cardinals": (38.6226, -90.1928),
    "tampa bay rays": (27.7682, -82.6534),
    "texas rangers": (32.7473, -97.0847),
    "toronto blue jays": (43.6414, -79.3894),
    "washington nationals": (38.8730, -77.0074),
}

_MLB_TEAM_ALIASES = {
    "ari": "arizona diamondbacks",
    "ath": "athletics",
    "atl": "atlanta braves",
    "bal": "baltimore orioles",
    "bos": "boston red sox",
    "chc": "chicago cubs",
    "cws": "chicago white sox",
    "cin": "cincinnati reds",
    "cle": "cleveland guardians",
    "col": "colorado rockies",
    "det": "detroit tigers",
    "hou": "houston astros",
    "kc": "kansas city royals",
    "laa": "los angeles angels",
    "lad": "los angeles dodgers",
    "mia": "miami marlins",
    "mil": "milwaukee brewers",
    "min": "minnesota twins",
    "nym": "new york mets",
    "nyy": "new york yankees",
    "phi": "philadelphia phillies",
    "pit": "pittsburgh pirates",
    "sd": "san diego padres",
    "sea": "seattle mariners",
    "sf": "san francisco giants",
    "stl": "st louis cardinals",
    "tb": "tampa bay rays",
    "tex": "texas rangers",
    "tor": "toronto blue jays",
    "wsh": "washington nationals",
}


def _parse_start_time(value: object) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _home_team(matchup: str) -> str:
    if "@" not in matchup:
        return ""
    normalized = normalize_team_name(matchup.split("@", 1)[1].strip())
    return _MLB_TEAM_ALIASES.get(normalized, normalized)


def _c_to_f(value: float) -> float:
    return (value * 9.0 / 5.0) + 32.0


@lru_cache(maxsize=512)
def _weather_hour(latitude: float, longitude: float, date_text: str, hour_text: str, archive: bool) -> float | None:
    url = _ARCHIVE_URL if archive else _FORECAST_URL
    response = requests.get(
        url,
        params={
            "latitude": latitude,
            "longitude": longitude,
            "start_date": date_text,
            "end_date": date_text,
            "hourly": "temperature_2m",
            "temperature_unit": "celsius",
            "timezone": "GMT",
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    hourly = payload.get("hourly") if isinstance(payload, dict) else None
    if not isinstance(hourly, dict):
        return None
    times = hourly.get("time")
    temperatures = hourly.get("temperature_2m")
    if not isinstance(times, list) or not isinstance(temperatures, list):
        return None
    wanted = f"{date_text}T{hour_text}"
    for index, time_value in enumerate(times):
        if str(time_value) == wanted and index < len(temperatures):
            try:
                return round(_c_to_f(float(temperatures[index])), 2)
            except (TypeError, ValueError):
                return None
    return None


def game_temperature_f(matchup: str, start_time_utc: object) -> float | None:
    start = _parse_start_time(start_time_utc)
    if start is None:
        return None
    coords = _MLB_PARK_COORDS.get(_home_team(matchup))
    if coords is None:
        return None
    date_text = start.date().isoformat()
    hour_text = start.strftime("%H:00")
    is_archive = start < datetime.now(timezone.utc)
    try:
        return _weather_hour(coords[0], coords[1], date_text, hour_text, is_archive)
    except requests.RequestException:
        return None