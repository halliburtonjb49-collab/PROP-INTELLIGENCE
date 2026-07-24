from typing import Any

from config import BASE_URL
from services.odds_service import _request_with_failover


def fetch_scores(
    sport_key: str,
    *,
    days_from: int = 1,
) -> list[dict[str, Any]]:
    response = _request_with_failover(
        f"{BASE_URL}/sports/{sport_key}/scores",
        {"daysFrom": days_from},
    )
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, list):
        raise ValueError("Scores response was not a list.")
    return payload
