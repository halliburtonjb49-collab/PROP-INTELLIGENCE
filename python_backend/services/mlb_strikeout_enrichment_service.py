"""Owner-safe MLB strikeout feature enrichment from persisted context."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

from database.postgres import database_is_configured, get_database_pool
from services.mlb_headshot_service import mlb_player_id
from services.mlb_parquet_feature_service import latest_player_features
from services.officiating_profile_service import get_officiating_profile
from services.team_normalizer import normalize_team_name


_PARK_K_FACTORS = {
    "colorado rockies": 0.94,
    "boston red sox": 1.01,
    "san francisco giants": 1.02,
    "san diego padres": 1.02,
    "seattle mariners": 1.01,
    "tampa bay rays": 1.01,
    "los angeles dodgers": 1.01,
    "new york yankees": 1.00,
    "athletics": 1.02,
    "arizona diamondbacks": 0.99,
}


def _safe_float(value: object) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def _parse_event_date(value: object) -> object:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.date()


def _preferred_average(features: dict[str, object], stem: str) -> float | None:
    for window in (10, 20, 5):
        value = _safe_float(features.get(f"pregame_{stem}_avg_{window}d"))
        if value is not None:
            return value
    return None


def _pitcher_metrics(player_id: str, event_date: object) -> dict[str, float | None]:
    latest = latest_player_features(role="PITCHER", player_id=player_id, before_date=event_date)
    features = latest.get("features") if isinstance(latest, dict) else None
    if not isinstance(features, dict):
        return {}
    pitches = _preferred_average(features, "pitches")
    batters_faced = _preferred_average(features, "batters_faced")
    strikeouts = _preferred_average(features, "strikeouts")
    whiffs = _preferred_average(features, "whiffs")
    called_strikes = _preferred_average(features, "called_strikes")
    pitcher_k_pct = None
    if strikeouts is not None and batters_faced and batters_faced > 0:
        pitcher_k_pct = max(0.0, min(1.0, strikeouts / batters_faced))
    pitcher_csw = None
    if pitches and pitches > 0 and (whiffs is not None or called_strikes is not None):
        pitcher_csw = max(0.0, min(1.0, ((whiffs or 0.0) + (called_strikes or 0.0)) / pitches))
    pitches_per_batter = None
    if pitches is not None and batters_faced and batters_faced > 0:
        pitches_per_batter = pitches / batters_faced
    return {
        "pitcher_k_pct": pitcher_k_pct,
        "pitcher_csw": pitcher_csw,
        "pitches_per_start": pitches,
        "pitches_per_batter": pitches_per_batter,
    }


def _lineup_k_rate(opposing_lineup: Iterable[object], event_date: object) -> float | None:
    weighted_total = 0.0
    total_weight = 0.0
    for entry in opposing_lineup:
        if not isinstance(entry, dict):
            continue
        player_name = str(entry.get("player") or "").strip()
        if not player_name:
            continue
        batter_id = mlb_player_id(player_name)
        if batter_id is None:
            continue
        latest = latest_player_features(role="BATTER", player_id=str(batter_id), before_date=event_date)
        features = latest.get("features") if isinstance(latest, dict) else None
        if not isinstance(features, dict):
            continue
        plate_appearances = _preferred_average(features, "plate_appearances")
        strikeouts = _preferred_average(features, "strikeouts")
        if plate_appearances is None or plate_appearances <= 0 or strikeouts is None:
            continue
        rate = max(0.0, min(1.0, strikeouts / plate_appearances))
        weight = max(1.0, 12.0 - float(entry.get("battingOrder") or 9))
        weighted_total += rate * weight
        total_weight += weight
    if total_weight <= 0:
        return None
    return round(weighted_total / total_weight, 6)


def _home_team_from_matchup(matchup: str) -> str:
    if "@" not in matchup:
        return ""
    return normalize_team_name(matchup.split("@", 1)[1].strip())


def _park_k_factor(matchup: str) -> float:
    return _PARK_K_FACTORS.get(_home_team_from_matchup(matchup), 1.0)


def _umpire_boost(game_pk: str) -> float | None:
    if not database_is_configured() or not str(game_pk).isdigit():
        return None
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        cursor.execute(
            """select official_name from mlb_umpire_game_assignments where game_pk=%s limit 1""",
            (str(game_pk),),
        )
        row = cursor.fetchone()
    if not row or not row[0]:
        return None
    profile = get_officiating_profile("MLB", str(row[0]).strip().lower().replace(" ", "-"))
    if not isinstance(profile, dict):
        return None
    tendency = _safe_float(profile.get("tendencyIndex"))
    if tendency is None:
        return None
    return round((tendency - 1.0) * 0.05, 6)


def enrich_mlb_strikeout_props(props: list[object]) -> None:
    if not props or not database_is_configured():
        return
    for prop in props:
        sport = str(getattr(prop, "sport", "")).strip().upper()
        market = " ".join((
            str(getattr(prop, "market", "")),
            str(getattr(prop, "marketKey", "")),
            str(getattr(prop, "category", "")),
        )).lower()
        if sport != "MLB" or "strikeout" not in market:
            continue
        event_date = _parse_event_date(getattr(prop, "startTimeUtc", ""))
        if event_date is None:
            continue
        source_player_id = str(getattr(prop, "sourcePlayerId", "") or "").strip()
        pitcher_id = source_player_id if source_player_id.isdigit() else None
        if pitcher_id is None:
            resolved = mlb_player_id(str(getattr(prop, "player", "") or ""))
            pitcher_id = str(resolved) if resolved is not None else None
        if pitcher_id:
            metrics = _pitcher_metrics(pitcher_id, event_date)
            if getattr(prop, "pitcherKPercent", None) is None and metrics.get("pitcher_k_pct") is not None:
                prop.pitcherKPercent = metrics["pitcher_k_pct"]
            if getattr(prop, "pitcherCsw", None) is None and metrics.get("pitcher_csw") is not None:
                prop.pitcherCsw = metrics["pitcher_csw"]
            if getattr(prop, "pitchesPerStart", None) is None and metrics.get("pitches_per_start") is not None:
                prop.pitchesPerStart = metrics["pitches_per_start"]
            if getattr(prop, "pitchesPerBatter", None) is None and metrics.get("pitches_per_batter") is not None:
                prop.pitchesPerBatter = metrics["pitches_per_batter"]

        lineup_matchup = getattr(prop, "mlbProjectedLineupMatchup", None)
        if isinstance(lineup_matchup, dict) and getattr(prop, "lineupKPercent", None) is None:
            lineup_rate = _lineup_k_rate(lineup_matchup.get("opposingLineup") or [], event_date)
            if lineup_rate is not None:
                prop.lineupKPercent = lineup_rate

        if getattr(prop, "umpireKBoost", None) is None:
            umpire_boost = _umpire_boost(str(getattr(prop, "apiSportsGameId", "") or ""))
            if umpire_boost is not None:
                prop.umpireKBoost = umpire_boost
        if getattr(prop, "parkKFactor", None) is None:
            prop.parkKFactor = _park_k_factor(str(getattr(prop, "matchup", "") or ""))