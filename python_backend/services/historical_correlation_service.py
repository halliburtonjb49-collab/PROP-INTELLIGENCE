"""Empirical prop correlation from overlapping historical player game logs."""

from __future__ import annotations

from math import sqrt

from database.postgres import database_is_configured, get_database_pool


def _column(market: str) -> str | None:
    text = market.lower().replace("player_", "")
    mappings = {
        "point": "points", "rebound": "rebounds", "assist": "assists",
        "steal": "steals", "block": "blocks", "turnover": "turnovers",
        "three": "threes", "free throw": "free_throw_attempts", "foul": "personal_fouls",
    }
    return next((column for key, column in mappings.items() if key in text), None)


def empirical_pair(first: object, second: object) -> dict[str, object] | None:
    sport = str(getattr(first, "sport", "")).upper()
    if sport not in {"NBA", "WNBA"} or sport != str(getattr(second, "sport", "")).upper():
        return None
    first_column, second_column = _column(str(getattr(first, "market", ""))), _column(str(getattr(second, "market", "")))
    if not first_column or not second_column or not database_is_configured():
        return None
    allowed = {"points", "rebounds", "assists", "steals", "blocks", "turnovers", "threes", "free_throw_attempts", "personal_fouls"}
    if first_column not in allowed or second_column not in allowed:
        return None
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(f"""select a.{first_column},b.{second_column}
            from historical_basketball_game_logs a join historical_basketball_game_logs b
              on a.sport=b.sport and a.game_date=b.game_date
            where a.sport=%s and lower(a.player_name)=lower(%s) and lower(b.player_name)=lower(%s)
              and a.{first_column} is not null and b.{second_column} is not null
            order by a.game_date desc limit 100""",
            (sport, str(getattr(first, "player", "")), str(getattr(second, "player", ""))))
        rows = [(float(row[0]), float(row[1])) for row in cursor.fetchall()]
    if len(rows) < 8:
        return None
    xs, ys = zip(*rows)
    x_mean, y_mean = sum(xs) / len(xs), sum(ys) / len(ys)
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in rows)
    denominator = sqrt(sum((x - x_mean) ** 2 for x in xs) * sum((y - y_mean) ** 2 for y in ys))
    if denominator == 0:
        return None
    coefficient = numerator / denominator
    if str(getattr(first, "side", "")) != str(getattr(second, "side", "")):
        coefficient *= -1
    line_a, line_b = getattr(first, "line", None), getattr(second, "line", None)
    joint = None
    if line_a is not None and line_b is not None:
        def hit(value: float, line: float, side: str) -> bool:
            return value > line if side == "OVER" else value < line
        joint = sum(hit(x, float(line_a), str(first.side)) and hit(y, float(line_b), str(second.side)) for x, y in rows) / len(rows)
    return {"coefficient": round(coefficient, 3), "sampleSize": len(rows),
            "jointHitRate": round(joint, 4) if joint is not None else None,
            "source": "historical-game-logs"}
