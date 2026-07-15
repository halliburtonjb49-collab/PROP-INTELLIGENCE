from typing import Any

import requests

from config import (
    BASE_URL,
    HTTP_TIMEOUT_SECONDS,
    ODDS_API_KEY,
    ODDS_REGIONS,
    PREFERRED_BOOKMAKERS_CSV,
)


def fetch_events(sport_key: str) -> list[dict[str, Any]]:
    response = requests.get(
        f"{BASE_URL}/sports/{sport_key}/events",
        params={
            "apiKey": ODDS_API_KEY,
            "dateFormat": "iso",
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()

    if isinstance(payload, list):
        return [event for event in payload if isinstance(event, dict)]
    return []


def fetch_event_odds(
    *,
    sport_key: str,
    event_id: str,
    markets: list[str],
) -> dict[str, Any]:
    response = requests.get(
        f"{BASE_URL}/sports/{sport_key}/events/{event_id}/odds",
        params={
            "apiKey": ODDS_API_KEY,
            "regions": ODDS_REGIONS,
            "markets": ",".join(markets),
            "bookmakers": PREFERRED_BOOKMAKERS_CSV,
            "oddsFormat": "american",
            "dateFormat": "iso",
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()

    if isinstance(payload, dict):
        return payload
    return {"bookmakers": []}
