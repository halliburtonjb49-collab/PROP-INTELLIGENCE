from datetime import datetime
from typing import Literal
from uuid import uuid4

from pydantic import BaseModel, Field, model_validator


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
    game_start_time: str = ""
    player: str
    sport: str
    matchup: str
    sportsbook: str
    market: str
    line: float
    entry_line: float | None = None
    closing_line: float | None = None
    side: Literal["OVER", "UNDER"]
    odds: float | None = None
    closing_odds: float | None = None
    line_clv: float | None = None
    line_clv_percent: float | None = None
    beat_closing_line: bool | None = None
    result_value: float | None = None
    result_status: Literal[
        "pending",
        "won",
        "lost",
        "push",
    ] = "pending"

    @model_validator(mode="after")
    def snapshot_entry_line(self) -> "SlipLeg":
        if self.entry_line is None:
            self.entry_line = self.line
        return self


class SlipCreate(BaseModel):
    legs: list[SlipLeg] = Field(min_length=1)
    stake: float = Field(default=0, ge=0)


class SlipPreview(BaseModel):
    legs: list[SlipLeg] = Field(min_length=1)
    stake: float = Field(gt=0)


class LegResultUpdate(BaseModel):
    prop_id: str
    result_value: float


class ClosingLineUpdate(BaseModel):
    prop_id: str
    closing_line: float = Field(gt=0)
    closing_odds: int | None = None


class SlipClosingLinesUpdate(BaseModel):
    updates: list[ClosingLineUpdate] = Field(min_length=1)


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
