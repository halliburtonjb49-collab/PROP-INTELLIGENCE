from services.opportunity_gate_service import evaluate_opportunity_gate


def test_opportunity_gate_blocks_today_style_weak_point_signal() -> None:
    gate = evaluate_opportunity_gate(
        projection=22.5238,
        line=21.5,
        volatility=9.23,
        probability=.50271,
        sample_size=20,
        data_quality_score=.8,
        injury_status="unknown",
        lineup_status="unknown",
        context_values=(None, None, None, None),
    )
    assert gate.actionable is False
    assert gate.status == "SYSTEM_LEAN"
    assert gate.normalized_edge == .1109
    assert "probability_below_action_threshold" in gate.reasons
    assert "opportunity_context_incomplete" in gate.reasons
    assert gate.grade == "D"
    assert "Pick remains visible" in gate.explanation


def test_opportunity_gate_allows_complete_strong_signal() -> None:
    gate = evaluate_opportunity_gate(
        projection=25,
        line=22.5,
        volatility=4,
        probability=.64,
        sample_size=20,
        data_quality_score=.9,
        injury_status="healthy",
        lineup_status="confirmed",
        context_values=(1.04, .96, 1.02, .99),
    )
    assert gate.actionable is True
    assert gate.status == "MODEL_PICK"
    assert gate.reasons == ()
    assert gate.adjusted_probability == .64
    assert gate.grade == "B"


def test_missing_context_penalizes_but_does_not_erase_exceptional_signal() -> None:
    gate = evaluate_opportunity_gate(
        projection=28,
        line=24.5,
        volatility=5,
        probability=.72,
        sample_size=20,
        data_quality_score=.9,
        injury_status="unknown",
        lineup_status="unknown",
        context_values=(None, None, None, None),
    )
    assert gate.actionable is True
    assert gate.adjusted_probability == .63
    assert "lineup_not_confirmed" in gate.reasons
    assert "opportunity_context_incomplete" in gate.reasons
    assert gate.grade == "B"
