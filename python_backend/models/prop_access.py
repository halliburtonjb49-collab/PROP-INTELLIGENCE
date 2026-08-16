"""Tier-safe API representations of sportsbook prop data."""
from pydantic import BaseModel, ConfigDict


class CorePropResponse(BaseModel):
    """Factual sportsbook data that is safe to deliver to Core members."""

    model_config = ConfigDict(extra="ignore")

    id: str
    gameId: str = ""
    eventId: str = ""
    apiSportsGameId: str = ""
    playerId: str = ""
    sourcePlayerId: str = ""
    canonicalPlayerId: str = ""
    player: str
    sport: str
    matchup: str
    sportsbook: str
    category: str = ""
    market: str
    marketKey: str = ""
    line: float
    openingLine: float | None = None
    currentLine: float | None = None
    lineMovedAtUtc: str = ""
    historicalHitRate: int | None = None
    recentHitRate: int | None = None
    temperatureF: float | None = None
    apparentTemperatureF: float | None = None
    precipitationProbability: float | None = None
    windSpeedMph: float | None = None
    windGustMph: float | None = None
    weatherCode: int | None = None
    weatherMultiplier: float = 1.0
    weatherStatus: str = ""
    weatherVenue: str = ""
    weatherSource: str = ""
    weatherForecastForUtc: str = ""
    startTimeUtc: str = ""
    displayTime: str = ""
    gameStatus: str = ""
    sourceGameStatus: str = ""
    gameTime: str = ""
    gameStartTime: str = ""
    gameDateLocal: str = ""
    timezone: str = ""
    isDoubleheader: bool = False
    isNeutralSite: bool = False
    isCanceled: bool = False
    isDelayed: bool = False
    lastUpdatedUtc: str = ""
    sourceUpdatedUtc: str = ""
    dataAgeSeconds: int | None = None
    dataStale: bool = False
    sourceProvider: str = ""
    piTrustScore: int = 0
    piTrustBand: str = "LIMITED"
    piTrustResearchReady: bool = False
    piTrustFactors: list[dict[str, object]] = []
    piTrustWarnings: list[str] = []
    injuryStatus: str = "unknown"
    lineupStatus: str = "unknown"
    imagePath: str = ""
    confidence: int = 0
    overOdds: float | None = None
    underOdds: float | None = None
    overDecimalOdds: float | None = None
    underDecimalOdds: float | None = None
    overImpliedProbability: float | None = None
    underImpliedProbability: float | None = None


def core_prop_payload(raw: object) -> dict[str, object]:
    if hasattr(raw, "model_dump"):
        raw = raw.model_dump()
    return CorePropResponse.model_validate(raw).model_dump()
