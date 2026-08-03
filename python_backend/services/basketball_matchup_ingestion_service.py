"""Join persisted pregame basketball matchup evidence onto live player props."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from statistics import fmean
from datetime import datetime, timezone
import logging

from database.postgres import database_is_configured, get_database_pool

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class BasketballMatchupContext:
    opponent_team_id: str
    position: str
    allowance_average: float | None
    allowance_league_average: float | None
    allowance_multiplier: float | None
    pace_multiplier: float | None
    direct_average: float | None
    direct_sample_size: int
    defensive_scheme: str
    matchup_multiplier: float | None
    is_home: bool | None


def _number(value: object) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _market_value(market: str, row: dict[str, object]) -> float | None:
    key = market.lower()
    points, rebounds, assists = (_number(row.get(name)) or 0 for name in ("points", "rebounds", "assists"))
    if "points" in key and "rebounds" in key and "assists" in key:
        return points + rebounds + assists
    if "points" in key and "rebounds" in key:
        return points + rebounds
    if "points" in key and "assists" in key:
        return points + assists
    if "rebounds" in key and "assists" in key:
        return rebounds + assists
    if "rebound" in key:
        return rebounds
    if "assist" in key:
        return assists
    if "point" in key:
        return points
    return None


def _scheme_label(pressure: float | None, switch: float | None) -> str:
    if pressure is None and switch is None:
        return ""
    if (pressure or 0) >= .58:
        return "HIGH PICK-AND-ROLL PRESSURE PROXY"
    if (switch or 0) >= .32:
        return "SWITCH-HEAVY PROXY"
    return "STANDARD COVERAGE PROXY"


def enrich_basketball_matchups(props: list[object]) -> None:
    """Use only observations stored before the upcoming event starts."""
    basketball = [p for p in props if str(getattr(p, "sport", "")).upper() in {"NBA", "WNBA"}]
    if not basketball or not database_is_configured():
        return
    try:
        with get_database_pool().connection() as connection, connection.cursor() as cursor:
            cursor.execute("""select sport,league_game_id,lower(player_name),player_id,team_id,
                game_date,minutes,points,rebounds,assists,raw
                from historical_basketball_game_logs
                where game_date between current_date-interval '180 days' and current_date-interval '1 day'
                  and sport in ('NBA','WNBA') order by game_date""")
            rows = cursor.fetchall()
            cursor.execute("""select sport,team_id,opponent_id,starts_at,is_home
                from team_schedule where starts_at between now()-interval '1 day' and now()+interval '14 days'""")
            schedules = cursor.fetchall()
            cursor.execute("""select sport,team_id,pick_roll_pressure_proxy,switch_rate_proxy,
                defender_difficulty,confidence from team_matchup_profiles
                where season in (extract(year from current_date)::text,
                  concat(extract(year from current_date-interval '1 year')::int,'-',
                         right(extract(year from current_date)::text,2)))""")
            profiles = cursor.fetchall()
    except Exception as exc:
        logger.warning("basketball matchup enrichment unavailable: %s", exc)
        return

    games: dict[tuple[str, str], set[str]] = defaultdict(set)
    history: list[dict[str, object]] = []
    latest_player: dict[tuple[str, str], tuple[str, str]] = {}
    team_possessions: dict[tuple[str, str], float] = defaultdict(float)
    for sport, game_id, name, player_id, team_id, game_date, minutes, points, rebounds, assists, raw in rows:
        raw = raw if isinstance(raw, dict) else {}
        item = {"sport": str(sport), "game": str(game_id), "name": str(name),
                "player_id": str(player_id), "team": str(team_id), "date": game_date,
                "minutes": minutes, "points": points, "rebounds": rebounds, "assists": assists,
                "position": str(raw.get("START_POSITION") or raw.get("POSITION") or "").upper()}
        history.append(item)
        games[(str(sport), str(game_id))].add(str(team_id))
        latest_player[(str(sport), str(name))] = (str(team_id), item["position"])
        possessions = (_number(raw.get("FGA")) or 0) + .44 * (_number(raw.get("FTA")) or 0)
        possessions += (_number(raw.get("TOV")) or 0) - (_number(raw.get("OREB")) or 0)
        team_possessions[(str(sport), f"{game_id}:{team_id}")] += possessions
    schedules_by_team: dict[tuple[str, str], list[tuple[object, ...]]] = defaultdict(list)
    for sport, team_id, opponent_id, starts_at, is_home in schedules:
        schedules_by_team[(str(sport), str(team_id))].append((starts_at, str(opponent_id), bool(is_home)))
    profile_by_team = {(str(row[0]), str(row[1])): row[2:] for row in profiles}
    pace_by_team: dict[tuple[str, str], list[float]] = defaultdict(list)
    all_paces: dict[str, list[float]] = defaultdict(list)
    for (sport, game_id), teams in games.items():
        for team in teams:
            value = team_possessions.get((sport, f"{game_id}:{team}"), 0)
            if value > 0:
                pace_by_team[(sport, team)].append(value)
                all_paces[sport].append(value)

    for prop in basketball:
        sport, name = str(prop.sport).upper(), str(prop.player).lower()
        player_identity = latest_player.get((sport, name))
        if not player_identity:
            continue
        team_id, position = player_identity
        candidates = schedules_by_team.get((sport, team_id), [])
        opponent_id, is_home = "", None
        if candidates:
            try:
                target = datetime.fromisoformat(
                    str(getattr(prop, "startTimeUtc", "")).replace("Z", "+00:00")
                )
                if target.tzinfo is None:
                    target = target.replace(tzinfo=timezone.utc)
            except ValueError:
                target = datetime.now(timezone.utc)
            matching = sorted(
                candidates,
                key=lambda row: abs((row[0] - target).total_seconds()),
            )
            _, opponent_id, is_home = matching[0]
        if not opponent_id:
            continue
        allowed, direct = [], []
        league_position = []
        for row in history:
            if row["sport"] != sport or (position and row["position"] != position):
                continue
            value = _market_value(str(prop.market), row)
            if value is None or not row["minutes"]:
                continue
            league_position.append(value)
            opponents = games.get((sport, str(row["game"])), set()) - {str(row["team"])}
            if opponent_id in opponents:
                allowed.append(value)
                if row["name"] == name:
                    direct.append(value)
        allowance = fmean(allowed) if allowed else None
        league = fmean(league_position) if league_position else None
        allowance_multiplier = (
            max(.90, min(1.10, allowance / league)) if allowance is not None and league else None
        )
        league_pace = fmean(all_paces[sport]) if all_paces[sport] else None
        team_pace = pace_by_team.get((sport, team_id), [])
        opponent_pace = pace_by_team.get((sport, opponent_id), [])
        pace = (
            max(.92, min(1.08, (fmean(team_pace) + fmean(opponent_pace)) / 2 / league_pace))
            if team_pace and opponent_pace and league_pace else None
        )
        profile = profile_by_team.get((sport, opponent_id))
        scheme = _scheme_label(profile[0], profile[1]) if profile else ""
        profile_multiplier = max(.94, min(1.06, 1 - float(profile[2]) * .04)) if profile else 1.0
        # Keep the profile adjustment separate from positional allowance so the
        # projection layer does not apply the same defensive evidence twice.
        matchup_multiplier = round(profile_multiplier, 4) if profile else None
        prop.opponentAllowanceByPosition = round(allowance, 3) if allowance is not None else None
        prop.opponentAllowanceLeagueAverage = round(league, 3) if league is not None else None
        prop.opponentPosition = position
        prop.defensiveScheme = scheme
        prop.directMatchupAverage = round(fmean(direct), 3) if direct else None
        prop.directMatchupSampleSize = len(direct)
        prop.isHome = is_home
        prop.paceMultiplier = round(pace, 4) if pace is not None else None
        prop.opponentDefenseMultiplier = round(allowance_multiplier, 4) if allowance_multiplier is not None else None
        prop.matchupMultiplier = matchup_multiplier
        prop.matchupContext = (
            f"{position or 'POSITION'} allowance based on {len(allowed)} pregame observations; "
            f"{len(direct)} direct matchups"
        )
