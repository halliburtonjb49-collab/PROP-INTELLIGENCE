from services.prop_service import canonical_market_group_key


def _row(
    game_id: str,
    commence_time: str = "2026-08-12T00:00:00Z",
) -> dict[str, object]:
    return {
        "sport": "basketball_wnba",
        "game_id": game_id,
        "home_team": "LOS_ANGELES_SPARKS_WNBA",
        "away_team": "Golden State Valkyries",
        "commence_time": commence_time,
        "player_name": "Ariel Atkins",
        "prop_type": "player_points",
    }


def test_provider_specific_event_ids_reconcile_to_same_market() -> None:
    assert canonical_market_group_key(
        _row("odds-123")
    ) == canonical_market_group_key(_row("sgo:456"))


def test_true_separate_tip_times_do_not_merge() -> None:
    assert canonical_market_group_key(
        _row("one")
    ) != canonical_market_group_key(
        _row("two", "2026-08-12T02:00:00Z")
    )