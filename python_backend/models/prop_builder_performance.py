from pydantic import BaseModel, Field


class PerformanceBreakdown(BaseModel):
    name: str
    total_builds: int = 0
    won_builds: int = 0
    lost_builds: int = 0
    pushed_builds: int = 0
    pending_builds: int = 0
    legs_won: int = 0
    legs_lost: int = 0
    legs_pushed: int = 0
    legs_pending: int = 0
    build_win_rate: float = 0
    leg_hit_rate: float = 0


class RecentBuildPerformance(BaseModel):
    id: int
    created_at: str
    status: str
    build_mode: str
    sports: list[str] = Field(
        default_factory=list,
    )
    prop_sites: list[str] = Field(
        default_factory=list,
    )
    generated_legs: int = 0
    legs_won: int = 0
    legs_lost: int = 0
    legs_pushed: int = 0
    legs_pending: int = 0
    hit_rate: float = 0
    average_edge: float = 0
    average_confidence: float = 0


class PerformanceTrendPoint(BaseModel):
    date: str
    total_builds: int = 0
    won_builds: int = 0
    lost_builds: int = 0
    pending_builds: int = 0
    legs_won: int = 0
    legs_lost: int = 0
    legs_pushed: int = 0
    leg_hit_rate: float = 0


class LegPerformanceBreakdown(BaseModel):
    name: str
    total_legs: int = 0
    legs_won: int = 0
    legs_lost: int = 0
    legs_pushed: int = 0
    legs_pending: int = 0
    resolved_legs: int = 0
    leg_hit_rate: float = 0
    average_edge: float = 0
    average_confidence: float = 0


class PropBuilderPerformanceResponse(BaseModel):
    total_builds: int = 0
    won_builds: int = 0
    lost_builds: int = 0
    pushed_builds: int = 0
    pending_builds: int = 0
    build_win_rate: float = 0
    total_legs: int = 0
    legs_won: int = 0
    legs_lost: int = 0
    legs_pushed: int = 0
    legs_pending: int = 0
    leg_hit_rate: float = 0
    average_edge: float = 0
    average_confidence: float = 0
    by_sport: list[PerformanceBreakdown] = Field(
        default_factory=list,
    )
    by_prop_site: list[PerformanceBreakdown] = Field(
        default_factory=list,
    )
    leg_performance_by_sport: list[LegPerformanceBreakdown] = Field(
        default_factory=list,
    )
    leg_performance_by_prop_site: list[LegPerformanceBreakdown] = Field(
        default_factory=list,
    )
    leg_performance_by_market: list[LegPerformanceBreakdown] = Field(
        default_factory=list,
    )
    leg_performance_by_player: list[LegPerformanceBreakdown] = Field(
        default_factory=list,
    )
    recent_builds: list[RecentBuildPerformance] = Field(
        default_factory=list,
    )
    trend: list[PerformanceTrendPoint] = Field(
        default_factory=list,
    )
