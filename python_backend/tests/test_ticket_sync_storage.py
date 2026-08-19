from datetime import datetime, timedelta, timezone

from models.slip import LegResultUpdate, SlipCreate, SlipLeg
from services import game_status_service, slip_service


def _ticket(prop_id: str, event_id: str) -> SlipCreate:
    return SlipCreate(
        legs=[
            SlipLeg(
                prop_id=prop_id,
                event_id=event_id,
                player="Sync Player",
                sport="NFL",
                matchup="AWAY @ HOME",
                sportsbook="DraftKings",
                market="Receiving Yards",
                line=40.5,
                side="OVER",
                game_start_time=(
                    datetime.now(timezone.utc) + timedelta(hours=4)
                ).isoformat(),
            )
        ],
        stake=10,
    )


def test_game_status_sync_uses_shared_ticket_storage(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "tickets.db")
    slip_service.create_slip(_ticket("status-prop", "status-event"), "owner")
    monkeypatch.setattr(
        game_status_service,
        "fetch_scores",
        lambda *_args, **_kwargs: [
            {"id": "status-event", "completed": True, "scores": [{"score": 1}]}
        ],
    )

    result = game_status_service.refresh_saved_slip_game_statuses()
    saved = slip_service.get_slips(user_id="owner")[0]

    assert result["slips_updated"] == 1
    assert saved.legs[0].game_completed is True
    assert saved.legs[0].game_status == "completed"


def test_result_sync_remains_owner_scoped(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "tickets.db")
    slip_service.create_slip(_ticket("shared", "event-1"), "owner-1")
    slip_service.create_slip(_ticket("shared", "event-1"), "owner-2")

    changed = slip_service.update_slip_results(
        [LegResultUpdate(prop_id="shared", result_value=50)],
        user_id="owner-1",
    )

    assert changed == 1
    assert slip_service.get_slips(user_id="owner-1")[0].status == "won"
    assert slip_service.get_slips(user_id="owner-2")[0].status == "active"
