from types import SimpleNamespace

from services.context_quality_service import evaluate_context_quality


def _prop(**changes):
    values = dict(
        sport="WNBA", injuryStatus="healthy", lineupStatus="confirmed",
        projectedOpportunity=31.5, restDays=2, travelMiles=400, isHome=True,
        dataAgeSeconds=120, dataStale=False, opponentAllowanceByPosition=18.2,
        paceMultiplier=1.02, directMatchupSampleSize=3,
        defensiveScheme="SWITCH-HEAVY PROXY",
        expectedPrimaryDefender="Defender One",
    )
    values.update(changes)
    return SimpleNamespace(**values)


def test_complete_pregame_context_scores_full_coverage() -> None:
    quality = evaluate_context_quality(_prop())
    assert quality.score == 1
    assert quality.missing == ()


def test_missing_lineup_and_matchup_are_explicit_not_neutral() -> None:
    quality = evaluate_context_quality(_prop(
        lineupStatus="unknown", opponentAllowanceByPosition=None,
        paceMultiplier=None, defensiveScheme="", directMatchupSampleSize=0,
        expectedPrimaryDefender="",
    ))
    assert quality.score < .7
    assert "lineup" in quality.missing
    assert "opponent_allowance" in quality.missing
    assert "defensive_scheme" in quality.missing
    assert "primary_defender" in quality.missing


def test_stale_live_feed_reduces_context_quality() -> None:
    quality = evaluate_context_quality(_prop(dataAgeSeconds=1800, dataStale=True))
    assert "live_feed_fresh" in quality.missing
