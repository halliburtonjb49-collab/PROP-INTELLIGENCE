from types import SimpleNamespace

from services.wnba_research_service import assess_wnba_research


def _prop(**overrides):
    values = dict(
        sport="WNBA",
        marketKey="player_points",
        market="Points",
        category="POINTS",
        projectedOpportunity=32.0,
        opportunityUnit="MINUTES",
        opportunitySampleSize=15,
        opportunityConfidence=.82,
        opportunityVolatility=2.4,
        roleStatus="HIGH_MINUTES",
        roleChange="STABLE",
        lineupStatus="CONFIRMED",
        injuryStatus="HEALTHY",
        paceMultiplier=1.02,
        opponentDefenseMultiplier=.98,
        matchupMultiplier=1.01,
        wowyMultiplier=1.04,
        usageMultiplier=1.06,
        marketBookCount=3,
        dataStale=False,
        restDays=1,
    )
    values.update(overrides)
    return SimpleNamespace(**values)


def test_strong_wnba_evidence_requires_minutes_and_role() -> None:
    result = assess_wnba_research(_prop())
    assert result.research_ready is True
    assert result.score >= 80
    assert result.minutes_certainty >= 60
    assert result.role_clarity >= 60


def test_unconfirmed_rotation_forces_wait_even_with_market_context() -> None:
    result = assess_wnba_research(_prop(
        projectedOpportunity=None,
        opportunitySampleSize=0,
        opportunityConfidence=0,
        opportunityVolatility=None,
        roleStatus="UNKNOWN",
        roleChange="UNKNOWN",
        lineupStatus="PROJECTED",
        injuryStatus="QUESTIONABLE",
    ))
    assert result.research_ready is False
    assert result.band in {"WAIT", "LIMITED"}
    assert any("minutes" in warning.lower() for warning in result.warnings)