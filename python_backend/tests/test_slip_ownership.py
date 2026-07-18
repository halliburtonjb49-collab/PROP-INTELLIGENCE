from models.slip import ClosingLineUpdate, LegResultUpdate, SlipCreate, SlipLeg
from services import slip_service
from datetime import datetime, timezone
from types import SimpleNamespace


def _request(player: str) -> SlipCreate:
    return SlipCreate(legs=[SlipLeg(prop_id=player, player=player, sport="NBA", matchup="A @ B",
        sportsbook="Book", market="points", line=20.5, side="OVER")], stake=10)


def test_saved_slips_are_isolated_by_user(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "slips.db")
    first = slip_service.create_slip(_request("First"), user_id="user-1")
    second = slip_service.create_slip(_request("Second"), user_id="user-2")
    assert [slip.id for slip in slip_service.get_slips(user_id="user-1")] == [first.id]
    assert [slip.id for slip in slip_service.get_slips(user_id="user-2")] == [second.id]
    assert slip_service.update_slip_status(first.id, "won", user_id="user-2") is False
    assert slip_service.update_slip_status(first.id, "won", user_id="user-1") is True


def test_entry_line_is_snapshotted_and_clv_is_user_isolated(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "slips.db")
    slip = slip_service.create_slip(_request("clv-prop"), user_id="user-1")
    assert slip.legs[0].entry_line == 20.5
    assert slip_service.update_slip_closing_lines(
        slip.id, [ClosingLineUpdate(prop_id="clv-prop", closing_line=22.5)], "user-2"
    ) is None
    result = slip_service.update_slip_closing_lines(
        slip.id, [ClosingLineUpdate(prop_id="clv-prop", closing_line=22.5)], "user-1"
    )
    assert result is not None and result["beatCloseRate"] == 100
    saved = slip_service.get_slips(user_id="user-1")[0]
    assert saved.legs[0].line_clv == 2
    assert saved.legs[0].beat_closing_line is True


def test_closing_capture_requires_exact_near_start_match(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "slips.db")
    now = datetime(2026, 7, 17, 20, 0, tzinfo=timezone.utc)
    request = SlipCreate(legs=[SlipLeg(
        prop_id="exact", event_id="event-1", player="Exact Player", sport="NBA",
        matchup="A @ B", sportsbook="Book", market="points", line=20.5, side="OVER",
    )], stake=10)
    slip_service.create_slip(request, user_id="user-1")
    matching = SimpleNamespace(
        eventId="event-1", player="Exact Player", marketKey="points", market="points",
        sportsbook="Book", startTimeUtc="2026-07-17T20:10:00Z",
        currentLine=22.5, line=22.5, overOdds=-110, underOdds=-110,
    )
    result = slip_service.capture_closing_lines_from_props([matching], now=now)
    assert result["matchedLegs"] == 1
    saved = slip_service.get_slips(user_id="user-1")[0]
    assert saved.legs[0].closing_line == 22.5
    assert saved.legs[0].beat_closing_line is True


def test_closing_capture_skips_ambiguous_or_early_rows(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "slips.db")
    slip_service.create_slip(_request("Player"), user_id="user-1")
    now = datetime(2026, 7, 17, 20, 0, tzinfo=timezone.utc)
    missing_event = SimpleNamespace(
        eventId="", player="Player", marketKey="points", market="points",
        sportsbook="Book", startTimeUtc="2026-07-17T20:10:00Z",
        currentLine=22.5, line=22.5, overOdds=-110, underOdds=-110,
    )
    assert slip_service.capture_closing_lines_from_props([missing_event], now=now)["matchedLegs"] == 0


def test_result_updates_are_isolated_by_user(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(slip_service, "DATABASE_PATH", tmp_path / "slips.db")
    slip_service.create_slip(_request("shared-prop"), user_id="user-1")
    slip_service.create_slip(_request("shared-prop"), user_id="user-2")
    changed = slip_service.update_slip_results(
        [LegResultUpdate(prop_id="shared-prop", result_value=25)], user_id="user-1"
    )
    assert changed == 1
    assert slip_service.get_slips(user_id="user-1")[0].status == "won"
    assert slip_service.get_slips(user_id="user-2")[0].status == "active"
