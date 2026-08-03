from services.prediction_automation_service import (
    _paper_trade_eligible,
    _snapshot_side,
)


def test_all_projected_props_receive_an_auditable_side() -> None:
    assert _snapshot_side("N/A", 22.4, 21.5) == "OVER"
    assert _snapshot_side("", 18.1, 20.5) == "UNDER"
    assert _snapshot_side("", None, 20.5) == ""
    assert _snapshot_side("", 20.5, 20.5) == ""


def test_only_a_and_b_grades_enter_forward_paper_trade() -> None:
    assert _paper_trade_eligible("A")
    assert _paper_trade_eligible("b")
    assert not _paper_trade_eligible("C")
    assert not _paper_trade_eligible("D")
