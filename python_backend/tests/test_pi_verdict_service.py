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
        sportsbook="PrizePicks",
        recommendedSide="OVER",
        recommendationAvailable=True,
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
    assert verdict.headline == "PLAY OVER"
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


def test_wnba_minutes_or_role_uncertainty_makes_a_settled_edge_wait():
    verdict = compute_verdict(_prop(
        sport="WNBA",
        wnbaResearchReady=False,
        wnbaResearchWarnings=["Recent minutes are too volatile."],
    ))

    assert verdict.decision == WAIT
    assert "wnba_minutes_or_role_uncertain" in verdict.reasons
    assert verdict.recheck == (
        "After minutes, role and lineup evidence are confirmed"
    )

def test_sport_specific_availability_waits_even_when_legacy_lineup_is_confirmed():
    verdict = compute_verdict(_prop(
        sport="MLB",
        pregameAvailability={
            "status": "WAIT",
            "warnings": ["Official batting order is not confirmed."],
            "recheck": "After the official batting order is confirmed",
        },
    ))
    assert verdict.decision == WAIT
    assert "pregame_availability_unsettled" in verdict.reasons
    assert verdict.recheck == "After the official batting order is confirmed"


def test_ready_sport_specific_assessment_replaces_generic_lineup_gate():
    verdict = compute_verdict(_prop(
        sport="NBA",
        lineupStatus="unknown",
        pregameAvailability={"status": "READY", "warnings": []},
    ))
    assert verdict.decision == PLAY_NOW

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


def test_the_current_best_book_is_not_told_to_shop_itself():
    verdict = compute_verdict(
        _prop(
            sportsbook="Underdog",
            overDecimalOdds=1.83,
            bestOverOdds=1.95,
            bestOverBook="Underdog",
        )
    )

    assert verdict.decision == PLAY_NOW
    assert verdict.better_price_at == ""


def test_an_impossible_playable_threshold_is_omitted():
    verdict = compute_verdict(
        _prop(
            projection=0.51,
            line=0.5,
            lineupStatus="unconfirmed",
        )
    )

    assert verdict.decision == WAIT
    assert verdict.maximum_playable_line is None


def test_fallback_projection_copy_does_not_claim_to_be_a_model_pick():
    verdict = compute_verdict(_prop(recommendationAvailable=False))

    assert "available projection" in verdict.reason.lower()
    assert "The model" not in verdict.reason


def test_a_modest_edge_is_a_lean_rather_than_a_play():
    # The fixture is priced at 1.91, so break-even is 52.4%, a lean needs
    # 54.4% and a full play needs 57.4%. 55.5% is past the price by enough
    # to watch and not by enough to stake: measured on 79,208 graded
    # results, that band returns +2.0% with an interval spanning zero.
    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.555))

    assert verdict.decision == LEAN
    assert verdict.is_actionable
    assert "modest" in verdict.reason


def test_a_probability_below_the_directional_threshold_is_a_pass():
    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.52))

    assert verdict.decision == PASS
    assert verdict.is_actionable is False


def test_a_qualified_direction_below_the_price_is_a_lean_with_a_warning():
    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.56,
                                    overDecimalOdds=1.73,
                                    bestOverOdds=1.73))

    assert verdict.decision == LEAN
    assert verdict.is_actionable
    assert verdict.reasons == ("directional_lean_price_not_cleared",)
    assert "price needs" in verdict.reason
    assert "posted price is not backed" in verdict.reason


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
    assert payload["headline"] == "PLAY OVER"
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
        _prop(uncertaintyAdjustedProbability=0.555, evPercentage=3.0)
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


def test_a_confident_model_at_a_bad_price_is_shown_with_the_warning():
    """The price is a warning the prop carries, not a gate that hides it.

    Measured on a live board, props the model liked at a median 68% carried a
    median expected value of -5.6%: the probability was real and the book had
    already taken it. That is worth saying on the card. It is not grounds for
    removing the prop, because a bet that never appears cannot be judged by
    the person whose money it is -- and making it a gate emptied every
    actionable section on the board.
    """

    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.74, evPercentage=-4.0)
    )

    assert verdict.decision == LEAN
    assert verdict.is_actionable
    assert "priced_out" in verdict.reasons
    # The reader is told exactly what is wrong with it.
    assert "-4.0%" in verdict.reason
    assert "Your call" in verdict.reason
    assert "in the line already" in verdict.reason


def test_a_bad_price_demotes_conviction_rather_than_erasing_it():
    # However much the model likes it, a price that has taken the edge is a
    # lean and not a play -- but it stays on the board either way.
    for probability in (0.85, 0.66, 0.56):
        verdict = compute_verdict(
            _prop(uncertaintyAdjustedProbability=probability, evPercentage=-1.0)
        )
        assert verdict.decision != PLAY_NOW, probability
        assert verdict.is_actionable, probability


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

    # 57.8% clears a -110 line (52.4% break-even) by the measured five point
    # play margin, and on a pick'em leg needing exactly 57.8% it does not
    # clear the price at all: one threshold cannot serve both.
    sportsbook = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.578, overDecimalOdds=1.91,
              bestOverOdds=1.91, evPercentage=6.0)
    )
    pickem = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.578, overDecimalOdds=1.73,
              bestOverOdds=1.73, evPercentage=6.0)
    )

    assert sportsbook.decision == PLAY_NOW
    assert pickem.decision == LEAN
    assert "directional_lean_price_not_cleared" in pickem.reasons


def test_a_pickem_leg_at_the_old_global_bar_is_no_longer_a_play():
    # 0.58 barely clears pick'em break-even of 57.8%, so the old rule called
    # it a play while it carried no margin at all.
    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.58, overDecimalOdds=1.73,
              bestOverOdds=1.73, evPercentage=4.0)
    )

    assert verdict.decision != PLAY_NOW


