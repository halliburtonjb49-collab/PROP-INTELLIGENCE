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
