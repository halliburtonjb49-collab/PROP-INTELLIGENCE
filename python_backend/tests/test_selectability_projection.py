from types import SimpleNamespace

from services.selectability_projection_service import (
    PICKEM_BREAK_EVEN,
    REQUIRED_MARGIN,
    STANDARD_BREAK_EVEN,
    break_even_for,
    project,
)


def _prop(**over):
    base = dict(
        sportsbook="PrizePicks",
        uncertaintyAdjustedProbability=0.60,
        projection=7.2,
        line=6.5,
        overDecimalOdds=None,
        underDecimalOdds=None,
        modelOverProbability=None,
        modelUnderProbability=None,
    )
    base.update(over)
    return SimpleNamespace(**base)


def test_posted_odds_beat_any_assumption() -> None:
    # A book that tells us what it pays must never be second-guessed.
    break_even, source = break_even_for(_prop(overDecimalOdds=2.0))

    assert break_even == 0.5
    assert source == "offeredOdds"


def test_a_pickem_leg_is_priced_off_the_slip() -> None:
    break_even, source = break_even_for(_prop(sportsbook="Underdog"))

    assert break_even == PICKEM_BREAK_EVEN
    assert source == "pickemStructure"


def test_an_unpriced_sportsbook_falls_back_to_the_standard_line() -> None:
    break_even, source = break_even_for(_prop(sportsbook="DraftKings"))

    assert break_even == STANDARD_BREAK_EVEN
    assert source == "assumedStandard"


def test_the_under_side_is_priced_off_the_under() -> None:
    # Pricing a bet off the wrong side's odds is how a losing number gets
    # called a winner.
    prop = _prop(
        modelOverProbability=0.30,
        modelUnderProbability=0.70,
        overDecimalOdds=5.0,
        underDecimalOdds=1.4,
    )

    assert break_even_for(prop)[0] == 1 / 1.4


def test_a_sportsbook_prop_below_the_global_bar_can_still_be_profitable() -> None:
    """The whole point of pricing the bar.

    0.55 clears a -110 book's 52.4% with room, and the single global 0.58
    threshold rejects it anyway.
    """

    result = project([
        _prop(sportsbook="DraftKings", uncertaintyAdjustedProbability=0.55)
    ])

    assert result["currentRule"]["pickable"] == 0
    assert result["priceAwareRule"]["pickable"] == 1
    assert result["gainedByBook"] == {"DRAFTKINGS": 1}


def test_a_pickem_prop_at_the_global_bar_carries_no_margin() -> None:
    # 0.58 barely clears pick'em's 57.8% break-even, so the global rule calls
    # it a play while the priced rule refuses it.
    result = project([
        _prop(sportsbook="PrizePicks", uncertaintyAdjustedProbability=0.58)
    ])

    assert result["currentRule"]["pickable"] == 1
    assert result["priceAwareRule"]["pickable"] == 0
    assert result["lostByBook"] == {"PRIZEPICKS": 1}


def test_a_prop_with_no_model_probability_is_counted_but_not_judged() -> None:
    result = project([
        _prop(uncertaintyAdjustedProbability=None, fairProbability=None)
    ])

    assert result["props"] == 1
    assert result["withModelProbability"] == 0
    assert result["priceAwareRule"]["pickable"] == 0


def test_the_margin_is_required_beyond_break_even() -> None:
    # Landing exactly on break-even is a coin flip that has paid the vig.
    exactly = _prop(
        sportsbook="DraftKings", uncertaintyAdjustedProbability=STANDARD_BREAK_EVEN
    )
    clear = _prop(
        sportsbook="DraftKings",
        uncertaintyAdjustedProbability=STANDARD_BREAK_EVEN + REQUIRED_MARGIN,
    )

    assert project([exactly])["priceAwareRule"]["pickable"] == 0
    assert project([clear])["priceAwareRule"]["pickable"] == 1


def test_an_empty_board_reports_zero_rather_than_failing() -> None:
    result = project([])

    assert result["props"] == 0
    assert result["currentRule"]["pickable"] == 0
    assert result["priceAwareRule"]["pickable"] == 0
