from services.player_identity_service import resolve_player_identity


def test_provider_player_id_remains_the_preferred_identity() -> None:
    identity = resolve_player_identity(
        source_provider="odds-api",
        source_player_id="player-123",
        player_name="Example Player",
        identity_scope="MLB",
    )

    assert identity["canonical_player_id"] == "odds-api:player-123"
    assert identity["confidence"] == 0.82


def test_missing_provider_id_uses_stable_scoped_name_identity() -> None:
    identity = resolve_player_identity(
        source_provider="odds-api",
        source_player_id="",
        player_name="José Ramírez",
        identity_scope="baseball_mlb",
    )

    assert (
        identity["canonical_player_id"]
        == "odds-api:name:baseball-mlb:jose-ramirez"
    )
    assert identity["confidence"] == 0.8
    assert identity["matched_by"] == "normalized_provider_name"
