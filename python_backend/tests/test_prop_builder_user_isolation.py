from models.prop_builder_history import PropBuilderHistoryCreate
import services.prop_builder_history_service as history
import services.prop_builder_performance_service as performance


def _build(player: str, result: str) -> PropBuilderHistoryCreate:
    return PropBuilderHistoryCreate(
        build_mode="manual",
        requested_legs=1,
        generated_legs=1,
        legs=[{
            "player": player,
            "sport": "MLB",
            "market": "hits",
            "sportsbook": "PRIZEPICKS",
            "result_status": result,
            "edge": 7,
            "confidence": 62,
        }],
    )


def test_builder_history_and_personal_performance_are_account_scoped(monkeypatch, tmp_path) -> None:
    database = tmp_path / "builder-history.db"
    monkeypatch.setattr(history, "DB_PATH", database)

    history.create_prop_builder_history(_build("Alice", "won"), user_id="user-a")
    history.create_prop_builder_history(_build("Bob", "lost"), user_id="user-b")

    user_a = history.list_prop_builder_history(user_id="user-a")
    user_b = history.list_prop_builder_history(user_id="user-b")
    assert len(user_a) == 1
    assert len(user_b) == 1
    assert user_a[0].legs[0]["player"] == "Alice"
    assert user_b[0].legs[0]["player"] == "Bob"

    result_a = performance.get_prop_builder_performance(user_id="user-a")
    result_b = performance.get_prop_builder_performance(user_id="user-b")
    assert result_a.legs_won == 1 and result_a.legs_lost == 0
    assert result_b.legs_won == 0 and result_b.legs_lost == 1

    assert history.delete_prop_builder_history(user_a[0].id, user_id="user-b") is False
    assert history.delete_prop_builder_history(user_a[0].id, user_id="user-a") is True
