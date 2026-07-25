"""Historical soccer player statistics from ESPN's public site feed.

This is a coverage fallback for leagues that are not included in the
configured Sportmonks subscription. It intentionally fetches only completed
events and only the counting statistics used by the baseline projection model.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime
import logging
from typing import Iterator

import requests

from config import HTTP_TIMEOUT_SECONDS

logger = logging.getLogger(__name__)

_BASE_URL = "https://site.api.espn.com/apis/site/v2/sports/soccer"

# MLS is the known gap in the current Sportmonks subscription. Additional
# leagues can be added here only after their ESPN roster-stat payloads are
# verified against the normalizer.
FALLBACK_LEAGUES: dict[str, tuple[str, str]] = {
    "soccer_usa_mls": ("usa.1", "779"),
}


class EspnSoccerStatisticsProvider:
    """Fetch completed ESPN soccer events and their player box-score stats."""

    def _json(self, url: str, *, params: dict[str, object] | None = None) -> dict:
        response = requests.get(
            url,
            params=params,
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        return payload if isinstance(payload, dict) else {}

    def _event_summary(
        self,
        *,
        espn_league: str,
        sportmonks_league_id: str,
        event: dict,
    ) -> dict | None:
        event_id = str(event.get("id") or "").strip()
        if not event_id:
            return None
        payload = self._json(
            f"{_BASE_URL}/{espn_league}/summary",
            params={"event": event_id},
        )
        header = payload.get("header") if isinstance(payload.get("header"), dict) else {}
        competitions = header.get("competitions")
        competition = competitions[0] if isinstance(competitions, list) and competitions else {}
        status = competition.get("status") if isinstance(competition, dict) else {}
        status_type = status.get("type") if isinstance(status, dict) else {}
        if status_type.get("completed") is not True:
            return None
        return {
            "id": event_id,
            "league_id": sportmonks_league_id,
            "starting_at": event.get("date") or competition.get("date"),
            "rosters": payload.get("rosters") or [],
        }

    def completed_fixtures(
        self,
        *,
        start_date: date,
        end_date: date,
        league_keys: tuple[str, ...] | None = None,
    ) -> Iterator[dict]:
        selected = league_keys or tuple(FALLBACK_LEAGUES)
        for league_key in selected:
            league = FALLBACK_LEAGUES.get(league_key)
            if league is None:
                continue
            espn_league, sportmonks_league_id = league
            payload = self._json(
                f"{_BASE_URL}/{espn_league}/scoreboard",
                params={
                    "dates": (
                        f"{start_date.strftime('%Y%m%d')}-"
                        f"{end_date.strftime('%Y%m%d')}"
                    ),
                    "limit": 1000,
                },
            )
            events = []
            for event in payload.get("events", []):
                if not isinstance(event, dict):
                    continue
                try:
                    event_date = datetime.fromisoformat(
                        str(event.get("date") or "").replace("Z", "+00:00")
                    ).date()
                except ValueError:
                    continue
                if start_date <= event_date <= end_date:
                    events.append(event)
            # ESPN can reset highly parallel site-API connections. Three workers
            # keeps the fallback quick without behaving like a burst scraper.
            with ThreadPoolExecutor(max_workers=3) as executor:
                pending = [
                    executor.submit(
                        self._event_summary,
                        espn_league=espn_league,
                        sportmonks_league_id=sportmonks_league_id,
                        event=event,
                    )
                    for event in events
                ]
                for future in as_completed(pending):
                    try:
                        fixture = future.result()
                        if fixture is not None:
                            yield fixture
                    except Exception:
                        logger.warning(
                            "ESPN soccer event summary failed for %s",
                            league_key,
                            exc_info=True,
                        )
