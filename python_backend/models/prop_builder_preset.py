from pydantic import BaseModel, Field


class PropBuilderPresetCreate(BaseModel):
    name: str = Field(
        min_length=1,
        max_length=50,
    )
    sports: list[str] = Field(
        default_factory=list,
    )
    prop_sites: list[str] = Field(
        default_factory=list,
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
    same_game_allowed: bool = False
    build_mode: str = "SAME_SPORT"
    risk_mode: str = "BALANCED"
    side_preference: str = "ANY"


class PropBuilderPreset(PropBuilderPresetCreate):
    id: int
