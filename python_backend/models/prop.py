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
    pick: str
    edge: float = Field(ge=0)
    recommendedSide: str = "N/A"
    confidence: int = 0
    recommendationEdge: float = 0.0
    tier: str = "No Pick"
    pickText: str = "No Pick"
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
    edgeSigned: float = 0.0
    fatigueIndex: float | None = None
    fatigueMultiplier: float | None = None
    travelMiles: float | None = None
    timezoneChangeHours: float | None = None
    matchupContext: str = ""
    matchupMultiplier: float | None = None
    officiatingContext: str = ""
    officiatingAdjustment: float | None = None
    sentimentLabel: str = ""
    sentimentScore: float | None = None
    sentimentSampleSize: int = 0
