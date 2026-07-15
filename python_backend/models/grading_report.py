from pydantic import BaseModel


class GradingLegReport(BaseModel):
    prop_id: str
    player: str
    market: str
    line: float
    side: str
    matched: bool
    matched_player: str = ""
    normalized_market: str = ""
    result_value: float | None = None
    result_status: str = "pending"
    reason: str = ""


class GradingReport(BaseModel):
    game_id: str
    stats_found: int
    legs_checked: int
    legs_matched: int
    legs_updated: int
    reports: list[GradingLegReport]