def test_a_strong_direction_at_an_expensive_price_populates_lean_not_play_now():
    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.85, overDecimalOdds=1.11,
              bestOverOdds=1.11, evPercentage=-5.0)
    )

    assert verdict.decision == LEAN
    assert verdict.is_actionable
    assert verdict.headline == "LEAN OVER"
    assert "85%" in verdict.reason
    assert "90%" in verdict.reason
    assert "posted price is not backed" in verdict.reason


def test_the_pass_explains_the_price_rather_than_a_threshold():
    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.51, overDecimalOdds=1.91,
              bestOverOdds=1.91)
    )

    assert verdict.decision == PASS
    assert "break even" in verdict.reason
    assert verdict.reasons == ("probability_below_price",)


def test_a_pass_never_tells_someone_they_cannot_have_it():
    """Tone is part of the product.

    A pass is our opinion, not a restriction. Wording that reads as a refusal
    costs a customer the same way hiding the prop would, and the prop stays
    fully selectable either way.
    """

    passes = [
        compute_verdict(_prop(projection=None)),
        compute_verdict(_prop(uncertaintyAdjustedProbability=0.50)),
        compute_verdict(
            _prop(uncertaintyAdjustedProbability=0.62, probabilityEdge=0.001)
        ),
    ]

    for verdict in passes:
        assert verdict.decision == PASS
        # Says what we think, never what the reader is allowed to do.
        assert "cannot be" not in verdict.reason
        assert "not worth" not in verdict.reason
        assert "nothing to take" not in verdict.reason


def test_a_pass_speaks_for_us_rather_than_about_the_bet():
    # "We do not see an edge" and "this is a bad bet" are different claims,
    # and only the first one is ours to make.
    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.62, probabilityEdge=0.001)
    )

    assert "we" in verdict.reason.lower()


def test_an_unmodelled_market_is_not_reported_as_a_warning():
    # Our coverage gap is not evidence against the prop.
    verdict = compute_verdict(_prop(projection=None))

    assert "no opinion" in verdict.reason
    assert "not a warning against it" in verdict.reason


def test_every_pass_hands_the_choice_back():
    """Plenty of people bet on a read rather than a number.

    They are customers with a different method, not mistakes to correct, and
    a card that reads as a scolding loses them. Every pass states our view
    and then says plainly that the decision is theirs.
    """

    passes = [
        compute_verdict(_prop(selectable=False)),
        compute_verdict(_prop(projection=None)),
        compute_verdict(
            _prop(recommendedSide="", uncertaintyAdjustedProbability=None,
                  modelOverProbability=None, modelUnderProbability=None)
        ),
        compute_verdict(_prop(uncertaintyAdjustedProbability=0.50)),
        compute_verdict(
            _prop(uncertaintyAdjustedProbability=0.62, probabilityEdge=0.001)
        ),
    ]

    for verdict in passes:
        assert verdict.decision == PASS
        reason = verdict.reason.lower()
        defers = any(
            phrase in reason
            for phrase in ("your call", "yours to take", "your read")
        )
        assert defers, verdict.reason


def test_the_play_bar_sits_where_the_money_actually_starts():
    """The margin is measured, not assumed.

    Grouped by the model's edge over the price actually paid, 79,208 graded
    results split cleanly: at or below break-even the return is -8.4% to
    -10.8%; nought to five points over returns +2.0% with an interval that
    spans zero; five to ten points returns +8.4%; ten to fifteen returns
    +26.0%. Two points over break-even -- the old bar -- sat inside the band
    whose return cannot be told apart from zero, which is how the default
    board came to recommend bets that lost money.
    """

    from services.pi_verdict_service import (
        LEAN_MARGIN_OVER_BREAK_EVEN,
        PLAY_MARGIN_OVER_BREAK_EVEN,
    )

    assert PLAY_MARGIN_OVER_BREAK_EVEN == 0.05
    # The lean bar stays at break-even plus a half point. In finer bands the
    # cliff is at break-even itself: 0.005-0.01 returns +8.9% and 0.01-0.02
    # returns +5.0%, so lifting this would have dropped 1,210 results worth
    # +6.4% [+1.2, +11.5] to tidy a threshold.
    assert LEAN_MARGIN_OVER_BREAK_EVEN == 0.005


def test_an_edge_at_or_below_the_price_is_not_playable():
    # The measured cliff. At or under break-even the return is -8.8%
    # [-9.4, -8.1] across 74,469 results; above it the board turns positive.
    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.523))

    assert verdict.decision == PASS
    assert verdict.is_actionable is False


def test_a_thin_but_real_edge_stays_on_the_playable_board():
    """Inventory the tidier threshold would have thrown away.

    Half a point to two points over the price returns +6.4% [+1.2, +11.5]
    across 1,210 graded results. It is not a full play, and it is not
    something to hide either.
    """

    verdict = compute_verdict(_prop(uncertaintyAdjustedProbability=0.535))

    assert verdict.is_actionable
    assert verdict.decision != PLAY_NOW


def test_a_generous_price_keeps_a_lower_probability_playable():
    """Inventory is protected by gating on edge rather than confidence.

    A flat confidence floor would drop this prop; it is a play because the
    price is generous, which is exactly the distinction that separates the
    +26% band from the -10% one.
    """

    verdict = compute_verdict(
        _prop(uncertaintyAdjustedProbability=0.58, overDecimalOdds=2.40,
              bestOverOdds=2.40, evPercentage=20.0)
    )

    assert verdict.decision == PLAY_NOW
    assert verdict.is_actionable
