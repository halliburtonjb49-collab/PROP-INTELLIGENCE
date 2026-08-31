from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class TravelLeg(BaseModel):
    miles: float = Field(default=0, ge=0)
    timezone_change_hours: float = Field(default=0, ge=0, le=12)
    is_road_game: bool = False


class FatigueRequest(BaseModel):
    rest_days: float = Field(default=1, ge=0, le=14)
    recent_minutes: list[float] = Field(default_factory=list)
    travel_legs: list[TravelLeg] = Field(default_factory=list)
    consecutive_games: int = Field(default=1, ge=1, le=10)


class ScheduleGame(BaseModel):
    starts_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    utc_offset_hours: float = Field(ge=-12, le=14)
    is_road_game: bool = False
    minutes: float | None = Field(default=None, ge=0, le=80)


class ScheduleFatigueRequest(BaseModel):
    upcoming_game: ScheduleGame
    previous_games: list[ScheduleGame] = Field(default_factory=list, max_length=10)


class OfficiatingRequest(BaseModel):
    sport: Literal["NBA", "WNBA", "MLB"]
    market: str
    baseline: float
    crew_whistle_rate_index: float = Field(default=1, ge=.5, le=1.5)
    strike_zone_width_index: float = Field(default=1, ge=.5, le=1.5)
    player_foul_rate: float = Field(default=0, ge=0, le=1)


class MatchupRequest(BaseModel):
    market: str
    baseline: float
    blitz_rate: float = Field(default=0, ge=0, le=1)
    switch_rate: float = Field(default=0, ge=0, le=1)
    defender_difficulty: float = Field(default=0, ge=-1, le=1)


class ContextResearchRequest(BaseModel):
    player: str = Field(min_length=2, max_length=120)
    sport: Literal["NBA", "WNBA"] = "NBA"
    metrics: list[Literal[
        "points", "rebounds", "assists", "steals", "blocks", "threes"
    ]] = Field(default_factory=lambda: ["points", "rebounds", "assists"], min_length=1, max_length=6)
    threshold: float = Field(default=20, ge=0, le=250)
    limit: int = Field(default=40, ge=5, le=100)


class UsageTotalsInput(BaseModel):
    player_fga: float = Field(ge=0)
    player_fta: float = Field(ge=0)
    player_tov: float = Field(ge=0)
    player_minutes: float = Field(gt=0)
    team_fga: float = Field(ge=0)
    team_fta: float = Field(ge=0)
    team_tov: float = Field(ge=0)
    team_minutes: float = Field(gt=0)


class WowyUsageRequest(BaseModel):
    sport: Literal["WNBA"] = "WNBA"
    player: str = Field(min_length=2, max_length=120)
    teammate: str = Field(min_length=2, max_length=120)
    on: UsageTotalsInput
    off: UsageTotalsInput
    minimum_split_minutes: float = Field(default=100, ge=20, le=500)


class DixonColesRequest(BaseModel):
    sport: Literal["SOCCER", "NHL"]
    home_expected_goals: float = Field(gt=0, le=10)
    away_expected_goals: float = Field(gt=0, le=10)
    rho: float = Field(default=-0.05, ge=-0.5, le=0.5)
    total_line: float = Field(default=2.5, ge=0, le=20)
    max_goals: int = Field(default=8, ge=2, le=15)


class PropLegInput(BaseModel):
    id: str = ""
    player: str
    team: str = ""
    opponent: str = ""
    game_id: str = ""
    sport: str
    market: str
    side: Literal["OVER", "UNDER"]
    baseline_projection: float | None = Field(default=None, ge=0)
    line: float | None = Field(default=None, ge=0)
    volatility: float | None = Field(default=None, gt=0)


class CorrelationRequest(BaseModel):
    legs: list[PropLegInput] = Field(min_length=2, max_length=12)


class GameScriptRequest(BaseModel):
    script: Literal["CLOSE", "HOME_BLOWOUT", "AWAY_BLOWOUT", "SHOOTOUT", "LOW_SCORING"]
    sport: str
    props: list[PropLegInput] = Field(default_factory=list, max_length=12)
    simulations: int = Field(default=10_000, ge=500, le=50_000)
    seed: int = Field(default=42, ge=0, le=2_147_483_647)
    regression_weight: float = Field(default=0.0, ge=0, le=1)
    pace_adjustment: float = Field(default=1.0, ge=0.75, le=1.25)
    minutes_adjustment: float = Field(default=1.0, ge=0.5, le=1.5)
    usage_adjustment: float = Field(default=1.0, ge=0.5, le=1.5)
    weather_adjustment: float = Field(default=1.0, ge=0.8, le=1.2)
    lineup_status: Literal["UNCHANGED", "CONFIRMED", "LIMITED", "BENCH", "OUT"] = "UNCHANGED"


class SimilarityCandidate(BaseModel):
    player: str
    stretch: list[float] = Field(min_length=2, max_length=20)
    next_game_value: float
    context: str = ""


