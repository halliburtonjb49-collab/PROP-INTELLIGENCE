"""Conservative, auditable projections from persisted historical game logs.

The baseline is intentionally simple. It is a recency-weighted average of
nested trailing windows, shrunk toward a role-matched prior so a short hot
streak cannot carry a projection on its own. It requires a real player match
and minimum sample, and remains explicitly uncalibrated until prediction
snapshots have enough out-of-sample grades.
"""

from __future__ import annotations

from bisect import bisect_left
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from math import sqrt
from statistics import fmean
from threading import Lock
from typing import Iterable, Sequence
import re

from database.postgres import database_is_configured, get_database_pool
from services.projection_calibration_service import (
    confidence_from_probability,
    recency_weighted_baseline,
    recency_weights_for,
    shrink_toward_prior,
    shrinkage_k_for,
)
from services.prop_probability_service import evaluate_market

MODEL_VERSION = "baseline-v3"
MINIMUM_SAMPLE_SIZE = 8
# Deep enough that the season term in the recency blend is distinct from the
# 20-game window rather than a duplicate of it.
MAXIMUM_SAMPLE_SIZE = 40
_CACHE_TTL = timedelta(minutes=5)

# Role buckets are read off the population itself: players are ranked by their
# own long-run level and a player's prior is the mean of their bucket. That
# keeps a high-usage scorer from being shrunk toward a league-wide average that
# includes deep bench players.
PRIOR_BUCKETS = 3
PRIOR_MINIMUM_PLAYERS = 12


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
    prior: float | None = None
    prior_weight: float = 1.0


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


def role_bucket_prior(
    player_mean: float,
    population_means: Sequence[float],
    *,
    buckets: int = PRIOR_BUCKETS,
    minimum_players: int = PRIOR_MINIMUM_PLAYERS,
) -> float | None:
    """Mean long-run level of the players who occupy the same role tier.

    Returns None when the population is too thin to describe roles at all, in
    which case the caller must not shrink.
    """

    values = sorted(float(value) for value in population_means)
    if len(values) < max(buckets, minimum_players):
        return None
    rank = bisect_left(values, float(player_mean))
    bucket = min(buckets - 1, rank * buckets // len(values))
    start = bucket * len(values) // buckets
    end = (bucket + 1) * len(values) // buckets
    peers = values[start:end]
    return fmean(peers) if peers else None


def compute_baseline_projection(
    values: Iterable[float],
    *,
    line: float,
    sport: str = "",
    market: str = "",
    minimum_sample_size: int = MINIMUM_SAMPLE_SIZE,
    prior: float | None = None,
) -> BaselineProjection | None:
    ordered = [float(value) for value in values][-MAXIMUM_SAMPLE_SIZE:]
    if len(ordered) < minimum_sample_size:
        return None

    long_mean = fmean(ordered)
    baseline = recency_weighted_baseline(
        ordered,
        weights=recency_weights_for(sport, market),
    )
    projection, own_weight = shrink_toward_prior(
        baseline,
        prior,
        sample_size=len(ordered),
        k=shrinkage_k_for(sport, market),
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
        # The observed share of blanked games is what distinguishes a player
        # who scores steadily from one who is shut out half the time and
        # compensates when they do produce.
        zero_rate=sum(1 for value in ordered if value <= 0) / len(ordered),
    )
    hit_probability = evaluation.model_probability
    return BaselineProjection(
        projection=round(projection, 3),
        confidence=confidence_from_probability(hit_probability),
        sample_size=len(ordered),
        volatility=round(volatility, 3),
        historical_hit_rate=historical_hit_rate,
        hit_probability=hit_probability,
        prior=None if prior is None else round(float(prior), 3),
        prior_weight=round(own_weight, 4),
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
        self._population_cache: dict[tuple[str, str], list[float]] = {}
        self._lock = Lock()

    def _basketball_population(self, sport: str, market: str) -> list[float]:
        means: list[float] = []
        for (log_sport, _player), rows in self.basketball.items():
            if log_sport != sport:
                continue
            values = [
                value
                for row in rows
                if (value := basketball_market_value(market, row)) is not None
            ]
            if values:
                means.append(fmean(values))
        return means

    def _population_means(
        self,
        *,
        sport: str,
        market: str,
        stat: str | None = None,
        mlb_role: str | None = None,
    ) -> list[float]:
        """Long-run level of every player who has logs for this market."""

        if mlb_role is not None:
            cache_key = (sport, f"{mlb_role}:{stat}")
        else:
            cache_key = (sport, stat or market)
        cached = self._population_cache.get(cache_key)
        if cached is not None:
            return cached
        if mlb_role is not None:
            prefix = f"{mlb_role}:"
            means = [
                fmean(values)
                for (player_key, log_stat), values in self.mlb.items()
                if log_stat == stat and player_key.startswith(prefix) and values
            ]
        elif stat is not None:
            means = [
                fmean(values)
                for (log_sport, _player, log_stat), values in self.multi_sport.items()
                if log_sport == sport and log_stat == stat and values
            ]
        else:
            means = self._basketball_population(sport, market)
        self._population_cache[cache_key] = means
        return means

    def _prior_for(
        self,
        values: Sequence[float],
        *,
        sport: str,
        market: str,
        stat: str | None = None,
        mlb_role: str | None = None,
    ) -> float | None:
        if not values:
            return None
        population = self._population_means(
            sport=sport,
            market=market,
            stat=stat,
            mlb_role=mlb_role,
        )
        return role_bucket_prior(fmean(values), population)

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
            self._population_cache = {}
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
                values,
                line=line,
                sport=normalized_sport,
                market=market,
                prior=self._prior_for(
                    values, sport=normalized_sport, market=market
                ),
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
                values,
                line=line,
                sport=normalized_sport,
                market=market,
                prior=self._prior_for(
                    values, sport="SOCCER", market=market, stat=stat
                ),
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
                prior=self._prior_for(
                    values, sport=canonical, market=market, stat=stat
                ),
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
            values,
            line=line,
            sport=normalized_sport,
            market=market,
            prior=self._prior_for(
                values,
                sport=normalized_sport,
                market=market,
                stat=stat,
                mlb_role=role,
            ),
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
