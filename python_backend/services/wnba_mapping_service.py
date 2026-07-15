from datetime import datetime

from config import DB_PATH, WNBA_LEAGUE_ID
from database.cache import PropCache
from providers.api_sports_basketball import (
    ApiSportsBasketballProvider,
)
from services.wnba_game_matcher import match_wnba_game

cache = PropCache(DB_PATH)


def _game_date(commence_time: str) -> str:
    parsed = datetime.fromisoformat(
        commence_time.replace("Z", "+00:00")
    )
    return parsed.date().isoformat()


def map_wnba_event(
    *,
    odds_event_id: str,
    home_team: str,
    away_team: str,
    commence_time: str,
    season: str,
) -> str | None:
    provider = ApiSportsBasketballProvider()
    payload = provider.get_games_by_date(
        league_id=WNBA_LEAGUE_ID,
        season=season,
        date=_game_date(commence_time),
    )
    raw_games = payload.get("response", [])
    if not isinstance(raw_games, list):
        return None

    api_sports_game_id = match_wnba_game(
        odds_home_team=home_team,
        odds_away_team=away_team,
        odds_start_time=commence_time,
        api_sports_games=raw_games,
    )
    if api_sports_game_id:
        cache.set_api_sports_game_id(
            odds_event_id=odds_event_id,
            api_sports_game_id=api_sports_game_id,
        )

    return api_sports_game_id
