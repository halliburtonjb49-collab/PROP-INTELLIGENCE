"""Build sample-size-aware officiating tendencies from historical events."""
from collections import defaultdict
from datetime import datetime, timezone
import json

from database.postgres import database_is_configured, get_database_pool


def calculate_mlb_umpire_profiles(rows: list[dict[str, object]], prior_pitches: int = 200) -> list[dict[str, object]]:
    eligible = [row for row in rows if str(row.get("umpire") or "").strip()
                and row.get("plate_x") is not None
                and .7 <= abs(float(row["plate_x"])) <= 1.1
                and str(row.get("description") or "") in {"called_strike", "ball", "blocked_ball"}]
    if not eligible:
        return []
    league_rate = sum(row.get("description") == "called_strike" for row in eligible) / len(eligible)
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in eligible:
        grouped[str(row["umpire"]).strip()].append(row)
    profiles = []
    for umpire, pitches in grouped.items():
        called = sum(row.get("description") == "called_strike" for row in pitches)
        raw_rate = called / len(pitches)
        shrunk_rate = (called + prior_pitches * league_rate) / (len(pitches) + prior_pitches)
        index = shrunk_rate / max(league_rate, 1e-9)
        profiles.append({"sport": "MLB", "officialId": umpire.lower().replace(" ", "-"),
            "officialName": umpire, "sampleSize": len(pitches), "rawRate": round(raw_rate, 5),
            "leagueRate": round(league_rate, 5), "tendencyIndex": round(index, 4),
            "confidence": round(len(pitches) / (len(pitches) + prior_pitches), 4),
            "metrics": {"borderlineCalledStrikes": called, "borderlineTakenPitches": len(pitches)}})
    return profiles


def persist_officiating_profiles(profiles: list[dict[str, object]]) -> int:
    if not profiles or not database_is_configured():
        return 0
    values = [(p["sport"], p["officialId"], p["officialName"], p["sampleSize"], p["rawRate"],
               p["leagueRate"], p["tendencyIndex"], p["confidence"], json.dumps(p["metrics"])) for p in profiles]
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("""insert into officiating_tendency_profiles
            (sport,official_id,official_name,sample_size,raw_rate,league_rate,tendency_index,confidence,metrics)
            values (%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb) on conflict(sport,official_id) do update set
            official_name=excluded.official_name,sample_size=excluded.sample_size,raw_rate=excluded.raw_rate,
            league_rate=excluded.league_rate,tendency_index=excluded.tendency_index,
            confidence=excluded.confidence,metrics=excluded.metrics,computed_at=now()""", values)
        connection.commit()
    return len(values)


def get_officiating_profile(sport: str, official_id: str) -> dict[str, object] | None:
    if not database_is_configured():
        return None
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select official_id,official_name,sample_size,raw_rate,league_rate,
            tendency_index,confidence,metrics,computed_at from officiating_tendency_profiles
            where sport=%s and official_id=%s""", (sport.upper(), official_id))
        row = cursor.fetchone()
    if row is None:
        return None
    return {"officialId": row[0], "officialName": row[1], "sampleSize": row[2],
            "rawRate": row[3], "leagueRate": row[4], "tendencyIndex": row[5],
            "confidence": row[6], "metrics": row[7], "computedAt": row[8].isoformat()}


def calculate_basketball_official_profiles(rows: list[dict[str, object]], prior_games: int = 20) -> list[dict[str, object]]:
    if not rows:
        return []
    league_rate = sum(float(row["whistle_events"]) for row in rows) / len(rows)
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        grouped[str(row["official_id"])].append(row)
    profiles = []
    for official_id, games in grouped.items():
        total = sum(float(game["whistle_events"]) for game in games)
        raw_rate = total / len(games)
        shrunk_rate = (total + prior_games * league_rate) / (len(games) + prior_games)
        first = games[0]
        profiles.append({"sport": str(first["sport"]), "officialId": official_id,
            "officialName": str(first["official_name"]), "sampleSize": len(games),
            "rawRate": round(raw_rate, 5), "leagueRate": round(league_rate, 5),
            "tendencyIndex": round(shrunk_rate / max(league_rate, 1e-9), 4),
            "confidence": round(len(games) / (len(games) + prior_games), 4),
            "metrics": {"averageWhistleEvents": round(raw_rate, 3)}})
    return profiles


def persist_basketball_assignments(rows: list[dict[str, object]]) -> int:
    if not rows or not database_is_configured():
        return 0
    values = [(r["sport"], r["league_game_id"], r["official_id"], r["official_name"],
               r["game_date"], r["total_fouls"], r["total_free_throw_attempts"], json.dumps(r.get("raw", {})))
              for r in rows]
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("""insert into basketball_official_game_assignments
            (sport,league_game_id,official_id,official_name,game_date,total_fouls,total_free_throw_attempts,raw)
            values (%s,%s,%s,%s,%s,%s,%s,%s::jsonb) on conflict(sport,league_game_id,official_id)
            do update set official_name=excluded.official_name,total_fouls=excluded.total_fouls,
            total_free_throw_attempts=excluded.total_free_throw_attempts,raw=excluded.raw,updated_at=now()""", values)
        connection.commit()
    return len(values)


def refresh_basketball_profiles(sport: str) -> int:
    if not database_is_configured():
        return 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select sport,official_id,official_name,
            total_fouls + .44*total_free_throw_attempts whistle_events
            from basketball_official_game_assignments where sport=%s
            and game_date >= current_date - interval '730 days'""", (sport,))
        rows = [{"sport": row[0], "official_id": row[1], "official_name": row[2],
                 "whistle_events": row[3]} for row in cursor.fetchall()]
    return persist_officiating_profiles(calculate_basketball_official_profiles(rows))
