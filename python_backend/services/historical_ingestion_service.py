"""Normalize and persist low-cost historical sports data."""

from __future__ import annotations

import hashlib
import json
import logging
import math
from numbers import Real
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timedelta, timezone
from typing import Iterable

from database.postgres import database_is_configured, get_database_pool
from providers.historical_data import MlbHistoricalProvider, NbaHistoricalProvider
from services.vector_similarity_service import upsert_basketball_stretches
from services.officiating_profile_service import (calculate_mlb_umpire_profiles,
    persist_basketball_assignments, persist_officiating_profiles, refresh_basketball_profiles)
from services.matchup_profile_service import build_matchup_profiles, persist_matchup_profiles

logger = logging.getLogger(__name__)


def _as_date(value: object) -> date | None:
    text = str(value or "").strip()
    for pattern in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%SZ", "%b %d, %Y",
                    "%m/%d/%Y", "%m/%d/%Y %H:%M:%S"):
        try:
            return datetime.strptime(text, pattern).date()
        except ValueError:
            continue
    return None


def build_official_assignments(logs: list[dict[str, object]], officials_by_game: dict[str, list[dict[str, object]]],
                               sport: str) -> list[dict[str, object]]:
    by_game: dict[str, list[dict[str, object]]] = {}
    for row in logs:
        by_game.setdefault(str(row["league_game_id"]), []).append(row)
    assignments = []
    for game_id, officials in officials_by_game.items():
        game_rows = by_game.get(game_id, [])
        if not game_rows:
            continue
        fouls = sum(float(row.get("personal_fouls") or 0) for row in game_rows)
        attempts = sum(float(row.get("free_throw_attempts") or 0) for row in game_rows)
        for official in officials:
            official_id = str(official.get("PERSON_ID") or "").strip()
            name = f"{official.get('FIRST_NAME') or ''} {official.get('LAST_NAME') or ''}".strip()
            if official_id:
                assignments.append({"sport": sport, "league_game_id": game_id,
                    "official_id": official_id, "official_name": name or official_id,
                    "game_date": game_rows[0].get("game_date"), "total_fouls": fouls,
                    "total_free_throw_attempts": attempts, "raw": official})
    return assignments


def _stable_id(*parts: object) -> str:
    value = "|".join(str(part or "").strip() for part in parts)
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:32]


def _number(value: object) -> float | None:
    try:
        number = None if value is None else float(value)
        return number if number is not None and math.isfinite(number) else None
    except (TypeError, ValueError):
        return None


def _json_safe(value: object) -> object:
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    if isinstance(value, Real) and not isinstance(value, bool):
        number = float(value)
        return value if math.isfinite(number) else None
    return value


def normalize_basketball_logs(rows: Iterable[dict[str, object]], sport: str) -> list[dict[str, object]]:
    normalized = []
    for row in rows:
        player_id = str(row.get("PLAYER_ID") or "")
        game_id = str(row.get("GAME_ID") or "")
        if not player_id or not game_id:
            continue
        normalized.append({
            "id": _stable_id(sport, game_id, player_id), "sport": sport,
            "league_game_id": game_id, "player_id": player_id,
            "player_name": str(row.get("PLAYER_NAME") or row.get("PLAYER") or ""),
            "team_id": str(row.get("TEAM_ID") or ""), "game_date": row.get("GAME_DATE"),
            "matchup": str(row.get("MATCHUP") or ""), "minutes": _number(row.get("MIN")),
            "points": _number(row.get("PTS")), "rebounds": _number(row.get("REB")),
            "assists": _number(row.get("AST")), "steals": _number(row.get("STL")),
            "blocks": _number(row.get("BLK")), "turnovers": _number(row.get("TOV")),
            "threes": _number(row.get("FG3M")), "personal_fouls": _number(row.get("PF")),
            "free_throw_attempts": _number(row.get("FTA")), "raw": _json_safe(row),
        })
    return normalized


def normalize_statcast(rows: Iterable[dict[str, object]]) -> list[dict[str, object]]:
    normalized = []
    for row in rows:
        game_pk, at_bat, pitch = row.get("game_pk"), row.get("at_bat_number"), row.get("pitch_number")
        if game_pk is None or at_bat is None or pitch is None:
            continue
        normalized.append({
            "id": _stable_id("MLB", game_pk, at_bat, pitch), "game_pk": str(game_pk),
            "game_date": row.get("game_date"), "pitcher_id": str(row.get("pitcher") or ""),
            "batter_id": str(row.get("batter") or ""), "umpire": str(row.get("umpire") or ""),
            "pitch_type": str(row.get("pitch_type") or ""), "description": str(row.get("description") or ""),
            "plate_x": _number(row.get("plate_x")), "plate_z": _number(row.get("plate_z")),
            "sz_top": _number(row.get("sz_top")), "sz_bot": _number(row.get("sz_bot")),
            "release_speed": _number(row.get("release_speed")), "events": str(row.get("events") or ""),
            "home_team": str(row.get("home_team") or ""), "away_team": str(row.get("away_team") or ""),
            "raw": _json_safe(row),
        })
    return normalized


