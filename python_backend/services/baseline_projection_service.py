"""Conservative, auditable projections from persisted historical game logs.

The baseline is intentionally simple. It is a time-ordered weighted average,
requires a real player match and minimum sample, and remains explicitly
uncalibrated until prediction snapshots have enough out-of-sample grades.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from math import sqrt
from statistics import fmean, median
from threading import Lock
from typing import Iterable
import re

from database.postgres import database_is_configured, get_database_pool
from services.projection_calibration_service import (
    confidence_from_probability,
    exponentially_weighted_mean,
)
from services.prop_probability_service import evaluate_market

MODEL_VERSION = "baseline-v2"
MINIMUM_SAMPLE_SIZE = 8
MAXIMUM_SAMPLE_SIZE = 20
_CACHE_TTL = timedelta(minutes=5)


@dataclass(frozen=True)
class BaselineProjection:
    projection: float
    confidence: int
    sample_size: int
    volatility: float
    historical_hit_rate: int
    hit_probability: float
    model_version: str = MODEL_VERSION
    source: str = "historical-game-logs"
    calibrated: bool = False


def _normalized(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value or "").lower())


def _market_text(value: object) -> str:
    return re.sub(r"\s+", " ", str(value or "").lower().replace("_", " ")).strip()


def basketball_market_value(market: object, row: tuple[object, ...]) -> float | None:
    text = _market_text(market)
    points, rebounds, assists, steals, blocks, turnovers, threes = [
        float(value or 0) for value in row
    ]
    if "points rebounds assists" in text or text.endswith(" pra") or text == "pra":
        return points + rebounds + assists
    if "points rebounds" in text:
        return points + rebounds
    if "points assists" in text:
        return points + assists
    if "rebounds assists" in text:
        return rebounds + assists
    if "three" in text or "3 pointer" in text:
        return threes
    if "rebound" in text:
        return rebounds
    if "assist" in text:
        return assists
    if "steal" in text:
        return steals
    if "block" in text:
        return blocks
    if "turnover" in text:
        return turnovers
    if "point" in text:
        return points
    return None


def compute_baseline_projection(
    values: Iterable[float],
    *,
    line: float,
    sport: str = "",
    market: str = "",
    minimum_sample_size: int = MINIMUM_SAMPLE_SIZE,
) -> BaselineProjection | None:
    ordered = [float(value) for value in values][-MAXIMUM_SAMPLE_SIZE:]
    if len(ordered) < minimum_sample_size:
        return None

    long_mean = fmean(ordered)
    recent = ordered[-min(5, len(ordered)) :]
    recent_mean = fmean(recent)
    robust_center = median(ordered)
    weighted_mean = exponentially_weighted_mean(ordered)
    projection = (
        (weighted_mean * 0.50)
        + (recent_mean * 0.20)
        + (long_mean * 0.15)
        + (robust_center * 0.15)
    )
    variance = sum((value - long_mean) ** 2 for value in ordered) / max(
        1, len(ordered) - 1
    )
    volatility = sqrt(variance)

    side_is_over = projection > float(line)
    hits = sum(
        1
        for value in ordered
        if (value > float(line) if side_is_over else value < float(line))
    )
    historical_hit_rate = round(hits / len(ordered) * 100)
    evaluation = evaluate_market(
        projection=projection,
        line=line,
        volatility=volatility,
        side="OVER" if side_is_over else "UNDER",
        sample_size=len(ordered),
        sport=sport,
        market=market,
        model_calibrated=False,
        empirical_hit_rate=historical_hit_rate / 100,
        sharp_probability=None,
        decimal_odds=None,
    )
    hit_probability = evaluation.model_probability
    return BaselineProjection(
        projection=round(projection, 3),
        confidence=confidence_from_probability(hit_probability),
        sample_size=len(ordered),
        volatility=round(volatility, 3),
        historical_hit_rate=historical_hit_rate,
        hit_probability=hit_probability,
    )


def baseline_is_actionable(
    projection: BaselineProjection,
    *,
    recommendation_tier: str,
) -> bool:
    return recommendation_tier != "Pass" and projection.historical_hit_rate >= 55


class _HistoricalProjectionIndex:
    def __init__(self) -> None:
        self.loaded_at: datetime | None = None
        self.basketball: dict[tuple[str, str], list[tuple[object, ...]]] = {}
        self.mlb: dict[tuple[str, str], list[float]] = {}
        self.multi_sport: dict[tuple[str, str, str], list[float]] = {}
        self._lock = Lock()

    def _fresh(self) -> bool:
        return (
            self.loaded_at is not None
            and datetime.now(timezone.utc) - self.loaded_at < _CACHE_TTL
        )

    def ensure_loaded(self) -> None:
        if self._fresh() or not database_is_configured():
            return
        with self._lock:
            if self._fresh():
                return
            basketball: dict[tuple[str, str], list[tuple[object, ...]]] = {}
            mlb: dict[tuple[str, str], list[float]] = {}
            multi_sport: dict[tuple[str, str, str], list[float]] = {}
            with get_database_pool().connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        """select sport,player_name,points,rebounds,assists,steals,
                            blocks,turnovers,threes from (
                            select sport,player_name,points,rebounds,assists,steals,
                            blocks,turnovers,threes,
                            row_number() over(
                                partition by sport,lower(player_name)
                                order by game_date desc,updated_at desc
                            ) recent_rank
                            from historical_basketball_game_logs
                            where game_date < current_date
                        ) logs where recent_rank <= %s
                        order by sport,lower(player_name),recent_rank desc""",
                        (MAXIMUM_SAMPLE_SIZE,),
                    )
                    for row in cursor.fetchall():
                        key = (str(row[0]).upper(), _normalized(row[1]))
                        basketball.setdefault(key, []).append(tuple(row[2:]))

                    cursor.execute(
                        """with batter_games as (
                            select batter_id,game_date,
                                count(*) filter(where events in
                                    ('single','double','triple','home_run')) hits,
                                coalesce(sum(case events when 'single' then 1
                                    when 'double' then 2 when 'triple' then 3
                                    when 'home_run' then 4 else 0 end),0) total_bases,
                                count(*) filter(where events='home_run') home_runs
                            from historical_mlb_pitches
                            where game_date < current_date
                                and game_date >= current_date - interval '365 days'
                                and batter_id <> ''
                            group by batter_id,game_date
                        ), pitcher_games as (
                            select pitcher_id,game_date,
                                count(*) filter(where events in
                                    ('strikeout','strikeout_double_play')) strikeouts
                            from historical_mlb_pitches
                            where game_date < current_date
                                and game_date >= current_date - interval '365 days'
                                and pitcher_id <> ''
                            group by pitcher_id,game_date
                        )
                        select 'batter',batter_id,game_date,hits,total_bases,home_runs,0
                        from batter_games
                        union all
                        select 'pitcher',pitcher_id,game_date,0,0,0,strikeouts
                        from pitcher_games
                        order by game_date""",
                    )
                    for role, player_id, _game_date, hits, bases, homers, strikeouts in cursor.fetchall():
                        prefix = f"{role}:{player_id}"
                        mlb.setdefault((prefix, "hits"), []).append(float(hits or 0))
                        mlb.setdefault((prefix, "total_bases"), []).append(float(bases or 0))
                        mlb.setdefault((prefix, "home_runs"), []).append(float(homers or 0))
                        mlb.setdefault((prefix, "strikeouts"), []).append(float(strikeouts or 0))

                    cursor.execute(
                        """select sport,player_name,stats from (
                            select sport,player_name,stats,
                            row_number() over(
                              partition by sport,lower(player_name)
                              order by game_date desc,updated_at desc
                            ) recent_rank
                            from historical_player_game_logs
                            where game_date < current_date
                        ) logs where recent_rank <= %s
                        order by sport,lower(player_name),recent_rank desc""",
                        (MAXIMUM_SAMPLE_SIZE,),
                    )
                    for sport, player_name, stats in cursor.fetchall():
                        if not isinstance(stats, dict):
                            continue
                        for stat, value in stats.items():
                            try:
                                number = float(value)
                            except (TypeError, ValueError):
                                continue
                            key = (str(sport).upper(), _normalized(player_name), str(stat))
                            multi_sport.setdefault(key, []).append(number)

            self.basketball = basketball
            self.mlb = {
                key: values[-MAXIMUM_SAMPLE_SIZE:] for key, values in mlb.items()
            }
            self.multi_sport = {
                key: values[-MAXIMUM_SAMPLE_SIZE:]
                for key, values in multi_sport.items()
            }
            self.loaded_at = datetime.now(timezone.utc)

    def project(
        self,
        *,
        sport: str,
        player: str,
        player_id: str,
        market: str,
        line: float,
    ) -> BaselineProjection | None:
        self.ensure_loaded()
        normalized_sport = sport.upper()
        if normalized_sport in {"NBA", "WNBA"}:
            rows = self.basketball.get((normalized_sport, _normalized(player)), [])
            values = [
                value
                for row in rows
                if (value := basketball_market_value(market, row)) is not None
            ]
            return compute_baseline_projection(
                values, line=line, sport=normalized_sport, market=market
            )

        if normalized_sport == "SOCCER":
            text = _market_text(market)
            exact_markets = {
                "player shots": "shots",
                "shots": "shots",
                "player shots on target": "shots_on_target",
                "shots on target": "shots_on_target",
                "player assists": "assists",
                "assists": "assists",
                "player goal scorer anytime": "goals",
                "anytime goalscorer": "goals",
                "player to receive card": "received_card",
                "player card": "received_card",
                "player to receive red card": "received_red_card",
                "player red card": "received_red_card",
            }
            stat = exact_markets.get(text)
            if stat is None:
                return None
            values = self.multi_sport.get(
                ("SOCCER", _normalized(player), stat),
                [],
            )
            return compute_baseline_projection(
                values, line=line, sport=normalized_sport, market=market
            )

        if normalized_sport in {"TENNIS", "PGA", "GOLF", "UFC", "MMA"}:
            text = _market_text(market)
            specialty_markets = {
                "TENNIS": {
                    "player sets won": "sets_won", "sets won": "sets_won",
                    "player games won": "games_won", "games won": "games_won",
                    "player aces": "aces", "aces": "aces",
                    "player double faults": "double_faults",
                    "double faults": "double_faults",
                    "player breakpoints won": "breakpoints_won",
                    "breakpoints won": "breakpoints_won",
                    "player break points won": "breakpoints_won",
                    "break points won": "breakpoints_won",
                },
                "PGA": {
                    "player birdies": "birdies", "birdies": "birdies",
                    "player bogeys": "bogeys", "bogeys": "bogeys",
                    "player pars": "pars", "pars": "pars",
                    "player eagles": "eagles", "eagles": "eagles",
                    "player strokes": "round_score", "strokes": "round_score",
                    "round score": "round_score",
                },
                "UFC": {
                    "fighter significant strikes": "significant_strikes",
                    "fighter takedowns": "takedowns",
                    "fighter knockdowns": "knockdowns",
                    "fighter submission attempts": "submission_attempts",
                    "fighter fight time": "fight_time_seconds",
                },
            }
            canonical = "PGA" if normalized_sport == "GOLF" else "UFC" if normalized_sport == "MMA" else normalized_sport
            stat = specialty_markets[canonical].get(text)
            if stat is None:
                return None
            values = self.multi_sport.get((canonical, _normalized(player), stat), [])
            return compute_baseline_projection(
                values, line=line, sport=canonical, market=market,
                # UFC athletes compete far less often than team-sport athletes.
                # Three completed fights enables a visibly limited baseline;
                # downstream quality/calibration gates still prevent an A/B grade.
                minimum_sample_size=3 if canonical == "UFC" else MINIMUM_SAMPLE_SIZE,
            )

        if normalized_sport != "MLB" or not player_id:
            return None
        text = _market_text(market)
        if "strikeout" in text:
            role, stat = "pitcher", "strikeouts"
        elif "total base" in text:
            role, stat = "batter", "total_bases"
        elif "home run" in text:
            role, stat = "batter", "home_runs"
        elif text in {"batter hits", "player hits", "hits"}:
            role, stat = "batter", "hits"
        else:
            return None
        values = self.mlb.get((f"{role}:{player_id}", stat), [])
        return compute_baseline_projection(
            values, line=line, sport=normalized_sport, market=market
        )


_INDEX = _HistoricalProjectionIndex()


def baseline_projection_for_prop(
    *,
    sport: str,
    player: str,
    player_id: str,
    market: str,
    line: float,
) -> BaselineProjection | None:
    try:
        return _INDEX.project(
            sport=sport,
            player=player,
            player_id=player_id,
            market=market,
            line=line,
        )
    except Exception:
        # Projection enrichment is optional; a database/provider issue must not
        # interrupt delivery of the underlying live prop feed.
        _INDEX.loaded_at = datetime.now(timezone.utc)
        return None
