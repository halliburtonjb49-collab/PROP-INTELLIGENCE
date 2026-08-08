from types import SimpleNamespace

import pytest

from services.pi_verdict_service import (
    LEAN,
    PASS,
    PLAY_NOW,
    SHOP,
    WAIT,
    compute_verdict,
    summarize,
    verdict_payload,
)


def _prop(**over):
    base = dict(
        selectable=True,
        projection=7.2,
        line=5.5,
        recommendedSide="OVER",
        uncertaintyAdjustedProbability=0.67,
        probabilityEdge=0.09,
        confidence=67,
        lineupStatus="confirmed",
        injuryStatus="healthy",
        dataStale=False,
        bestOverOdds=1.91,
        overDecimalOdds=1.91,
        bestOverBook="PrizePicks",
        bestUnderOdds=1.91,
        underDecimalOdds=1.91,
        bestUnderBook="PrizePicks",
    )
    base.update(over)
    return SimpleNamespace(**base)


def test_a_settled_edge_is_a_play_now():
    verdict = compute_verdict(_prop())

    assert verdict.decision == PLAY_NOW
    assert verdict.headline == "PLAY OVER NOW"
    assert verdict.is_actionable
    # A shopper needs to know where the edge ends, not just that it exists.
    assert verdict.maximum_playable_line == 6.7


def test_an_unsettled_lineup_makes_it_wait_even_with_a_strong_edge():
    """Acting on unsettled information is the expensive mistake.

    The edge is unchanged; what is missing is the certainty that the player
    is in the game at all.
    """

    verdict = compute_verdict(_prop(lineupStatus="unconfirmed"))

    assert verdict.decision == WAIT
    assert verdict.recheck == "After lineup confirmation"
    # The edge is still described, so the reader knows what they are waiting for.
    assert verdict.maximum_playable_line == 6.7


def test_a_questionable_player_outranks_an_unconfirmed_lineup():
    # Both are unknowns, but the injury is the one that decides whether the
    # prop exists at all.
    verdict = compute_verdict(
        _prop(injuryStatus="questionable", lineupStatus="unconfirmed")
    )

    assert verdict.decision == WAIT
    assert "injury_unresolved" in verdict.reasons
    assert verdict.recheck == "After the injury report is final"


def test_stale_odds_are_a_wait_not_a_play():
    verdict = compute_verdict(_prop(dataStale=True))

    assert verdict.decision == WAIT
    assert "stale_odds" in verdict.reasons


def test_a_better_price_elsewhere_is_a_shop():
    verdict = compute_verdict(
        _prop(overDecimalOdds=1.83, bestOverOdds=1.95, bestOverBook="Underdog")
    )

    assert verdict.decision == SHOP
    assert verdict.better_price_at == "Underdog"
    # Still worth taking -- just not here.
    assert verdict.is_actionable


def test_a_trivial_price_difference_is_not_worth_a_trip():
    verdict = compute_verdict(
        _prop(overDecimalOdds=1.90, bestOverOdds=1.92, bestOverBook="Underdog")
    )

    assert verdict.decision == PLAY_NOW


def test_a_modest_edge_is_a_lean_rather_than_a_play():
    # The fixture is priced at 1.91, so break-even is 52.4% and a full play
    # needs 54.4%. 53.5% is past the price but not far past it.
    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.535))

    assert verdict.decision == LEAN
    assert verdict.is_actionable
    assert "modest" in verdict.reason


def test_a_probability_that_cannot_beat_the_vig_is_a_pass():
    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.52))

    assert verdict.decision == PASS
    assert verdict.is_actionable is False


def test_agreeing_with_the_market_is_a_pass_however_high_the_probability():
    """A high probability the market already prices is not an edge.

    Sixty-seven percent on a side the market also has at sixty-seven is a
    correct opinion worth nothing.
    """

    verdict = compute_verdict(_prop(probabilityEdge=0.005))

    assert verdict.decision == PASS
    assert "no_edge_over_market" in verdict.reasons


def test_a_prop_without_a_projection_passes_and_says_why():
    verdict = compute_verdict(_prop(projection=None))

    assert verdict.decision == PASS
    assert "no_projection" in verdict.reasons
    assert verdict.recheck


def test_an_unverified_prop_never_reaches_a_recommendation():
    verdict = compute_verdict(_prop(selectable=False))

    assert verdict.decision == PASS
    assert verdict.reasons == ("unverified",)


def test_pass_is_decided_before_anything_can_dress_it_up():
    # Unverified, no projection and an unconfirmed lineup at once: the verdict
    # must be the most fundamental failure, not the most recent rule.
    verdict = compute_verdict(
        _prop(selectable=False, projection=None, lineupStatus="unconfirmed")
    )

    assert verdict.decision == PASS
    assert verdict.reasons == ("unverified",)


def test_the_under_side_reads_its_own_fields():
    verdict = compute_verdict(
        _prop(
            recommendedSide="UNDER",
            projection=4.1,
            underDecimalOdds=1.80,
            bestUnderOdds=1.95,
            bestUnderBook="Betr",
        )
    )

    assert verdict.decision == SHOP
    assert verdict.better_price_at == "Betr"
    # An under's playable line sits above the projection, not below it.
    assert verdict.maximum_playable_line == 4.6


def test_the_payload_carries_what_a_card_needs():
    payload = verdict_payload(compute_verdict(_prop()))

    assert payload["decision"] == PLAY_NOW
    assert payload["headline"] == "PLAY OVER NOW"
    assert payload["actionable"] is True
    assert payload["maximumPlayableLine"] == 6.7


