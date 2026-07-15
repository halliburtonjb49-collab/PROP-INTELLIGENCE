from pydantic import BaseModel, Field


class StrategyRecommendation(BaseModel):
    name: str = ""
    sample_size: int = 0
    hit_rate: float = 0
    average_edge: float = 0
    average_confidence: float = 0


class PropBuilderStrategyResponse(BaseModel):
    enough_data: bool = False
    minimum_required_legs: int = 10
    resolved_legs: int = 0
    recommended_sport: StrategyRecommendation | None = None
    recommended_prop_site: StrategyRecommendation | None = None
    recommended_market: StrategyRecommendation | None = None
    recommended_minimum_edge: int = 60
    recommended_minimum_confidence: int = 60
    recommended_leg_count: int = 3
    warnings: list[str] = Field(
        default_factory=list,
    )
