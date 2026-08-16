"""Venue-aware weather context for outdoor prop events.

Weather is fetched once per game, never once per prop. Known stadium
coordinates win; soccer and college events use a conservative geocoding
fallback and remain unadjusted when the location cannot be verified.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from functools import lru_cache
import re
from typing import Iterable

import requests

from config import HTTP_TIMEOUT_SECONDS
from services.mlb_weather_service import _MLB_PARK_COORDS, _MLB_TEAM_ALIASES
from services.team_normalizer import normalize_team_name

_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
_GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
_OUTDOOR_SPORTS = frozenset({"MLB", "NFL", "NCAAF", "CFL", "SOCCER", "MLS"})

_NFL_VENUES: dict[str, tuple[float, float]] = {
    "arizona cardinals": (33.5276, -112.2626),
    "atlanta falcons": (33.7554, -84.4008),
    "baltimore ravens": (39.2780, -76.6227),
    "buffalo bills": (42.7738, -78.7870),
    "carolina panthers": (35.2258, -80.8528),
    "chicago bears": (41.8623, -87.6167),
    "cincinnati bengals": (39.0954, -84.5160),
    "cleveland browns": (41.5061, -81.6995),
    "dallas cowboys": (32.7473, -97.0945),
    "denver broncos": (39.7439, -105.0201),
    "detroit lions": (42.3400, -83.0456),
    "green bay packers": (44.5013, -88.0622),
    "houston texans": (29.6847, -95.4107),
    "indianapolis colts": (39.7601, -86.1639),
    "jacksonville jaguars": (30.3239, -81.6373),
    "kansas city chiefs": (39.0489, -94.4839),
    "las vegas raiders": (36.0908, -115.1830),
    "los angeles chargers": (33.9535, -118.3392),
    "los angeles rams": (33.9535, -118.3392),
    "miami dolphins": (25.9580, -80.2389),
    "minnesota vikings": (44.9738, -93.2581),
    "new england patriots": (42.0909, -71.2643),
    "new orleans saints": (29.9511, -90.0812),
    "new york giants": (40.8135, -74.0745),
    "new york jets": (40.8135, -74.0745),
    "philadelphia eagles": (39.9008, -75.1675),
    "pittsburgh steelers": (40.4468, -80.0158),
    "san francisco 49ers": (37.4030, -121.9700),
    "seattle seahawks": (47.5952, -122.3316),
    "tampa bay buccaneers": (27.9759, -82.5033),
    "tennessee titans": (36.1665, -86.7713),
    "washington commanders": (38.9078, -76.8645),
}

_CFL_VENUES: dict[str, tuple[float, float]] = {
    "bc lions": (49.2768, -123.1119),
    "calgary stampeders": (51.0704, -114.1215),
    "edmonton elks": (53.5592, -113.4767),
    "hamilton tiger cats": (43.2520, -79.8300),
    "montreal alouettes": (45.5101, -73.5808),
    "ottawa redblacks": (45.3982, -75.6831),
    "saskatchewan roughriders": (50.4505, -104.6336),
    "toronto argonauts": (43.6332, -79.4186),
    "winnipeg blue bombers": (49.8077, -97.1430),
}

_FIXED_INDOOR = frozenset({
    "atlanta falcons", "detroit lions", "las vegas raiders",
    "minnesota vikings", "new orleans saints",
    "tampa bay rays",
})
_ROOF_UNKNOWN = frozenset({
    "arizona cardinals", "dallas cowboys", "houston texans",
    "indianapolis colts",
    "arizona diamondbacks", "houston astros", "miami marlins",
    "milwaukee brewers", "seattle mariners", "texas rangers",
    "toronto blue jays",
    "bc lions", "montreal alouettes", "toronto argonauts",
})


def _home_team(matchup: str) -> str:
    if "@" not in matchup:
        return ""
    return normalize_team_name(matchup.split("@", 1)[1].strip())


def _parse_start(value: object) -> datetime | None:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _known_coords(sport: str, home: str) -> tuple[float, float] | None:
    if sport == "MLB":
        return _MLB_PARK_COORDS.get(_MLB_TEAM_ALIASES.get(home, home))
    if sport == "NFL":
        return _NFL_VENUES.get(home)
    if sport == "CFL":
        return _CFL_VENUES.get(home)
    return None


def _place_query(sport: str, home: str) -> str:
    if sport not in {"SOCCER", "MLS", "NCAAF"}:
        return ""
    value = re.sub(r"\b(fc|afc|cf|sc|united|city)\b", " ", home, flags=re.I)
    value = re.sub(r"\s+", " ", value).strip()
    return value if len(value) >= 3 else ""


@lru_cache(maxsize=512)
def _geocode(query: str) -> tuple[float, float, str] | None:
    if not query:
        return None
    try:
        response = requests.get(
            _GEOCODING_URL,
            params={"name": query, "count": 1, "language": "en", "format": "json"},
            timeout=min(8, HTTP_TIMEOUT_SECONDS),
        )
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError):
        return None
    results = payload.get("results") if isinstance(payload, dict) else None
    if not isinstance(results, list) or not results:
        return None
    row = results[0] if isinstance(results[0], dict) else {}
    try:
        latitude = float(row["latitude"])
        longitude = float(row["longitude"])
    except (KeyError, TypeError, ValueError):
        return None
    label = ", ".join(
        str(row.get(key) or "").strip()
        for key in ("name", "admin1", "country")
        if str(row.get(key) or "").strip()
    )
    return latitude, longitude, label or query


def _weather_multiplier(
    sport: str,
    market: str,
    *,
    temperature_f: float,
    wind_mph: float,
    precipitation_probability: float,
) -> float:
    text = str(market or "").lower().replace("_", " ")
    multiplier = 1.0
    if sport in {"NFL", "NCAAF", "CFL"}:
        air_market = any(token in text for token in (
            "pass", "receiv", "reception", "field goal", "kicking",
        ))
        rushing_market = "rush" in text
        if air_market:
            if wind_mph >= 20:
                multiplier -= 0.08
            elif wind_mph >= 15:
                multiplier -= 0.04
            if precipitation_probability >= 60:
                multiplier -= 0.03
            if temperature_f <= 25:
                multiplier -= 0.03
        elif rushing_market and (wind_mph >= 18 or precipitation_probability >= 65):
            multiplier += 0.01
    elif sport in {"SOCCER", "MLS"}:
        if any(token in text for token in ("goal", "shot", "assist", "pass")):
            if wind_mph >= 20:
                multiplier -= 0.04
            elif wind_mph >= 15:
                multiplier -= 0.02
            if precipitation_probability >= 70:
                multiplier -= 0.02
    elif sport == "MLB" and any(token in text for token in (
        "home run", "total base", "hit", "run", "rbi",
    )):
        multiplier += max(-0.05, min(0.05, (temperature_f - 70.0) * 0.002))
    return round(max(0.88, min(1.08, multiplier)), 4)


@lru_cache(maxsize=1024)
def game_weather(sport: str, matchup: str, start_time_utc: str) -> dict[str, object]:
    sport_label = str(sport or "").strip().upper()
    start = _parse_start(start_time_utc)
    home = _home_team(matchup)
    if sport_label not in _OUTDOOR_SPORTS:
        return {"status": "not_applicable", "multiplier": 1.0}
    if not home or start is None:
        return {"status": "location_unavailable", "multiplier": 1.0}
    canonical_home = _MLB_TEAM_ALIASES.get(home, home) if sport_label == "MLB" else home
    if canonical_home in _FIXED_INDOOR:
        return {
            "status": "indoor", "venue": f"{canonical_home.title()} home venue",
            "multiplier": 1.0, "source": "venue_reference",
        }
    coords = _known_coords(sport_label, home)
    location = f"{canonical_home.title()} home venue"
    if coords is None:
        geocoded = _geocode(_place_query(sport_label, home))
        if geocoded is None:
            return {
                "status": "location_unavailable", "venue": canonical_home,
                "multiplier": 1.0,
            }
        coords = geocoded[:2]
        location = geocoded[2]
    date_text = start.date().isoformat()
    try:
        response = requests.get(
            _FORECAST_URL,
            params={
                "latitude": coords[0], "longitude": coords[1],
                "start_date": date_text, "end_date": date_text,
                "hourly": (
                    "temperature_2m,apparent_temperature,"
                    "precipitation_probability,wind_speed_10m,"
                    "wind_gusts_10m,weather_code"
                ),
                "temperature_unit": "fahrenheit",
                "wind_speed_unit": "mph",
                "timezone": "GMT",
            },
            timeout=min(10, HTTP_TIMEOUT_SECONDS),
        )
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError):
        return {
            "status": "weather_unavailable", "venue": location,
            "multiplier": 1.0,
        }
    hourly = payload.get("hourly") if isinstance(payload, dict) else None
    if not isinstance(hourly, dict):
        return {"status": "weather_unavailable", "venue": location, "multiplier": 1.0}
    times = hourly.get("time")
    if not isinstance(times, list) or not times:
        return {"status": "weather_unavailable", "venue": location, "multiplier": 1.0}
    wanted = start.replace(minute=0, second=0, microsecond=0).strftime("%Y-%m-%dT%H:00")
    try:
        index = times.index(wanted)
        temperature = float(hourly["temperature_2m"][index])
        apparent = float(hourly["apparent_temperature"][index])
        precipitation = float(hourly["precipitation_probability"][index])
        wind = float(hourly["wind_speed_10m"][index])
        gust = float(hourly["wind_gusts_10m"][index])
        code = int(hourly["weather_code"][index])
    except (ValueError, KeyError, IndexError, TypeError):
        return {"status": "weather_unavailable", "venue": location, "multiplier": 1.0}
    status = "roof_unknown" if canonical_home in _ROOF_UNKNOWN else "outdoor"
    return {
        "status": status,
        "venue": location,
        "temperatureF": round(temperature, 1),
        "apparentTemperatureF": round(apparent, 1),
        "precipitationProbability": round(precipitation, 1),
        "windSpeedMph": round(wind, 1),
        "windGustMph": round(gust, 1),
        "weatherCode": code,
        "source": "open-meteo",
        "forecastForUtc": start.isoformat(),
        "multiplier": 1.0,
    }


def enrich_outdoor_weather(props: Iterable[object]) -> None:
    values = list(props)
    keys = {
        (
            str(getattr(prop, "sport", "") or "").upper(),
            str(getattr(prop, "matchup", "") or ""),
            str(getattr(prop, "startTimeUtc", "") or ""),
        )
        for prop in values
        if str(getattr(prop, "sport", "") or "").upper() in _OUTDOOR_SPORTS
        and not bool(getattr(prop, "isNeutralSite", False))
    }
    contexts: dict[tuple[str, str, str], dict[str, object]] = {}
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {executor.submit(game_weather, *key): key for key in keys}
        for future in as_completed(futures):
            key = futures[future]
            try:
                contexts[key] = future.result()
            except Exception:
                contexts[key] = {"status": "weather_unavailable", "multiplier": 1.0}

    for prop in values:
        if bool(getattr(prop, "isNeutralSite", False)):
            prop.weatherStatus = "location_unavailable"
            prop.weatherVenue = "Neutral site (venue unavailable)"
            prop.weatherSource = ""
            prop.weatherForecastForUtc = ""
            prop.weatherMultiplier = 1.0
            continue

        key = (
            str(getattr(prop, "sport", "") or "").upper(),
            str(getattr(prop, "matchup", "") or ""),
            str(getattr(prop, "startTimeUtc", "") or ""),
        )
        context = contexts.get(key)
        if not context:
            continue
        status = str(context.get("status") or "weather_unavailable")
        prop.weatherStatus = status
        prop.weatherVenue = str(context.get("venue") or "")
        prop.weatherSource = str(context.get("source") or "")
        if status == "indoor":
            prop.temperatureF = 72.0
        prop.weatherForecastForUtc = str(context.get("forecastForUtc") or "")
        for target, source in (
            ("temperatureF", "temperatureF"),
            ("apparentTemperatureF", "apparentTemperatureF"),
            ("precipitationProbability", "precipitationProbability"),
            ("windSpeedMph", "windSpeedMph"),
            ("windGustMph", "windGustMph"),
            ("weatherCode", "weatherCode"),
        ):
            if context.get(source) is not None:
                setattr(prop, target, context[source])
        multiplier = 1.0
        market = " ".join(str(getattr(prop, field, "") or "") for field in (
            "market", "marketKey", "category",
        ))
        if status == "outdoor":
            multiplier = _weather_multiplier(
                key[0], market,
                temperature_f=float(context.get("temperatureF") or 70),
                wind_mph=float(context.get("windSpeedMph") or 0),
                precipitation_probability=float(
                    context.get("precipitationProbability") or 0
                ),
            )
        prop.weatherMultiplier = multiplier

