from services.prop_context_service import tier_from_confidence
from services import prop_recommendation_service as recommendations


def test_the_band_that_lost_money_is_no_longer_playable():
    """Measured over 2,859 graded predictions the board showed as Lean.

    That band claimed 57.9%, hit 54.0%, and lost 9.1% flat-staked while the
    card described it as playable with less margin. A tier that costs the
    user money is worse than offering no tier at all.
    """

    assert tier_from_confidence(57) == "Pass"
    assert tier_from_confidence(59) == "Pass"


def test_the_tiers_that_earned_their_labels_keep_them():
    # Premium beat its own claim (69.1% stated, 71.6% actual, +7.6% ROI) and
    # Strong was honest at 61.6% stated against 60.3% actual, so neither
    # threshold moves: nothing a user learned about them changes underneath.
    assert tier_from_confidence(60) == "Strong"
    assert tier_from_confidence(64) == "Strong"
    assert tier_from_confidence(65) == "Premium"
    assert tier_from_confidence(99) == "Premium"


def test_a_passing_side_is_never_dressed_up_by_a_high_confidence():
    assert tier_from_confidence(90, "Pass") == "Pass"


def test_every_caller_shares_one_definition():
    """The thresholds lived in four places and one had no floor at all.

    Behind the uncertainty gate, a prop deemed actionable was labelled Lean
    at any confidence whatsoever -- 50 included. Divergent copies of the
    same rule are what put a losing band on the board.
    """

    assert tier_from_confidence is recommendations.tier_from_confidence
    assert recommendations.ACTIONABLE_CONFIDENCE_FLOOR == 60
    assert recommendations.PREMIUM_CONFIDENCE_FLOOR == 65


def test_a_recommendation_below_the_floor_is_not_offered_as_a_pick():
    built = recommendations.build_prop_recommendation(
        projection=10.05, line=10.0, sport="WNBA", market="Player Points",
    )

    assert built["tier"] == "Pass"
    assert built["pickText"] == "Pass"
