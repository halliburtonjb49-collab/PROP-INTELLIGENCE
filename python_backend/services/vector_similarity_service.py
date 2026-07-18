"""Deterministic feature vectors and pgvector-backed historical analog search."""
from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from statistics import fmean, median

from database.postgres import database_is_configured, get_database_pool
from models.intelligence import DatabaseSimilarityRequest


def stretch_embedding(values: list[float]) -> list[float]:
    mean = fmean(values)
    variance = sum((value - mean) ** 2 for value in values) / max(1, len(values) - 1)
    deviation = variance ** .5
    normalized = [(value - mean) / max(deviation, 1e-6) for value in values]
    # Resample the sequence to ten fixed positions, preserving shape across input lengths.
    sequence = []
    for index in range(10):
        position = index * (len(normalized) - 1) / 9
        lower = int(position)
        upper = min(len(normalized) - 1, lower + 1)
        weight = position - lower
        sequence.append(normalized[lower] * (1 - weight) + normalized[upper] * weight)
    trend = (values[-1] - values[0]) / max(1, len(values) - 1)
    recent = fmean(values[-min(3, len(values)):])
    features = sequence + [mean / 100, deviation / 50, median(values) / 100,
                           trend / max(deviation, 1), recent / 100, len(values) / 20]
    return [round(value, 8) for value in features]


def _vector_literal(values: list[float]) -> str:
    return "[" + ",".join(str(value) for value in values) + "]"


def database_similarity(request: DatabaseSimilarityRequest) -> dict[str, object]:
    if not database_is_configured():
        return {"player": request.player, "matches": [], "analogNextGameProjection": None,
                "engine": "pgvector", "reason": "DATABASE_URL is not configured"}
    vector = stretch_embedding(request.recent_stretch)
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select id,player_id,market,next_game_value,similarity,context,occurred_at
            from match_player_stretches_filtered((%s)::vector,%s,%s,%s)""",
            (_vector_literal(vector), request.sport.upper(), request.market.lower(), request.limit))
        rows = cursor.fetchall()
    matches = [{"id": row[0], "player": row[1], "market": row[2],
                "nextGameValue": float(row[3]), "similarity": round(float(row[4]), 4),
                "context": row[5], "occurredAt": row[6].isoformat()} for row in rows]
    weights = sum(max(0, row["similarity"]) for row in matches)
    projection = (sum(row["nextGameValue"] * max(0, row["similarity"]) for row in matches) / weights
                  if weights else None)
    return {"player": request.player, "matches": matches,
            "analogNextGameProjection": round(projection, 2) if projection is not None else None,
            "engine": "supabase-pgvector-cosine-v1", "embeddingDimensions": 16}


def upsert_basketball_stretches(rows: list[dict[str, object]], sport: str) -> int:
    if not rows or not database_is_configured():
        return 0
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        grouped[str(row.get("player_id") or "")].append(row)
    values_to_insert = []
    for player_id, games in grouped.items():
        games.sort(key=lambda game: str(game.get("game_date") or ""))
        for market in ("points", "rebounds", "assists"):
            for index in range(5, len(games)):
                stretch = [float(game[market]) for game in games[index - 5:index] if game.get(market) is not None]
                next_value = games[index].get(market)
                if len(stretch) != 5 or next_value is None:
                    continue
                occurred = games[index - 1].get("game_date")
                context = {"nextGameId": games[index].get("league_game_id"),
                           "playerName": games[index].get("player_name")}
                values_to_insert.append((sport, player_id, market, __import__("json").dumps(stretch),
                    _vector_literal(stretch_embedding(stretch)), float(next_value),
                    __import__("json").dumps(context), occurred))
    if not values_to_insert:
        return 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("""insert into player_stretch_embeddings
            (sport,player_id,market,stretch_values,embedding,next_game_value,context,occurred_at)
            values (%s,%s,%s,%s::jsonb,(%s)::vector,%s,%s::jsonb,%s)
            on conflict(sport,player_id,market,occurred_at) do update set
            stretch_values=excluded.stretch_values,embedding=excluded.embedding,
            next_game_value=excluded.next_game_value,context=excluded.context""", values_to_insert)
        connection.commit()
    return len(values_to_insert)
