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
    action: Literal["VIEW", "SEARCH", "CLICK", "WATCHLIST", "PICK_OVER", "PICK_UNDER"]


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
