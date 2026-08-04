"""SportMonks Cricket API (v2.0) diagnostic probe.

The Cricket API's public docs never explicitly confirm player-level prop
markets (runs scored, wickets taken, with a real over/under line) exist,
as opposed to match-winner/outright odds only — the same ambiguous
pattern that turned out to be moneyline-only for balldontlie's tennis
API. Rather than guess at a normalization schema, this module fetches
one real fixture's odds and logs the raw market/bookmaker shape so the
next sync tells us definitively what SportMonks actually returns before
a full integration is built against it.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

import requests

from config import CRICKETDATA_API_KEY, HTTP_TIMEOUT_SECONDS, SPORTMONKS_CRICKET_API_KEY

LOGGER = logging.getLogger(__name__)
BASE_URL = "https://cricket.sportmonks.com/api/v2.0"


def _get(path: str, params: dict[str, object]) -> dict[str, object]:
    if not SPORTMONKS_CRICKET_API_KEY:
        raise RuntimeError("SPORTMONKS_CRICKET_API_KEY is not configured")
    response = requests.get(
        f"{BASE_URL}/{path.lstrip('/')}",
        params={**params, "api_token": SPORTMONKS_CRICKET_API_KEY},
        timeout=HTTP_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, dict):
        raise RuntimeError("SportMonks cricket returned a non-object payload")
    return payload


def probe_cricket_odds_shape() -> dict[str, object]:
    """One-shot diagnostic: fetch upcoming fixtures with odds included and
    log the real shape. Never raises past logging so a wrong endpoint
    guess just reports 'unavailable' instead of failing the sync."""
    if not SPORTMONKS_CRICKET_API_KEY:
        return {"status": "not_configured"}
    now = datetime.now(timezone.utc)
    try:
        fixtures_payload = _get(
            "fixtures",
            {
                "filter[starts_between]": (
                    f"{now.date().isoformat()},"
                    f"{(now + timedelta(days=10)).date().isoformat()}"
                ),
                "include": "localteam,visitorteam,odds",
            },
        )
    except Exception as exc:
        LOGGER.warning("sportmonks cricket fixtures probe failed error=%s", exc)
        return {"status": "error", "error": str(exc)}

    fixtures = fixtures_payload.get("data")
    fixtures_list = fixtures if isinstance(fixtures, list) else []
    LOGGER.warning(
        "sportmonks cricket probe fixtures count=%s topLevelKeys=%s sample=%r",
        len(fixtures_list),
        sorted(fixtures_payload.keys()),
        fixtures_list[0] if fixtures_list else None,
    )
    if not fixtures_list:
        return {"status": "no_fixtures", "topLevelKeys": sorted(fixtures_payload.keys())}

    first = fixtures_list[0]
    odds = first.get("odds") if isinstance(first, dict) else None
    LOGGER.warning(
        "sportmonks cricket probe odds type=%s sample=%r",
        type(odds).__name__,
        odds,
    )
    return {
        "status": "ok",
        "fixtureCount": len(fixtures_list),
        "hasOdds": bool(odds),
    }


def cricketdata_health_check() -> dict[str, object]:
    """CricketData.org is stats-only (no betting odds); this just confirms
    the key works so it can supply context data later if useful."""
    if not CRICKETDATA_API_KEY:
        return {"status": "not_configured"}
    try:
        response = requests.get(
            "https://api.cricapi.com/v1/currentMatches",
            params={"apikey": CRICKETDATA_API_KEY, "offset": 0},
            timeout=HTTP_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception as exc:
        LOGGER.warning("cricketdata.org health check failed error=%s", exc)
        return {"status": "error", "error": str(exc)}
    status = str(payload.get("status") or "") if isinstance(payload, dict) else ""
    return {"status": status or "unknown"}
