from typing import Any

import requests

from config import (
    BASE_URL,
    HTTP_TIMEOUT_SECONDS,
    ODDS_API_KEY,
)


def fetch_scores(
    sport_key: str,
    *,
    days_from: int = 1,
) -> list[dict[str, Any]]:
    response = requests.get(
        f"{BASE_URL}/sports/{sport_key}/scores",
        params={
            "apiKey": ODDS_API_KEY,
            "daysFrom": days_from,
        },
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, list):
        raise ValueError("Scores response was not a list.")
    return payload