class HistoricalRepository:
    def upsert_basketball_logs(self, rows: list[dict[str, object]]) -> int:
        if not rows or not database_is_configured():
            return 0
        values = [(r["id"], r["sport"], r["league_game_id"], r["player_id"], r["player_name"],
                   r["team_id"], r["game_date"], r["matchup"], r["minutes"], r["points"], r["rebounds"],
                   r["assists"], r["steals"], r["blocks"], r["turnovers"], r["threes"],
                   r["personal_fouls"], r["free_throw_attempts"], json.dumps(r["raw"], default=str)) for r in rows]
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.executemany("""insert into historical_basketball_game_logs
                (id,sport,league_game_id,player_id,player_name,team_id,game_date,matchup,minutes,points,rebounds,assists,steals,blocks,turnovers,threes,personal_fouls,free_throw_attempts,raw)
                values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb)
                on conflict (id) do update set minutes=excluded.minutes,points=excluded.points,rebounds=excluded.rebounds,
                assists=excluded.assists,steals=excluded.steals,blocks=excluded.blocks,turnovers=excluded.turnovers,
                threes=excluded.threes,personal_fouls=excluded.personal_fouls,
                free_throw_attempts=excluded.free_throw_attempts,raw=excluded.raw,updated_at=now()""", values)
        return len(values)

    def upsert_mlb_pitches(self, rows: list[dict[str, object]]) -> int:
        if not rows or not database_is_configured():
            return 0
        values = [(r["id"], r["game_pk"], r["game_date"], r["pitcher_id"], r["batter_id"], r["umpire"],
                   r["pitch_type"], r["description"], r["plate_x"], r["plate_z"], r["release_speed"], r["sz_top"], r["sz_bot"], r["events"],
                   r["home_team"], r["away_team"], json.dumps(r["raw"], default=str)) for r in rows]
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.executemany("""insert into historical_mlb_pitches
                (id,game_pk,game_date,pitcher_id,batter_id,umpire,pitch_type,description,plate_x,plate_z,release_speed,sz_top,sz_bot,events,home_team,away_team,raw)
                values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb)
                on conflict (id) do update set description=excluded.description,plate_x=excluded.plate_x,
                plate_z=excluded.plate_z,release_speed=excluded.release_speed,events=excluded.events,raw=excluded.raw,updated_at=now()""", values)
        return len(values)

    def load_mlb_umpire_pitches(self) -> list[dict[str, object]]:
        if not database_is_configured():
            return []
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute("""select umpire,plate_x,description from historical_mlb_pitches
                where umpire <> '' and plate_x is not null and game_date >= current_date - interval '730 days'""")
            return [{"umpire": row[0], "plate_x": row[1], "description": row[2]} for row in cursor.fetchall()]

    def upsert_mlb_umpire_assignments(self, rows: list[dict[str, object]]) -> int:
        if not rows or not database_is_configured():
            return 0
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.executemany("""insert into mlb_umpire_game_assignments
                (game_pk,game_date,official_id,official_name,source,raw)
                values(%s,%s,%s,%s,%s,%s::jsonb) on conflict(game_pk) do update set
                game_date=excluded.game_date,official_id=excluded.official_id,
                official_name=excluded.official_name,source=excluded.source,raw=excluded.raw,updated_at=now()""",
                [(r["game_pk"], r["game_date"], r["official_id"], r["official_name"],
                  r["source"], json.dumps(r["raw"], default=str)) for r in rows])
            cursor.execute("""update historical_mlb_pitches p set umpire=a.official_name
                from mlb_umpire_game_assignments a where p.game_pk=a.game_pk
                and (p.umpire is null or p.umpire='')""")
            connection.commit()
        return len(rows)


