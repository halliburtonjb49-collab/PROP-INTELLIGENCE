from datetime import datetime
from typing import Literal
from uuid import uuid4

from pydantic import BaseModel, Field


SlipStatus = Literal["active", "won", "lost"]


class SlipLeg(BaseModel):
    prop_id: str
    event_id: str = ""
    api_sports_game_id: str = ""
    player_id: str = ""
    custom_label: str = ""
    manual_note: str = ""
    game_status: str = "scheduled"
    game_completed: bool = False
    player: str
    sport: str
    matchup: str
    sportsbook: str
    market: str
    line: float
    side: Literal["OVER", "UNDER"]
    odds: float | None = None
    result_value: float | None = None
    result_status: Literal[
        "pending",
        "won",
        "lost",
        "push",
    ] = "pending"


class SlipCreate(BaseModel):
    legs: list[SlipLeg] = Field(min_length=1)
    stake: float = Field(default=0, ge=0)


class SlipPreview(BaseModel):
    legs: list[SlipLeg] = Field(min_length=1)
    stake: float = Field(gt=0)


class LegResultUpdate(BaseModel):
    prop_id: str
    result_value: float


class SlipResponse(BaseModel):
    id: str
    status: SlipStatus
    stake: float
    potential_payout: float
    created_at: str
    legs: list[SlipLeg]


def create_slip_response(
    request: SlipCreate,
    potential_payout: float,
) -> SlipResponse:
    return SlipResponse(
        id=str(uuid4()),
        status="active",
        stake=request.stake,
        potential_payout=potential_payout,
        created_at=datetime.now().isoformat(),
        legs=request.legs,
    )