def test_a_board_can_be_summarised():
    counts = summarize([
        compute_verdict(_prop()),
        compute_verdict(_prop(lineupStatus="unconfirmed")),
        compute_verdict(_prop(uncertaintyAdjustedProbability=0.50)),
    ])

    assert counts[PLAY_NOW] == 1
    assert counts[WAIT] == 1
    assert counts[PASS] == 1
    assert counts[SHOP] == 0


def test_the_model_is_read_even_when_the_gate_named_no_side():
    """The gate blanks recommendedSide on most of the board.

    Reading only that field made the verdict claim the model had no opinion
    on 1,574 live props that each carried a probability for both sides.
    """

    verdict = compute_verdict(
        _prop(
            recommendedSide="N/A",
            confidence=0,
            uncertaintyAdjustedProbability=None,
            modelOverProbability=0.31,
            modelUnderProbability=0.69,
            projection=0.0,
            line=0.5,
            probabilityEdge=0.09,
        )
    )

    assert verdict.decision != PASS
    assert verdict.side == "UNDER"
    assert "69%" in verdict.reason


def test_the_legacy_gate_does_not_cap_a_prop_that_clears_the_price():
    """Deferring to that gate as well demoted good bets for no reason.

    It tests the pre-calibration probability; this tests the calibrated one
    and the price, which is the stricter pair. Sixty-four props at a median
    15% expected value were being called leans while nine with the same
    credentials were called plays.
    """

    verdict = compute_verdict(
        _prop(
            recommendedSide="N/A",
            uncertaintyAdjustedProbability=None,
            modelOverProbability=0.72,
            modelUnderProbability=0.28,
            probabilityEdge=0.12,
            evPercentage=15.0,
        )
    )

    assert verdict.decision == PLAY_NOW
    assert verdict.side == "OVER"


def test_a_lean_is_a_real_edge_that_falls_short_of_a_play():
    # Between the lean and play bars this price implies, and paying enough.
    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.535, evPercentage=3.0)
    )

    assert verdict.decision == LEAN
    assert verdict.is_actionable


def test_a_released_side_still_earns_a_full_play():
    verdict = compute_verdict(_prop(recommendedSide="OVER"))

    assert verdict.decision == PLAY_NOW


def test_the_stronger_model_side_is_chosen():
    over_favoured = compute_verdict(
        _prop(
            recommendedSide="",
            uncertaintyAdjustedProbability=None,
            modelOverProbability=0.66,
            modelUnderProbability=0.34,
        )
    )
    assert over_favoured.side == "OVER"

    under_favoured = compute_verdict(
        _prop(
            recommendedSide="",
            uncertaintyAdjustedProbability=None,
            modelOverProbability=0.34,
            modelUnderProbability=0.66,
        )
    )
    assert under_favoured.side == "UNDER"


def test_a_confident_model_at_a_bad_price_is_still_a_pass():
    """The price decides, not the probability.

    Measured on a live board, props the model liked at a median 68% carried a
    median expected value of -5.6%: the probability was real and the book had
    already taken it. Playing all of them would lose money slowly while every
    card looked encouraging.
    """

    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.74, evPercentage=-4.0)
    )

    assert verdict.decision == PASS
    assert "negative_expected_value" in verdict.reasons
    assert "already in the line" in verdict.reason


def test_expected_value_is_checked_before_conviction_is_awarded():
    # A play, a shop and a lean must each survive the price test; otherwise the
    # board offers confident-looking bets that lose.
    for probability in (0.85, 0.66, 0.56):
        verdict = compute_verdict(
            _prop(uncertaintyAdjustedProbability=probability, evPercentage=-1.0)
        )
        assert verdict.decision == PASS, probability


def test_a_prop_with_no_price_is_judged_on_the_model_alone():
    # Pick'em sites publish no odds. Absent expected value is not negative
    # expected value, and refusing those would empty the board.
    verdict = compute_verdict(_prop(evPercentage=None))

    assert verdict.decision == PLAY_NOW


def test_a_positive_price_survives_the_gate():
    verdict = compute_verdict(_prop(evPercentage=12.5))

    assert verdict.decision == PLAY_NOW
    assert verdict.is_actionable


def test_the_bar_follows_the_price_not_a_constant():
    """The defect a single global threshold caused.

    Measured on a live board, 641 props cleared 0.58 while only 245 beat the
    number their own book was offering. 56% is a comfortable play against a
    -110 line needing 52.4%, and not a play at all on a pick'em leg needing
    57.8% -- one threshold cannot be right for both.
    """

    sportsbook = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.56, overDecimalOdds=1.91,
              bestOverOdds=1.91, evPercentage=6.0)
    )
    pickem = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.56, overDecimalOdds=1.73,
              bestOverOdds=1.73, evPercentage=6.0)
    )

    assert sportsbook.decision == PLAY_NOW
    assert pickem.decision == PASS


def test_a_pickem_leg_at_the_old_global_bar_is_no_longer_a_play():
    # 0.58 barely clears pick'em break-even of 57.8%, so the old rule called
    # it a play while it carried no margin at all.
    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.58, overDecimalOdds=1.73,
              bestOverOdds=1.73, evPercentage=4.0)
    )

    assert verdict.decision != PLAY_NOW


def test_the_pass_explains_the_price_rather_than_a_threshold():
    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.51, overDecimalOdds=1.91,
              bestOverOdds=1.91)
    )

    assert verdict.decision == PASS
    assert "break even" in verdict.reason
    assert verdict.reasons == ("probability_below_price",)