def run_daily_historical_sync(target_date: date | None = None, season: str | None = None) -> dict[str, object]:
    target = target_date or (datetime.now(timezone.utc).date() - timedelta(days=1))
    nba_start_year = target.year if target.month >= 7 else target.year - 1
    nba_season = season or f"{nba_start_year}-{str(nba_start_year + 1)[-2:]}"
    wnba_season = season or str(target.year)
    repository = HistoricalRepository()
    nba = NbaHistoricalProvider()
    results: dict[str, object] = {"targetDate": target.isoformat(), "startedAt": datetime.now(timezone.utc).isoformat()}
    for sport, league_id, league_season in (
        ("NBA", "00", nba_season),
        ("WNBA", "10", wnba_season),
    ):
        try:
            logs = normalize_basketball_logs(
                nba.league_game_logs(season=league_season, league_id=league_id),
                sport,
            )
            target_game_ids = sorted({str(row["league_game_id"]) for row in logs if _as_date(row.get("game_date")) == target})
            officials_by_game = {}
            for game_id in target_game_ids:
                try:
                    officials_by_game[game_id] = nba.game_officials(game_id=game_id)
                except Exception:
                    logger.warning("Official lookup failed for %s %s", sport, game_id, exc_info=True)
            assignments = build_official_assignments(logs, officials_by_game, sport)
            matchup_profiles_upserted = 0
            try:
                ball_handler = nba.defensive_synergy(season=league_season, league_id=league_id,
                                                     play_type="PRBallHandler")
                roll_man = nba.defensive_synergy(season=league_season, league_id=league_id,
                                                 play_type="PRRollman")
                matchup_profiles_upserted = persist_matchup_profiles(
                    build_matchup_profiles(ball_handler, roll_man, sport, league_season))
            except Exception:
                logger.warning("Defensive Synergy lookup failed for %s", sport, exc_info=True)
            results[sport] = {"fetched": len(logs), "upserted": repository.upsert_basketball_logs(logs),
                              "stretchesUpserted": upsert_basketball_stretches(logs, sport),
                              "officialAssignmentsUpserted": persist_basketball_assignments(assignments),
                              "officiatingProfilesUpserted": refresh_basketball_profiles(sport),
                              "matchupProfilesUpserted": matchup_profiles_upserted}
        except Exception as exc:
            logger.exception("Historical %s sync failed", sport)
            results[sport] = {"error": str(exc)}
    try:
        mlb = MlbHistoricalProvider()
        pitches = normalize_statcast(mlb.statcast(start=target, end=target))
        upserted = repository.upsert_mlb_pitches(pitches)
        umpire_assignments = mlb.umpire_assignments(start=target, end=target)
        assignments_upserted = repository.upsert_mlb_umpire_assignments(umpire_assignments)
        profiles = calculate_mlb_umpire_profiles(repository.load_mlb_umpire_pitches())
        results["MLB"] = {"fetched": len(pitches), "upserted": upserted,
                          "umpireAssignmentsUpserted": assignments_upserted,
                          "officiatingProfilesUpserted": persist_officiating_profiles(profiles)}
    except Exception as exc:
        logger.exception("Historical MLB sync failed")
        results["MLB"] = {"error": str(exc)}
    results["finishedAt"] = datetime.now(timezone.utc).isoformat()
    return results


def backfill_basketball_officiating(*, sport: str, season: str,
                                    days: int = 30, max_games: int = 60) -> dict[str, object]:
    """Backfill recent official crews without re-downloading full player logs."""
    if not database_is_configured():
        return {"persisted": False, "reason": "DATABASE_URL is not configured"}
    league_id = "10" if sport.upper() == "WNBA" else "00"
    provider = NbaHistoricalProvider()
    cutoff = datetime.now(timezone.utc).date() - timedelta(days=max(1, days))
    schedule = provider.league_schedule(season=season, league_id=league_id)
    game_ids = []
    for row in schedule:
        game_date = _as_date(row.get("gameDate") or row.get("gameDateUTC"))
        if game_date and game_date >= cutoff and str(row.get("gameId") or ""):
            game_ids.append(str(row["gameId"]))
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select league_game_id,game_date,personal_fouls,free_throw_attempts
            from historical_basketball_game_logs where sport=%s and game_date >= %s""",
            (sport.upper(), cutoff))
        rows = cursor.fetchall()
        cursor.execute("""select distinct league_game_id from basketball_official_game_assignments
            where sport=%s and game_date >= %s""", (sport.upper(), cutoff))
        existing = {str(row[0]) for row in cursor.fetchall()}
    totals: dict[str, dict[str, object]] = {}
    for game_id, game_date, fouls, attempts in rows:
        item = totals.setdefault(str(game_id), {"game_date": game_date, "fouls": 0.0, "attempts": 0.0})
        item["fouls"] = float(item["fouls"]) + float(fouls or 0)
        item["attempts"] = float(item["attempts"]) + float(attempts or 0)
    candidate_ids = sorted((set(game_ids) & set(totals)) - existing, reverse=True)[:max_games]
    assignments = []
    failures = 0
    def fetch(game_id: str) -> tuple[str, list[dict[str, object]]]:
        return game_id, provider.game_officials(game_id=game_id, timeout=30)
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {executor.submit(fetch, game_id): game_id for game_id in candidate_ids}
        completed = []
        for future in as_completed(futures):
            try:
                completed.append(future.result())
            except Exception:
                failures += 1
                logger.warning("Official backfill failed sport=%s game=%s error=%s",
                               sport, futures[future], future.exception())
    for game_id, officials in completed:
        try:
            total = totals[game_id]
            for official in officials:
                official_id = str(official.get("PERSON_ID") or "").strip()
                if official_id:
                    assignments.append({"sport": sport.upper(), "league_game_id": game_id,
                        "official_id": official_id,
                        "official_name": f"{official.get('FIRST_NAME') or ''} {official.get('LAST_NAME') or ''}".strip(),
                        "game_date": total["game_date"], "total_fouls": total["fouls"],
                        "total_free_throw_attempts": total["attempts"], "raw": official})
        except Exception:
            failures += 1
            logger.warning("Official normalization failed sport=%s game=%s", sport, game_id, exc_info=True)
    persisted = persist_basketball_assignments(assignments)
    profiles = refresh_basketball_profiles(sport.upper())
    return {"persisted": True, "candidateGames": len(candidate_ids),
            "assignments": persisted, "profiles": profiles, "failures": failures}
