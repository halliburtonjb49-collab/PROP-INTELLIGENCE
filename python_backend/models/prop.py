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
    # True when the projection is minutes times a per-minute rate. The
    # workload multipliers must then be left out of the context adjustment,
    # because the minutes they describe are already inside the projection.
    projectionUsesMinutes: bool = False
    projectedMinutes: float | None = None
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
    recommendationExplainability: dict[str, object] = Field(default_factory=dict)
    # Whether this prop is coherent enough to show, and complete enough to
    # act on. A prop naming a market its sport does not have, or a source it
    # cannot identify, is not displayed at all.
    # One conclusion in place of six signals the reader would otherwise have
    # to assemble: play now, shop, wait, lean or pass.
    verdict: dict[str, object] = Field(default_factory=dict)
    verificationStatus: str = "verified"
    verificationReasons: list[str] = Field(default_factory=list)
    selectable: bool = True
    dataQualityScore: float = Field(default=0.0, ge=0, le=1)
    dataQualityReasons: list[str] = Field(default_factory=list)
    piTrustScore: int = Field(default=0, ge=0, le=100)
    piTrustBand: str = 'LIMITED'
    piTrustResearchReady: bool = False
    piTrustFactors: list[dict[str, object]] = Field(default_factory=list)
    piTrustWarnings: list[str] = Field(default_factory=list)
    researchCapsule: dict[str, object] = Field(default_factory=dict)
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
    # Normalized sport-specific participation evidence and readiness.
    pregameAvailability: dict[str, object] = Field(default_factory=dict)
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
    # Model probability minus the de-vigged market probability for the
    # recommended side. Unlike `edge`, which is a difference in stat units and
    # therefore incomparable across markets, this is the quantity worth
    # ranking on: it is denominated in probability and already net of margin.
    probabilityEdge: float | None = None
    # Both sides of the modeled distribution, so a card can show the full
    # picture rather than only the recommended side's probability.
    modelOverProbability: float | None = None
    modelUnderProbability: float | None = None
    # Central interval of the modeled outcome, from the same distribution that
    # produced the probabilities above.
    projectionIntervalLow: float | None = None
    projectionIntervalHigh: float | None = None
    projectionIntervalCoverage: float = 0.80
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
    pitcherKPercent: float | None = None
    lineupKPercent: float | None = None
    pitchesPerStart: float | None = None
    pitchesPerBatter: float | None = None
    pitcherCsw: float | None = None
    lineupCswAgainst: float | None = None
    temperatureF: float | None = None
    umpireKBoost: float | None = None
    parkKFactor: float | None = None
    strikeoutModelMethod: str = ""
    strikeoutSkillSource: str = ""
    strikeoutProjectedBattersFaced: int | None = None
    strikeoutUsedFallbackPitcherRate: bool = False
    strikeoutUsedFallbackLineupRate: bool = False
    strikeoutUsedFallbackTbf: bool = False
    strikeoutUsedMarketBlend: bool = False
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
    wnbaResearchScore: int = Field(default=0, ge=0, le=100)
    wnbaResearchBand: str = "NOT_APPLICABLE"
    wnbaResearchReady: bool = False
    wnbaMinutesCertainty: int = Field(default=0, ge=0, le=100)
    wnbaRoleClarity: int = Field(default=0, ge=0, le=100)
    wnbaResearchFactors: list[dict[str, object]] = Field(default_factory=list)
    wnbaResearchWarnings: list[str] = Field(default_factory=list)
    officiatingContext: str = ""
    officiatingAdjustment: float | None = None
    sentimentLabel: str = ""
    sentimentScore: float | None = None
    sentimentSampleSize: int = 0
