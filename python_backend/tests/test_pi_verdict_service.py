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
    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.56))

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


def test_a_side_the_gate_declined_is_never_a_full_play():
    """The gate checks things this does not -- separation, expected value.

    Overruling it would put two different answers on the same board.
    """

    verdict = compute_verdict(
        _prop(
            recommendedSide="N/A",
            uncertaintyAdjustedProbability=None,
            modelOverProbability=0.72,
            modelUnderProbability=0.28,
            probabilityEdge=0.12,
        )
    )

    assert verdict.decision == LEAN
    assert verdict.side == "OVER"
    assert "release checks" in verdict.reason


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