class SimilarityRequest(BaseModel):
    player: str
    recent_stretch: list[float] = Field(min_length=2, max_length=20)
    candidates: list[SimilarityCandidate] = Field(default_factory=list, max_length=1000)
    limit: int = Field(default=5, ge=1, le=25)


class DatabaseSimilarityRequest(BaseModel):
    player: str
    sport: str
    market: str
    recent_stretch: list[float] = Field(min_length=3, max_length=20)
    limit: int = Field(default=5, ge=1, le=25)


class SentimentEvent(BaseModel):
    prop_id: str
    action: Literal[
        "VIEW", "SEARCH", "CLICK", "WATCHLIST", "PICK_OVER", "PICK_UNDER",
        "APP_OPEN", "ONBOARDING_COMPLETE", "ONBOARDING_SKIPPED",
        "DASHBOARD_READY", "SITE_FILTER", "VERDICT_FILTER",
        "PROP_SELECTED", "SLIP_LOCKED", "PAYWALL_VIEW",
        "CHECKOUT_STARTED", "CHECKOUT_FAILED", "PURCHASE_COMPLETED",
        "SLOW_LOAD", "ERROR", "API_SUCCESS", "API_FAILURE",
        "PROP_LOAD_SUCCESS", "PROP_LOAD_FAILURE", "AUTH_FAILURE",
        "MEDIA_FAILURE", "SERVICE_WORKER_VERSION", "SCREEN_TIMING", "WEB_VITAL",
        "LANDING_VIEW", "SIGNUP_STARTED", "EMAIL_VERIFIED", "FIRST_PROP",
        "PI_INTELLIGENCE_OPENED", "RETURNING_USER",
    ]
    duration_ms: int | None = Field(default=None, ge=0, le=300000)
    metadata: dict[str, str] = Field(default_factory=dict)


class SentimentBatchRequest(BaseModel):
    events: list[SentimentEvent] = Field(min_length=1, max_length=100)


class AlertCondition(BaseModel):
    field: str
    operator: Literal["EQ", "NE", "LT", "LTE", "GT", "GTE", "IN", "CONTAINS"]
    value: object


class CompoundAlertRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    conditions: list[AlertCondition] = Field(min_length=1, max_length=12)
    logic: Literal["ALL", "ANY"] = "ALL"
    snapshot: dict[str, object] = Field(default_factory=dict)


class AlertSnapshotRequest(BaseModel):
    snapshot: dict[str, object]


class HistoricalFeatureRequest(BaseModel):
    values: list[float] = Field(min_length=3, max_length=200)
    minutes: list[float] = Field(default_factory=list, max_length=200)
    window: int = Field(default=10, ge=3, le=50)


class PredictionSnapshotRequest(BaseModel):
    prop_id: str
    player_id: str
    sport: str
    market: str
    side: Literal["OVER", "UNDER"]
    line: float
    projection: float
    hit_probability: float = Field(ge=0, le=1)
    model_version: str = "intelligence-v1"
    inputs: dict[str, object] = Field(default_factory=dict)
    event_time: str | None = None


class PredictionGradeRequest(BaseModel):
    actual_value: float


class ClosingLineValueRequest(BaseModel):
    side: Literal["OVER", "UNDER"]
    entry_line: float = Field(gt=0)
    closing_line: float = Field(gt=0)
    entry_odds: int | None = None
    closing_odds: int | None = None
    closing_opposite_odds: int | None = None


class PropIntelligenceRequest(BaseModel):
    player: str = Field(min_length=1, max_length=120)
    sport: str = Field(min_length=1, max_length=20)
    market: str = Field(min_length=1, max_length=40)
    line: float = Field(gt=0)
    projected_mean: float = Field(ge=0)
    projected_std_dev: float = Field(ge=0)
    sharp_over_odds: float | None = Field(default=None, gt=0)
    sharp_under_odds: float | None = Field(default=None, gt=0)
    retail_over_odds: float | None = Field(default=None, gt=0)
    retail_under_odds: float | None = Field(default=None, gt=0)
    bankroll: float = Field(default=1000, gt=0)
    kelly_fraction: float = Field(default=0.25, ge=0, le=1)
    simulations: int = Field(default=2000, ge=100, le=100000)
    seed: int = Field(default=42, ge=0, le=2_147_483_647)
    pitcher_k_pct: float | None = Field(default=None, ge=0, le=1)
    lineup_k_pct: float | None = Field(default=None, ge=0, le=1)
    pitches_per_start: float | None = Field(default=None, gt=0, le=160)
    pitches_per_batter: float | None = Field(default=None, gt=1, le=8)
    pitcher_csw: float | None = Field(default=None, ge=0, le=1)
    lineup_csw_against: float | None = Field(default=None, ge=0, le=1)
    temp_f: float = Field(default=70, ge=-20, le=120)
    umpire_k_boost: float = Field(default=0.0, ge=-0.1, le=0.1)
    park_k_factor: float = Field(default=1.0, ge=0.8, le=1.2)
    league_avg_k_rate: float = Field(default=0.224, ge=0.1, le=0.5)
    league_avg_csw: float = Field(default=0.275, ge=0.1, le=0.6)
