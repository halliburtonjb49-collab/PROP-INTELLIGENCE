from pydantic import BaseModel, Field


class PropResponse(BaseModel):
    id: str
    gameId: str = ""
    eventId: str = ""
    apiSportsGameId: str = ""
    playerId: str = ""
    sourcePlayerId: str = ""
    canonicalPlayerId: str = ""
    playerIdentityConfidence: float = 0.0
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
    projection: float | None = None
    projectionSource: str = ""
    projectionModelVersion: str = ""
    projectionSampleSize: int = 0
    projectionVolatility: float | None = None
    projectionCalibrated: bool = False
    projectionLabel: str = ""
    historicalHitRate: int | None = None
    pick: str
    edge: float = Field(ge=0)
    recommendedSide: str = "N/A"
    confidence: int = 0
    recommendationEdge: float = 0.0
    tier: str = "No Pick"
    pickText: str = "No Pick"
    recommendationAvailable: bool = False
    recommendationUnavailableReason: str = ""
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
    sourceProvider: str = "odds-api"
    injuryStatus: str = "unknown"
    lineupStatus: str = "unknown"
    imagePath: str = ""
    overOdds: float | None = None
    underOdds: float | None = None
    overDecimalOdds: float | None = None
    underDecimalOdds: float | None = None
    overImpliedProbability: float | None = None
    underImpliedProbability: float | None = None
    noVigOverProbability: float | None = None
    noVigUnderProbability: float | None = None
    evPercentage: float | None = None
    fairProbability: float | None = None
    isPositiveEv: bool = False
    modelProbability: float | None = None
    marketProbability: float | None = None
    pushProbability: float = 0.0
    lossProbability: float | None = None
    fairDecimalOdds: float | None = None
    probabilityMethod: str = ""
    probabilityMarketWeight: float = 0.0
    probabilityUncertainty: float | None = None
    probabilityCalibrationAdjustment: float = 0.0
    probabilityCalibrationSampleSize: int = 0
    edgeSigned: float = 0.0
    fatigueIndex: float | None = None
    fatigueMultiplier: float | None = None
    restDays: float | None = None
    paceMultiplier: float | None = None
    opponentDefenseMultiplier: float | None = None
    usageMultiplier: float | None = None
    homeAwayMultiplier: float | None = None
    travelMiles: float | None = None
    timezoneChangeHours: float | None = None
    matchupContext: str = ""
    matchupMultiplier: float | None = None
    officiatingContext: str = ""
    officiatingAdjustment: float | None = None
    sentimentLabel: str = ""
    sentimentScore: float | None = None
    sentimentSampleSize: int = 0
