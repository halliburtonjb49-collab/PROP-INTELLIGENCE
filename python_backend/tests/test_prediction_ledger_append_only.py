from pathlib import Path

from scripts.apply_supabase_migrations import MIGRATIONS


ROOT = Path(__file__).resolve().parents[2]


def test_graded_prediction_history_is_append_only_and_registered() -> None:
    filename = "supabase_prediction_ledger_append_only.sql"
    assert filename in MIGRATIONS
    sql = (ROOT / filename).read_text(encoding="utf-8").lower()
    assert "before update or delete on public.prediction_snapshots" in sql
    assert "old.hit is not null" in sql
    assert "graded prediction history is append-only" in sql
    assert "new.hit is distinct from old.hit" in sql
    assert "new.actual_value is distinct from old.actual_value" in sql
    assert "revoke all on function" in sql