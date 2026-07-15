from datetime import datetime

from pydantic import BaseModel, Field


class PropBuilderHistoryCreate(BaseModel):
    build_mode: str
    risk_mode: str = "BALANCED"
    sports: list[str] = Field(
        default_factory=list,
    )
    prop_sites: list[str] = Field(
        default_factory=list,
    )
    markets: list[str] = Field(
        default_factory=list,
    )
    requested_legs: int
    generated_legs: int
    average_edge: float = 0
    average_confidence: float = 0
    legs: list[dict] = Field(
        default_factory=list,
    )
    status: str = "pending"
    legs_won: int = 0
    legs_lost: int = 0
    legs_pushed: int = 0
    legs_pending: int = 0
    hit_rate: float = 0


class PropBuilderHistory(PropBuilderHistoryCreate):
    id: int
    created_at: datetime
