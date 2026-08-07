from types import SimpleNamespace

from services.prop_verification_service import (
    describe,
    display_matchup,
    display_team_name,
    is_placeholder,
    market_belongs_to_sport,
    verify_prop,
)


def _prop(**over):
    base = dict(
        player="Drew Romo",
        sport="MLB",
        marketKey="batter_hits",
        market="Batter Hits",
        line=0.5,
        sportsbook="PrizePicks",
        projection=0.62,
        matchup="Cleveland Guardians @ Chicago White Sox",
    )
    base.update(over)
    return SimpleNamespace(**base)


def test_a_feed_identifier_becomes_a_readable_team_name() -> None:
    assert display_team_name("CLEVELAND_GUARDIANS_MLB") == "Cleveland Guardians"
    assert display_team_name("GOLDEN_STATE_VALKYRIES_WNBA") == "Golden State Valkyries"


def test_the_league_suffix_is_dropped_not_capitalised() -> None:
    # The card already says which sport it is; repeating it inside the team
    # name is how MLB ends up printed twice on one line.
    assert "Mlb" not in display_team_name("DETROIT_TIGERS_MLB")
    assert display_team_name("DETROIT_TIGERS_MLB") == "Detroit Tigers"


def test_a_name_that_is_already_readable_survives_untouched() -> None:
    assert display_team_name("Seattle Mariners") == "Seattle Mariners"
    assert display_team_name("Chicago White Sox") == "Chicago White Sox"


def test_a_placeholder_yields_nothing_rather_than_tidied_noise() -> None:
    # The caller must be able to tell "no name" from "a name".
    for value in ("UNKNOWN", "", "  ", "N/A", "TBD", None):
        assert display_team_name(value) == ""
        assert is_placeholder(value)


def test_a_matchup_is_rebuilt_from_both_identifiers() -> None:
    assert display_matchup(
        "CLEVELAND_GUARDIANS_MLB @ CHICAGO_WHITE_SOX_MLB"
    ) == "Cleveland Guardians @ Chicago White Sox"


def test_teams_are_preferred_over_a_raw_matchup_string() -> None:
    assert display_matchup(
        "garbage", home="SEATTLE_MARINERS_MLB", away="DETROIT_TIGERS_MLB"
    ) == "Detroit Tigers @ Seattle Mariners"


def test_baseball_has_no_points_market() -> None:
    # The defect from the board: a basketball stat mapped onto a baseball event.
    assert market_belongs_to_sport("MLB", "player_points") is False
    assert market_belongs_to_sport("MLB", "batter_hits") is True
    assert market_belongs_to_sport("NBA", "player_points") is True


def test_an_unconfigured_sport_is_not_judged() -> None:
    # A new sport must not be rejected for being new.
    assert market_belongs_to_sport("PGA", "player_birdies") is True
    assert market_belongs_to_sport("", "anything") is True


def test_a_sound_prop_is_verified_and_selectable() -> None:
    result = verify_prop(_prop())

    assert result.status == "verified"
    assert result.displayable and result.selectable
    assert result.reasons == ()


def test_the_card_from_the_board_is_quarantined() -> None:
    # Exactly the record behind the screenshot: a baseball points market, an
    # unnamed source and no projection.
    result = verify_prop(
        _prop(
            marketKey="player_points",
            market="Player Points",
            sportsbook="UNKNOWN",
            projection=None,
        )
    )

    assert result.status == "quarantined"
    assert result.displayable is False
    assert "market_not_in_sport" in result.reasons
    assert "source_unverified" in result.reasons
    assert "projection_missing" in result.reasons


def test_every_fault_is_reported_not_just_the_first() -> None:
    # An unknown source and a missing projection are different problems, and
    # fixing one does not fix the other.
    result = verify_prop(_prop(sportsbook="UNKNOWN", projection=None))
    assert set(result.reasons) == {"source_unverified", "projection_missing"}


def test_a_prop_whose_source_cannot_be_named_is_shown_and_explained() -> None:
    """UNKNOWN in the raw feed is a metadata gap, not proof the bet is fake.

    The prop still corresponds to something a sportsbook is actually
    offering, so it stays on the board with the gap named rather than
    disappearing -- the same treatment a missing projection already gets.
    """

    result = verify_prop(_prop(sportsbook="UNKNOWN"))

    assert result.status == "unverified"
    assert result.displayable is True
    assert result.selectable is True
    assert "source_unverified" in result.reasons

    # An unnamed event is the same failure seen from the other side.
    unnamed_event = verify_prop(_prop(matchup=""))
    assert unnamed_event.displayable is True
    assert unnamed_event.selectable is True


def test_a_missing_projection_is_reported_but_does_not_block() -> None:
    """Our coverage gap is not the prop's fault.

    The line is real and the market is real. Refusing the pick would mistake
    a gap in what we model for a defect in what they are looking at.
    """

    result = verify_prop(_prop(projection=None))

    assert result.displayable is True
    assert result.selectable is True
    # The gap is still recorded so the card can say so.
    assert "projection_missing" in result.reasons


def test_a_broken_core_object_is_withheld_entirely() -> None:
    """Faults with nothing coherent underneath the caveat.

    A market that does not exist in its sport cannot be graded against
    anything real. A prop with no line has no number for an Over/Under to
    mean anything against. A prop with no player has nothing to attach a
    pick to. None of these can be shown with a warning, because there is no
    real bet underneath the warning -- so all three are hidden rather than
    explained.
    """

    assert verify_prop(_prop(marketKey="", market="")).displayable is False
    assert verify_prop(
        _prop(marketKey="player_points", market="Player Points")
    ).displayable is False
    assert verify_prop(_prop(line=None)).displayable is False
    assert verify_prop(_prop(player="")).displayable is False


def test_a_missing_source_or_event_name_is_shown_and_explained() -> None:
    # These are holes in our metadata about the surroundings of a real prop,
    # not about whether the prop itself exists -- the player, market and line
    # are all still intact, so they are treated like a missing projection.
    missing_source = verify_prop(_prop(sportsbook="UNKNOWN"))
    assert missing_source.displayable is True
    assert missing_source.selectable is True
    assert "source_unverified" in missing_source.reasons

    missing_event = verify_prop(_prop(matchup=""))
    assert missing_event.displayable is True
    assert missing_event.selectable is True
    assert "event_unnamed" in missing_event.reasons


def test_reasons_read_as_english() -> None:
    described = describe(("market_not_in_sport", "source_unverified"))

    assert described == [
        "Market does not exist in this sport",
        "Prop source could not be verified",
    ]
    # An unmapped reason still says something rather than vanishing.
    assert describe(("brand_new_reason",)) == ["brand new reason"]
