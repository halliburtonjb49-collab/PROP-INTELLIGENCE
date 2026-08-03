"""Persist league-provided historical defender matchup shares."""

from __future__ import annotations

from database.postgres import database_is_configured, get_database_pool
from providers.historical_data import NbaHistoricalProvider
import logging

logger = logging.getLogger(__name__)


def _number(row: dict[str, object], key: str) -> float:
    try:
        return float(row.get(key) or 0)
    except (TypeError, ValueError):
        return 0.0


def sync_defender_matchups(*, sport: str, season: str) -> dict[str, object]:
    if not database_is_configured():
        return {"sport": sport, "created": 0, "reason": "DATABASE_URL is not configured"}
    league_id = "10" if sport.upper() == "WNBA" else "00"
    try:
        rows = NbaHistoricalProvider().league_defender_matchups(
            season=season, league_id=league_id, timeout=20,
        )
    except Exception as exc:
        logger.warning("Defender matchup provider unavailable; retaining cached data: %s", exc)
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                "select count(*) from basketball_defender_matchups where sport=%s and season=%s",
                (sport.upper(), season),
            )
            cached = int(cursor.fetchone()[0])
        return {
            "sport": sport.upper(), "season": season, "matchups": cached,
            "source": "cached", "providerError": str(exc),
        }
    values = []
    for row in rows:
        offensive_id = str(row.get("OFF_PLAYER_ID") or "")
        defensive_id = str(row.get("DEF_PLAYER_ID") or "")
        if not offensive_id or not defensive_id:
            continue
        values.append((sport.upper(), season, offensive_id,
                       str(row.get("OFF_PLAYER_NAME") or offensive_id), defensive_id,
                       str(row.get("DEF_PLAYER_NAME") or defensive_id),
                       _number(row, "MATCHUP_MIN"), _number(row, "PARTIAL_POSS"),
                       _number(row, "PLAYER_PTS"), _number(row, "MATCHUP_FGA"),
                       _number(row, "MATCHUP_FG_PCT"), int(_number(row, "GP")),
                       "stats.nba.com LeagueSeasonMatchups via nba_api"))
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("""insert into basketball_defender_matchups
          (sport,season,offensive_player_id,offensive_player_name,defensive_player_id,
           defensive_player_name,matchup_minutes,partial_possessions,player_points,
           matchup_fga,matchup_fg_pct,games,source)
          values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
          on conflict(sport,season,offensive_player_id,defensive_player_id) do update set
          offensive_player_name=excluded.offensive_player_name,
          defensive_player_name=excluded.defensive_player_name,
          matchup_minutes=excluded.matchup_minutes,partial_possessions=excluded.partial_possessions,
          player_points=excluded.player_points,matchup_fga=excluded.matchup_fga,
          matchup_fg_pct=excluded.matchup_fg_pct,games=excluded.games,
          source=excluded.source,updated_at=now()""", values)
        connection.commit()
    return {"sport": sport.upper(), "season": season, "matchups": len(values)}
