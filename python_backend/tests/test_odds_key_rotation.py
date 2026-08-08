from services import odds_service


class _Response:
    def __init__(self, status_code: int, text: str = "") -> None:
        self.status_code = status_code
        self.text = text


def _reset(keys: list[str]) -> None:
    odds_service._ODDS_API_KEYS[:] = keys
    odds_service._active_key_index = 0
    odds_service._dead_keys.clear()


def test_a_deactivated_key_is_recognised_as_dead_not_exhausted() -> None:
    """Both arrive as 401 and were treated identically.

    A quota resets; a cancelled key does not, and rotating onto one takes the
    board down where having no backup at all would only have cost the
    overage.
    """

    deactivated = _Response(401, '{"error_code":"DEACTIVATED_KEY"}')
    exhausted = _Response(401, '{"message":"quota reached"}')

    assert odds_service._is_deactivated(deactivated) is True
    assert odds_service._is_deactivated(exhausted) is False


def test_rotation_skips_a_key_known_to_be_dead() -> None:
    _reset(["primary", "dead", "third"])
    odds_service._mark_key_dead(1)

    assert odds_service._advance_to_next_key() is True
    # Lands on the third key, never on the dead second one.
    assert odds_service._current_api_key() == "third"
    _reset([])


def test_a_dead_last_key_leaves_rotation_where_it_was() -> None:
    # Better to stay on an exhausted key than to move onto a refused one:
    # the first fails until reset, the second fails forever.
    _reset(["primary", "dead"])
    odds_service._mark_key_dead(1)

    assert odds_service._advance_to_next_key() is False
    assert odds_service._current_api_key() == "primary"
    _reset([])


def test_an_ordinary_exhaustion_still_rotates() -> None:
    _reset(["primary", "backup"])

    assert odds_service._advance_to_next_key() is True
    assert odds_service._current_api_key() == "backup"
    _reset([])


def test_the_snapshot_reports_how_many_keys_are_dead() -> None:
    _reset(["primary", "dead"])
    odds_service._mark_key_dead(1)
    snapshot = odds_service.active_key_snapshot()

    assert snapshot["configuredKeyCount"] == 2
    assert snapshot.get("deadKeyCount") == 1
    _reset([])
