from typing import Literal

from pydantic import BaseModel, Field


class PropBuilderRequest(BaseModel):
    sports: list[str] = Field(default_factory=list)
    prop_sites: list[str] = Field(
        default_factory=lambda: [
            "PrizePicks",
            "Underdog",
            "FanDuel",
            "Sleeper",
            "Draft Picks",
        ]
    )
    markets: list[str] = Field(
        default_factory=list,
    )
    leg_count: int = Field(
        default=3,
        ge=2,
        le=8,
    )
    minimum_edge: int = Field(
        default=60,
        ge=0,
        le=100,
    )
    minimum_confidence: int = Field(
        default=60,
        ge=0,
        le=100,
    )
    locked_legs: list["PropBuilderLeg"] = Field(
        default_factory=list,
    )
    excluded_prop_ids: list[str] = Field(
        default_factory=list,
    )
    correlation_guard_enabled: bool = True
    maximum_legs_per_game: int = Field(
        default=1,
        ge=1,
        le=8,
    )
    maximum_legs_per_team: int = Field(
        default=2,
        ge=1,
        le=8,
    )
    maximum_legs_per_player: int = Field(
        default=1,
        ge=1,
        le=4,
    )
    same_game_allowed: bool = False
    build_mode: Literal[
        "SAME_SPORT",
        "MIXED_SPORTS",
    ] = "SAME_SPORT"
    risk_mode: Literal[
        "SAFE",
        "BALANCED",
        "AGGRESSIVE",
    ] = "BALANCED"
    side_preference: Literal[
        "ANY",
        "OVER",
        "UNDER",
    ] = "ANY"


class PropBuilderLeg(BaseModel):
    prop_id: str
    builder_position: int = 0
    custom_label: str = ""
    manual_note: str = ""
    original_line: float | None = None
    original_odds: int | None = None
    current_line: float | None = None
    current_odds: int | None = None
    line_change: float = 0
    odds_change: int = 0
    movement_status: str = "UNCHANGED"
    last_line_check: str | None = None
    result_status: str = "pending"
    result_value: float | None = None
    event_id: str = ""
    api_sports_game_id: str = ""
    player: str
    sport: str
    matchup: str
    prop_site: str
    market: str
    line: float
    side: str
    odds: float | None = None
    edge: int
    confidence: int
    game_time: str = ""
    image_path: str = ""
    home_team: str = ""
    away_team: str = ""
    player_team: str = ""
    selection_reason: str = ""
    strategy_match: bool = False
    historical_hit_rate: float | None = None
    historical_sample_size: int = 0
    risk_factors: list[str] = Field(
        default_factory=list,
    )


class PropBuilderResponse(BaseModel):
    requested_legs: int
    generated_legs: int
    available_candidate_count: int = 0
    filtered_out_count: int = 0
    build_messages: list[str] = Field(
        default_factory=list,
    )
    average_edge: float
    average_confidence: float
    prop_sites: list[str]
    sports: list[str]
    markets: list[str] = Field(
        default_factory=list,
    )
    correlation_warnings: list[str] = Field(
        default_factory=list,
    )
    build_mode: str
    risk_mode: str = "BALANCED"
    legs: list[PropBuilderLeg]


class PropReplacementRequest(BaseModel):
    current_prop_id: str
    sports: list[str] = Field(default_factory=list)
    prop_sites: list[str] = Field(
        default_factory=lambda: [
            "PrizePicks",
            "Underdog",
            "Sleeper",
            "FanDuel",
            "Draft Picks",
        ]
    )
    markets: list[str] = Field(
        default_factory=list,
    )
    minimum_edge: int = Field(
        default=60,
        ge=0,
        le=100,
    )
    minimum_confidence: int = Field(
        default=60,
        ge=0,
        le=100,
    )
    correlation_guard_enabled: bool = True
    maximum_legs_per_game: int = Field(
        default=1,
        ge=1,
        le=8,
    )
    maximum_legs_per_team: int = Field(
        default=2,
        ge=1,
        le=8,
    )
    maximum_legs_per_player: int = Field(
        default=1,
        ge=1,
        le=4,
    )
    build_mode: Literal[
        "SAME_SPORT",
        "MIXED_SPORTS",
    ] = "SAME_SPORT"
    risk_mode: Literal[
        "SAFE",
        "BALANCED",
        "AGGRESSIVE",
    ] = "BALANCED"
    side_preference: Literal[
        "ANY",
        "OVER",
        "UNDER",
    ] = "ANY"
    excluded_prop_ids: list[str] = Field(
        default_factory=list,
    )
    excluded_players: list[str] = Field(
        default_factory=list,
    )
    excluded_event_ids: list[str] = Field(
        default_factory=list,
    )


PropBuilderRequest.model_rebuild()
