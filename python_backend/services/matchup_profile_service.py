"""Build transparent matchup proxies from free defensive Synergy data."""
import json
from collections import defaultdict

from database.postgres import database_is_configured, get_database_pool


def _number(row: dict[str, object], *keys: str) -> float | None:
    for key in keys:
        try:
            if row.get(key) is not None:
                return float(row[key])
        except (TypeError, ValueError):
            pass
    return None


def build_matchup_profiles(ball_handler: list[dict[str, object]], roll_man: list[dict[str, object]],
                           sport: str, season: str) -> list[dict[str, object]]:
    grouped: dict[str, dict[str, dict[str, object]]] = defaultdict(dict)
    for label, rows in (("ballHandler", ball_handler), ("rollMan", roll_man)):
        for row in rows:
            team_id = str(row.get("TEAM_ID") or "")
            if team_id:
                grouped[team_id][label] = row
    all_ppp = [_number(row, "PPP") for row in ball_handler + roll_man]
    valid_ppp = [value for value in all_ppp if value is not None]
    league_ppp = sum(valid_ppp) / len(valid_ppp) if valid_ppp else 1.0
    profiles = []
    for team_id, parts in grouped.items():
        handler, roller = parts.get("ballHandler", {}), parts.get("rollMan", {})
        handler_ppp, roller_ppp = _number(handler, "PPP"), _number(roller, "PPP")
        possession_share = _number(handler, "POSS_PCT", "POSS_PCT_RANK") or 0
        percentile = _number(handler, "PERCENTILE")
        sample = (_number(handler, "POSS") or 0) + (_number(roller, "POSS") or 0)
        observed = [value for value in (handler_ppp, roller_ppp) if value is not None]
        allowed_ppp = sum(observed) / len(observed) if observed else league_ppp
        difficulty = max(-1.0, min(1.0, (league_ppp - allowed_ppp) / max(.15, league_ppp * .15)))
        pressure = max(0.0, min(1.0, .25 + difficulty * .18 + min(.25, possession_share * .25)))
        switch_signal = .15 if (roller_ppp or league_ppp) < (handler_ppp or league_ppp) else 0.0
        switch_proxy = max(0.0, min(1.0, .20 + switch_signal))
        confidence = min(1.0, sample / 250) if sample else min(.5, len(observed) * .2)
        source_row = handler or roller
        profiles.append({"sport": sport, "teamId": team_id,
            "teamName": str(source_row.get("TEAM_NAME") or team_id), "season": season,
            "pickRollPressureProxy": round(pressure, 4), "switchRateProxy": round(float(switch_proxy), 4),
            "defenderDifficulty": round(difficulty, 4), "confidence": round(confidence, 4),
            "source": "NBA Synergy defensive play-type proxy (not observed blitz/switch tracking)",
            "metrics": {"ballHandlerPpp": handler_ppp, "rollManPpp": roller_ppp,
                        "leaguePpp": round(league_ppp, 4), "possessions": sample,
                        "percentile": percentile}})
    return profiles


def persist_matchup_profiles(profiles: list[dict[str, object]]) -> int:
    if not profiles or not database_is_configured():
        return 0
    values = [(p["sport"], p["teamId"], p["teamName"], p["season"], p["pickRollPressureProxy"],
               p["switchRateProxy"], p["defenderDifficulty"], p["confidence"], p["source"],
               json.dumps(p["metrics"])) for p in profiles]
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.executemany("""insert into team_matchup_profiles
          (sport,team_id,team_name,season,pick_roll_pressure_proxy,switch_rate_proxy,
           defender_difficulty,confidence,source,metrics) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb)
          on conflict(sport,team_id,season) do update set team_name=excluded.team_name,
          pick_roll_pressure_proxy=excluded.pick_roll_pressure_proxy,switch_rate_proxy=excluded.switch_rate_proxy,
          defender_difficulty=excluded.defender_difficulty,confidence=excluded.confidence,
          source=excluded.source,metrics=excluded.metrics,computed_at=now()""", values)
        connection.commit()
    return len(values)


def get_matchup_profile(sport: str, team_id: str, season: str) -> dict[str, object] | None:
    if not database_is_configured(): return None
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute("""select team_name,pick_roll_pressure_proxy,switch_rate_proxy,
            defender_difficulty,confidence,source,metrics,computed_at from team_matchup_profiles
            where sport=%s and team_id=%s and season=%s""", (sport, team_id, season))
        row = cursor.fetchone()
    if row is None: return None
    return {"teamId": team_id, "teamName": row[0], "pickRollPressureProxy": row[1],
            "switchRateProxy": row[2], "defenderDifficulty": row[3], "confidence": row[4],
            "source": row[5], "metrics": row[6], "computedAt": row[7].isoformat()}
