from types import SimpleNamespace

import pytest

from services import owner_action_service as actions


def test_prop_control_key_is_stable_but_provider_specific() -> None:
    first = actions.prop_control_key(
        sport=" WNBA ", game_id="GAME-1", player="Ariel  Atkins",
        market="Points", provider="PrizePicks",
    )
    same = actions.prop_control_key(
        sport="wnba", game_id="game-1", player="ariel atkins",
        market="points", provider="prizepicks",
    )
    other_provider = actions.prop_control_key(
        sport="wnba", game_id="game-1", player="ariel atkins",
        market="points", provider="underdog",
    )

    assert first == same
    assert first != other_provider


def test_manual_quarantine_filters_only_matching_prop(monkeypatch) -> None:
    held = SimpleNamespace(
        sport="WNBA", gameId="game-1", eventId="game-1",
        player="Ariel Atkins", market="Points", sportsbook="PrizePicks",
    )
    shown = SimpleNamespace(
        sport="WNBA", gameId="game-1", eventId="game-1",
        player="Ariel Atkins", market="Points", sportsbook="Underdog",
    )
    held_key = actions.prop_control_key_for(held)
    monkeypatch.setattr(actions, "active_prop_quarantine_keys", lambda: frozenset({held_key}))

    assert actions.filter_owner_quarantined_props([held, shown]) == [shown]


def test_prop_action_requires_reason_and_matching_snapshot(monkeypatch) -> None:
    monkeypatch.setattr(actions, "database_is_configured", lambda: True)
    snapshot = {
        "sport": "WNBA", "gameId": "game-1", "player": "Ariel Atkins",
        "market": "Points", "provider": "PrizePicks",
    }
    key = actions.prop_control_key(
        sport="WNBA", game_id="game-1", player="Ariel Atkins",
        market="Points", provider="PrizePicks",
    )

    with pytest.raises(ValueError, match="at least 5"):
        actions.set_prop_quarantine(
            target_key=key, quarantined=True, reason="bad",
            actor_user_id="owner", snapshot=snapshot,
        )
    with pytest.raises(ValueError, match="does not match"):
        actions.set_prop_quarantine(
            target_key="wrong", quarantined=True, reason="Bad provider line",
            actor_user_id="owner", snapshot=snapshot,
        )
