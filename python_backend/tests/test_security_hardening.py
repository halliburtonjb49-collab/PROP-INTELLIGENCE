from pathlib import Path

import main


ROOT = Path(__file__).resolve().parents[2]


def _request(path: str, method: str = "GET", query: str = ""):
    scope = {
        "type": "http",
        "method": method,
        "path": path,
        "query_string": query.encode(),
        "headers": [],
        "client": ("127.0.0.1", 1234),
        "server": ("test", 80),
        "scheme": "http",
    }
    return main.Request(scope)


def test_sensitive_route_rate_limit_scopes_are_specific() -> None:
    assert main._rate_limit_scope(_request("/api/props")) == (
        "prop-feed",
        60,
    )
    assert main._rate_limit_scope(
        _request("/api/props", query="search=judge")
    ) == ("player-search", 30)
    assert main._rate_limit_scope(
        _request("/api/slips", method="POST")
    ) == ("ticket-create", 10)
    assert main._rate_limit_scope(
        _request("/api/intelligence/game-script", method="POST")
    ) == ("pro-calculation", 30)
    assert main._rate_limit_scope(
        _request("/api/realtime/connect")
    ) == ("chat-realtime", 30)


def test_security_migration_enables_public_rls_and_revokes_proprietary_data() -> None:
    sql = (ROOT / "supabase_security_hardening.sql").read_text(
        encoding="utf-8"
    ).lower()
    assert "where schemaname = 'public'" in sql
    assert "enable row level security" in sql
    assert "revoke all on public.prediction_snapshots" in sql
    assert "revoke all on public.prop_market_intelligence" in sql
    assert "create table if not exists public.security_events" in sql
    assert "revoke all on public.security_events from anon, authenticated" in sql


def test_function_hardening_removes_anonymous_definer_execution() -> None:
    sql = (ROOT / "supabase_function_execution_hardening.sql").read_text(
        encoding="utf-8"
    ).lower()
    assert "alter function public.validate_prop_chat_link(text)" in sql
    assert "set search_path = pg_catalog" in sql
    assert (
        "revoke execute on function %s from public, anon, authenticated"
        in sql
    )
    assert "grant execute on function %s to service_role" in sql
    assert "public.acknowledge_prop_chat_notice(bigint)" in sql
    assert "public.assign_user_role(text,text)" in sql
    assert "public.start_prop_chat_direct_conversation(uuid)" in sql
    assert "public.enforce_prop_chat_message_v4()" not in sql

def test_feedback_table_is_migrated_as_api_only_data() -> None:
    from scripts.apply_supabase_migrations import MIGRATIONS

    filename = "supabase_user_feedback_messages.sql"
    assert filename in MIGRATIONS
    sql = (ROOT / filename).read_text(encoding="utf-8").lower()
    assert "enable row level security" in sql
    assert "force row level security" in sql
    assert (
        "revoke all on public.user_feedback_messages from anon, authenticated"
        in sql
    )


def test_member_signup_table_is_migrated_as_api_only_data() -> None:
    from scripts.apply_supabase_migrations import MIGRATIONS

    filename = "supabase_member_signup_notifications.sql"
    assert filename in MIGRATIONS
    sql = (ROOT / filename).read_text(encoding="utf-8").lower()
    assert "enable row level security" in sql
    assert "force row level security" in sql
    assert (
        "revoke all on public.member_signup_notifications "
        "from anon, authenticated"
        in sql
    )


def test_owner_operations_tables_are_migrated_as_api_only_data() -> None:
    from scripts.apply_supabase_migrations import MIGRATIONS

    filename = "supabase_owner_operations_security.sql"
    assert filename in MIGRATIONS
    sql = (ROOT / filename).read_text(encoding="utf-8").lower()
    for table in (
        "owner_prop_quarantines",
        "owner_alert_acknowledgements",
        "owner_operations_audit",
    ):
        assert f"alter table if exists public.{table} enable row level security" in sql
        assert f"alter table if exists public.{table} force row level security" in sql
        assert f"revoke all on table public.{table} from anon, authenticated" in sql

def test_member_identity_grants_are_owner_only_and_server_derived() -> None:
    from scripts.apply_supabase_migrations import MIGRATIONS

    filename = "supabase_member_identity_roles.sql"
    assert filename in MIGRATIONS
    sql = (ROOT / filename).read_text(encoding="utf-8").lower()
    assert "public.effective_account_role() <> 'owner'" in sql
    assert "revoke update (" in sql
    assert "assigned_member_role" in sql
    assert "author_badge_number" in sql
    assert "new.author_badge_number :=" in sql
    assert "prevent_member_access_self_assignment" in sql
    assert "revoke all on function public.assign_member_identity_role" in sql

    hardening_filename = "supabase_member_identity_execution_hardening.sql"
    assert hardening_filename in MIGRATIONS
    hardening = (ROOT / hardening_filename).read_text(encoding="utf-8").lower()
    assert "from public, anon, authenticated" in hardening
    assert "prevent_member_access_self_assignment()" in hardening
    assert "to authenticated" in hardening
