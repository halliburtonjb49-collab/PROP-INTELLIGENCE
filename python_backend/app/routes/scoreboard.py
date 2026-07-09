from __future__ import annotations

import asyncio
from datetime import date, datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from app.services.sportsdataio_service import sportsdataio_service

router = APIRouter(
    prefix="/scoreboard",
    tags=["scoreboard"],
)


class ScoreboardGameResponse(BaseModel):
    id: str
    sport: str
    league: str
    away_team: str = ""
    home_team: str = ""
    away_score: int | None = None
    home_score: int | None = None
    status: str
    detail: str = ""
    start_time: datetime | None = None
    away_logo: str | None = None
    home_logo: str | None = None
    venue: str | None = None
    fighter_one: str | None = None
    fighter_two: str | None = None
    fighter_one_image: str | None = None
    fighter_two_image: str | None = None
    winner: str | None = None
    method: str | None = None
    round: int | None = None
    time: str | None = None
    weight_class: str | None = None


class ScoreboardResponse(BaseModel):
    date: str
    updated_at: datetime
    games: list[ScoreboardGameResponse]


LEAGUE_ORDER = {
    "NBA": 1,
    "WNBA": 2,
    "MLB": 3,
    "NFL": 4,
    "NHL": 5,
    "MLS": 6,
    "EPL": 7,
    "SOCCER": 8,
    "ATP": 9,
    "WTA": 10,
    "PGA": 11,
    "UFC": 12,
}


_scoreboard_cache: dict[str, tuple[datetime, list[ScoreboardGameResponse]]] = {}
CACHE_DURATION = timedelta(seconds=20)


def normalize_status(value: Any) -> str:
    raw = str(value or "").strip().upper().replace("-", "_").replace(" ", "_")
    if raw in {
        "LIVE",
        "IN_PROGRESS",
        "INPROGRESS",
        "PLAYING",
        "ACTIVE",
        "HALFTIME",
        "INTERMISSION",
    }:
        return "LIVE"
    if raw in {
        "FINAL",
        "COMPLETED",
        "CLOSED",
        "FINISHED",
        "ENDED",
        "FULL_TIME",
    }:
        return "FINAL"
    if raw in {
        "POSTPONED",
        "CANCELED",
        "CANCELLED",
        "SUSPENDED",
        "DELAYED",
    }:
        return raw
    return "UPCOMING"


def safe_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def safe_datetime(value: Any) -> datetime | None:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def nested_get(data: dict[str, Any], *keys: str) -> Any:
    current: Any = data
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def normalize_game(
    raw: dict[str, Any],
    *,
    default_sport: str = "",
) -> ScoreboardGameResponse:
    sport = str(
        raw.get("sport")
        or raw.get("sport_key")
        or raw.get("league")
        or raw.get("leagueName")
        or default_sport
    ).upper()

    league = str(
        raw.get("league")
        or raw.get("league_name")
        or raw.get("leagueName")
        or sport
    ).upper()

    aliases = {
        "MMA": "UFC",
        "ULTIMATE_FIGHTING_CHAMPIONSHIP": "UFC",
        "UFC_MMA": "UFC",
    }
    sport = aliases.get(sport, sport)
    league = aliases.get(league, league)

    status = normalize_status(
        raw.get("status")
        or raw.get("game_status")
        or raw.get("state")
        or raw.get("gameState")
    )

    is_ufc = league == "UFC" or sport == "UFC"
    if is_ufc:
        return ScoreboardGameResponse(
            id=str(
                raw.get("FightId")
                or raw.get("FightID")
                or raw.get("EventId")
                or raw.get("id")
                or ""
            ),
            sport="UFC",
            league="UFC",
            status=normalize_status(raw.get("Status") or raw.get("status")),
            detail=str(raw.get("WeightClass") or raw.get("Division") or ""),
            start_time=safe_datetime(raw.get("DateTime") or raw.get("StartTime")),
            venue=str(raw.get("Venue") or raw.get("VenueName") or "") or None,
            fighter_one=str(
                raw.get("Fighter1")
                or raw.get("RedCorner")
                or raw.get("FighterA")
                or ""
            )
            or None,
            fighter_two=str(
                raw.get("Fighter2")
                or raw.get("BlueCorner")
                or raw.get("FighterB")
                or ""
            )
            or None,
            fighter_one_image=str(
                raw.get("Fighter1Image") or raw.get("RedCornerImage") or ""
            )
            or None,
            fighter_two_image=str(
                raw.get("Fighter2Image") or raw.get("BlueCornerImage") or ""
            )
            or None,
            winner=str(raw.get("Winner") or raw.get("WinnerName") or "") or None,
            method=str(raw.get("Method") or raw.get("ResultMethod") or "") or None,
            round=safe_int(raw.get("Round") or raw.get("ResultRound")),
            time=str(raw.get("Time") or raw.get("ResultTime") or "") or None,
            weight_class=str(raw.get("WeightClass") or raw.get("Division") or "")
            or None,
        )

    away_team = (
        raw.get("away_team")
        or raw.get("awayTeam")
        or raw.get("visitor_team")
        or nested_get(raw, "competitors", "away", "name")
        or "Away Team"
    )

    home_team = (
        raw.get("home_team")
        or raw.get("homeTeam")
        or nested_get(raw, "competitors", "home", "name")
        or "Home Team"
    )

    away_score = safe_int(
        raw.get("away_score")
        or raw.get("awayScore")
        or raw.get("visitor_score")
        or nested_get(raw, "competitors", "away", "score")
    )

    home_score = safe_int(
        raw.get("home_score")
        or raw.get("homeScore")
        or nested_get(raw, "competitors", "home", "score")
    )

    away_logo = (
        raw.get("away_logo")
        or raw.get("away_team_logo")
        or nested_get(raw, "competitors", "away", "logo")
    )

    home_logo = (
        raw.get("home_logo")
        or raw.get("home_team_logo")
        or nested_get(raw, "competitors", "home", "logo")
    )

    detail = (
        raw.get("detail")
        or raw.get("status_detail")
        or raw.get("clock")
        or raw.get("period")
        or raw.get("inning")
        or ""
    )

    start_time = safe_datetime(
        raw.get("start_time")
        or raw.get("commence_time")
        or raw.get("game_time")
        or raw.get("startTime")
    )

    return ScoreboardGameResponse(
        id=str(
            raw.get("id")
            or raw.get("game_id")
            or raw.get("event_id")
            or raw.get("eventId")
            or ""
        ),
        sport=sport,
        league=league,
        away_team=str(away_team),
        home_team=str(home_team),
        away_score=away_score,
        home_score=home_score,
        status=status,
        detail=str(detail),
        start_time=start_time,
        away_logo=str(away_logo or "") or None,
        home_logo=str(home_logo or "") or None,
        venue=str(raw.get("venue") or "") or None,
    )


