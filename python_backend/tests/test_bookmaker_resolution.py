from config import _resolve_bookmakers


def test_a_key_the_provider_does_not_have_is_dropped():
    """Requesting a nonexistent bookmaker is silent and costs a book.

    The provider omits unknown keys without comment, so `sleeper` was
    requested for months and could never have returned anything.
    """

    resolved, dropped, _ = _resolve_bookmakers(
        "prizepicks,underdog,sleeper,fanduel"
    )

    assert "sleeper" not in resolved
    assert dropped == ["sleeper"]
    assert "prizepicks" in resolved


def test_a_configuration_that_has_fallen_behind_is_brought_forward():
    # A value set in a deployment dashboard outranks the repository and stays
    # behind when the repository moves on.
    resolved, _, restored = _resolve_bookmakers(
        "prizepicks,underdog,draftkings,sleeper,fanduel,betr_us_dfs"
    )

    assert "pick6" in resolved
    assert restored == ["pick6"]


def test_a_current_configuration_is_left_alone():
    resolved, dropped, restored = _resolve_bookmakers(
        "prizepicks,underdog,draftkings,pick6,fanduel,betr_us_dfs"
    )

    assert dropped == []
    assert restored == []
    assert resolved[0] == "prizepicks"


def test_operator_choices_beyond_the_dfs_set_survive():
    # Restoring the DFS sites must not strip books somebody added on purpose.
    resolved, _, _ = _resolve_bookmakers("draftkings,fanduel,espnbet")

    assert "espnbet" in resolved
    assert "draftkings" in resolved


def test_whitespace_and_case_are_normalised():
    resolved, _, _ = _resolve_bookmakers("  PrizePicks , UNDERDOG ,, ")

    assert "prizepicks" in resolved
    assert "underdog" in resolved
    assert "" not in resolved


def test_an_empty_configuration_still_yields_the_dfs_sites():
    resolved, _, restored = _resolve_bookmakers("")

    # Never request nothing: an empty list would return the whole market.
    assert set(resolved) == {"prizepicks", "underdog", "betr_us_dfs", "pick6"}
    assert set(restored) == set(resolved)
