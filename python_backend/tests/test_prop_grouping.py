from types import SimpleNamespace

from services.prop_group_service import assign_prop_groups, prop_group_key


def _prop(**overrides):
    base = {
        "id": "p1",
        "sport": "WNBA",
        "eventId": "evt-1",
        "playerId": "player-9",
        "player": "Janelle Salaun",
        "marketKey": "player_points",
        "market": "Points",
        "line": 11.0,
        "sportsbook": "PrizePicks",
        "propGroupId": "",
        "propGroupBookCount": 0,
    }
    base.update(overrides)
    return SimpleNamespace(**base)


def test_the_same_offer_at_different_books_shares_one_group():
    """13,053 distinct props arrive as 28,194 cards, 2.16 to one.

    The worst of them appear fourteen times, once per book carrying it.
    """

    props = [
        _prop(id="a", sportsbook="PrizePicks"),
        _prop(id="b", sportsbook="DraftKings"),
        _prop(id="c", sportsbook="FanDuel"),
    ]

    assign_prop_groups(props)

    assert len({prop.propGroupId for prop in props}) == 1
    assert all(prop.propGroupBookCount == 3 for prop in props)


def test_a_different_line_is_still_the_same_offer():
    """Books disagree about the number, and which has the best line is the
    question being asked. Splitting on it would leave the near-duplicate
    cards this exists to collapse."""

    props = [_prop(id="a", line=25.5), _prop(id="b", line=26.5)]

    assign_prop_groups(props)

    assert props[0].propGroupId == props[1].propGroupId


def test_the_same_player_in_a_different_event_never_merges():
    props = [_prop(id="a", eventId="evt-1"), _prop(id="b", eventId="evt-2")]

    assign_prop_groups(props)

    assert props[0].propGroupId != props[1].propGroupId


def test_different_markets_never_merge():
    props = [
        _prop(id="a", marketKey="player_points"),
        _prop(id="b", marketKey="player_rebounds"),
    ]

    assign_prop_groups(props)

    assert props[0].propGroupId != props[1].propGroupId


def test_players_with_similar_names_are_kept_apart_by_id():
    props = [
        _prop(id="a", playerId="player-9", player="J. Salaun"),
        _prop(id="b", playerId="player-12", player="J Salaun"),
    ]

    assign_prop_groups(props)

    assert props[0].propGroupId != props[1].propGroupId


def test_a_name_carries_the_group_when_no_id_exists():
    props = [
        _prop(id="a", playerId="", sportsbook="PrizePicks"),
        _prop(id="b", playerId="", sportsbook="FanDuel"),
    ]

    assign_prop_groups(props)

    assert props[0].propGroupId == props[1].propGroupId
    assert props[0].propGroupId.startswith("solo:") is False


def test_an_unidentifiable_prop_stands_alone_rather_than_guessing():
    """Merging on missing identity would put one player's prop on another's
    card. Standing alone is the failure that costs nothing."""

    props = [
        _prop(id="a", playerId="", player="", eventId=""),
        _prop(id="b", playerId="", player="", eventId=""),
    ]

    assign_prop_groups(props)

    assert props[0].propGroupId != props[1].propGroupId
    assert props[0].propGroupId == "solo:a"


def test_the_identity_is_stable_across_refreshes():
    first = prop_group_key(
        sport="WNBA", event_id="evt-1", player_id="p9",
        player="Janelle Salaun", market_key="player_points", market="Points",
    )
    second = prop_group_key(
        sport="wnba", event_id="EVT-1", player_id="P9",
        player="janelle salaun", market_key="Player_Points", market="points",
    )

    assert first == second
