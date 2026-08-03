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
    projectionPreMarket: float | None = None
    projectionMarketWeight: float = 0.0
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
    recommendationExplanation: str = ""
    dataQualityScore: float = Field(default=0.0, ge=0, le=1)
    dataQualityReasons: list[str] = Field(default_factory=list)
    opportunityScore: float = Field(default=0.0, ge=0, le=1)
    opportunityStatus: str = "SYSTEM_LEAN"
    opportunityReasons: list[str] = Field(default_factory=list)
    uncertaintyAdjustedEdge: float | None = None
    pickGrade: str = "C"
    pickGradeExplanation: str = "Awaiting sufficient projection evidence."
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
    sourceProvider: str = "odds-api"
    injuryStatus: str = "unknown"
    lineupStatus: str = "unknown"
    imagePath: str = ""
    overOdds: float | None = None
    underOdds: float | None = None
    marketOriginLine: float | None = None
    lineDiscrepancy: float | None = None
    marketBookCount: int = 0
    bestOverOdds: float | None = None
    bestUnderOdds: float | None = None
    bestOverBook: str = ""
    bestUnderBook: str = ""
    publicBetPercentage: float | None = None
    moneyPercentage: float | None = None
    volumeSource: str = ""
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
    selectionMethod: str = "calibrated-ensemble-v1"
    selectionReason: str = ""
    uncertaintyAdjustedProbability: float | None = None
    recommendedStakeFraction: float = Field(default=0.0, ge=0, le=1)
    edgeSigned: float = 0.0
    fatigueIndex: float | None = None
    fatigueMultiplier: float | None = None
    restDays: float | None = None
    paceMultiplier: float | None = None
    opponentDefenseMultiplier: float | None = None
    usageMultiplier: float | None = None
    projectedOpportunity: float | None = None
    opportunityUnit: str = ""
    opportunitySampleSize: int = 0
    opportunityVolatility: float | None = None
    opportunityMultiplier: float | None = None
    opportunityConfidence: float | None = None
    opportunitySource: str = ""
    roleStatus: str = "UNKNOWN"
    roleChange: str = "UNKNOWN"
    wowyMultiplier: float | None = None
    gameScriptMultiplier: float | None = None
    homeAwayMultiplier: float | None = None
    travelMiles: float | None = None
    timezoneChangeHours: float | None = None
    matchupContext: str = ""
    matchupMultiplier: float | None = None
    opponentAllowanceByPosition: float | None = None
    opponentAllowanceLeagueAverage: float | None = None
    opponentPosition: str = ""
    defensiveScheme: str = ""
    directMatchupAverage: float | None = None
    directMatchupSampleSize: int = 0
    expectedPrimaryDefender: str = ""
    expectedPrimaryDefenderConfidence: float | None = None
    expectedPrimaryDefenderSampleSize: float | None = None
    mlbProjectedLineupMatchup: dict[str, object] | None = None
    isHome: bool | None = None
    contextDataQualityScore: float = Field(default=0.0, ge=0, le=1)
    contextPresentFields: list[str] = Field(default_factory=list)
    contextMissingFields: list[str] = Field(default_factory=list)
    officiatingContext: str = ""
    officiatingAdjustment: float | None = None
    sentimentLabel: str = ""
    sentimentScore: float | None = None
    sentimentSampleSize: int = 0