async def fetch_provider_games(selected_date: date) -> list[dict[str, Any]]:
    games = await fetch_multi_league_games(selected_date)
    if games:
        print("FIRST SCOREBOARD GAME:", games[0])
    return games


async def fetch_multi_league_games(selected_date: date) -> list[dict[str, Any]]:
    date_value = selected_date.strftime("%Y-%b-%d").upper()

    # Use candidate endpoints per league and keep going if one league fails.
    league_endpoints = {
        "NBA": [
            f"https://api.sportsdata.io/v3/nba/scores/json/GamesByDate/{date_value}",
        ],
        "WNBA": [
            f"https://api.sportsdata.io/v3/wnba/scores/json/GamesByDate/{date_value}",
        ],
        "MLB": [
            f"https://api.sportsdata.io/v3/mlb/scores/json/GamesByDate/{date_value}",
        ],
        "NHL": [
            f"https://api.sportsdata.io/v3/nhl/scores/json/GamesByDate/{date_value}",
        ],
        "NFL": [
            f"https://api.sportsdata.io/v3/nfl/scores/json/ScoresByDate/{date_value}",
            f"https://api.sportsdata.io/v3/nfl/scores/json/GamesByDate/{date_value}",
        ],
        "UFC": [
            f"https://api.sportsdata.io/v3/mma/scores/json/FightsByDate/{date_value}",
            f"https://api.sportsdata.io/v3/mma/scores/json/EventFightsByDate/{date_value}",
        ],
    }

    async def fetch_league(league: str, urls: list[str]) -> list[dict[str, Any]]:
        for url in urls:
            try:
                result = await sportsdataio_service.get_json(url)
                if isinstance(result, list):
                    enriched: list[dict[str, Any]] = []
                    for item in result:
                        if not isinstance(item, dict):
                            continue
                        normalized = dict(item)
                        normalized.setdefault("league", league)
                        normalized.setdefault("sport", league)
                        enriched.append(normalized)
                    return enriched
            except Exception as error:
                print(f"Scoreboard fetch failed for {league} via {url}: {error}")
                continue
        return []

    tasks = [
        fetch_league(league, urls)
        for league, urls in league_endpoints.items()
    ]
    league_results = await asyncio.gather(*tasks)

    combined: list[dict[str, Any]] = []
    for result in league_results:
        combined.extend(result)
    return combined


@router.get("", response_model=ScoreboardResponse)
async def get_scoreboard(
    game_date: date = Query(
        alias="date",
        description="Scoreboard date in YYYY-MM-DD format",
    ),
) -> ScoreboardResponse:
    cache_key = game_date.isoformat()
    now = datetime.now(timezone.utc)

    cached = _scoreboard_cache.get(cache_key)
    if cached is not None:
        cached_at, cached_games = cached
        if now - cached_at < CACHE_DURATION:
            return ScoreboardResponse(
                date=cache_key,
                updated_at=cached_at,
                games=cached_games,
            )

    try:
        raw_games = await fetch_provider_games(game_date)
        games = [normalize_game(game) for game in raw_games]

        games.sort(
            key=lambda game: (
                LEAGUE_ORDER.get(game.league, 999),
                game.start_time or datetime.max.replace(tzinfo=timezone.utc),
            )
        )

        _scoreboard_cache[cache_key] = (now, games)

        return ScoreboardResponse(
            date=cache_key,
            updated_at=now,
            games=games,
        )
    except Exception as error:
        raise HTTPException(
            status_code=502,
            detail=f"Unable to retrieve scoreboard data: {error}",
        ) from error
