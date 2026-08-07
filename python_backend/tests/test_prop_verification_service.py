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


def test_a_prop_whose_source_cannot_be_named_is_hidden() -> None:
    """A card that prints UNKNOWN is worse than no card.

    It tells the reader the feed does not know what it is showing them.
    """

    result = verify_prop(_prop(sportsbook="UNKNOWN"))

    assert result.status == "quarantined"
    assert result.displayable is False
    assert "source_unverified" in result.reasons

    # An unnamed event is the same failure seen from the other side.
    assert verify_prop(_prop(matchup="")).displayable is False


def test_an_incomplete_prop_is_shown_but_cannot_be_selected() -> None:
    # There is something to look at; there is not enough to act on.
    result = verify_prop(_prop(projection=None))

    assert result.displayable is True
    assert result.selectable is False
    assert result.status == "unverified"


def test_a_prop_with_no_market_at_all_is_quarantined() -> None:
    assert verify_prop(_prop(marketKey="", market="")).displayable is False
    assert verify_prop(_prop(line=None)).displayable is False
    assert verify_prop(_prop(player="")).displayable is False


def test_reasons_read_as_english() -> None:
    described = describe(("market_not_in_sport", "source_unverified"))

    assert described == [
        "Market does not exist in this sport",
        "Prop source could not be verified",
    ]
    # An unmapped reason still says something rather than vanishing.
    assert describe(("brand_new_reason",)) == ["brand new reason"]
