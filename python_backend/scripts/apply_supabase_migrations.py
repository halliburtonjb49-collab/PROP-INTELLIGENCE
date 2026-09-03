"""Apply the repository's Supabase migrations in a tracked, deterministic order."""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path
import socket
from urllib.parse import parse_qsl, quote, urlencode, urlparse, urlunparse

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / "python_backend" / ".env")

MIGRATIONS = (
    "supabase_user_tables_and_rls.sql",
    "supabase_owner_role_manager.sql",
    "supabase_change_request_workflow.sql",
    "supabase_advisor_change_request_access.sql",
    "supabase_add_is_premium_column.sql",
    "supabase_subscription_tiers.sql",
    "supabase_billing_webhook_integrity.sql",
    "supabase_founding_pro_claims.sql",
    "supabase_historical_data.sql",
    "supabase_multi_sport_history.sql",
    "supabase_intelligence_features.sql",
    "supabase_operational_pipeline.sql",
    "supabase_pipeline_monitoring.sql",
    "supabase_sportsbook_line_history.sql",
    "supabase_prop_chat.sql",
    "supabase_prop_chat_v2.sql",
    "supabase_prop_chat_v3.sql",
    "supabase_prop_chat_v4.sql",
    "supabase_prop_chat_v5.sql",
    "supabase_prop_chat_v6.sql",
    "supabase_prop_chat_v7.sql",
    "supabase_prop_chat_owner_announcements.sql",
    "supabase_core_pro_chat_enforcement.sql",
    "supabase_slip_postgres_storage.sql",
    "supabase_slip_request_idempotency.sql",
    "supabase_owner_user_id.sql",
    "supabase_all_owner_accounts.sql",
    "supabase_member_identity_roles.sql",
    "supabase_member_identity_execution_hardening.sql",
    "supabase_performance_indexes.sql",
    "supabase_security_hardening.sql",
    "supabase_function_execution_hardening.sql",
    "supabase_model_research_pipeline.sql",
    "supabase_pregame_context_observations.sql",
    "supabase_pregame_context_lookup_index.sql",
    "supabase_pregame_context_sport_lookup_index.sql",
    "supabase_defender_matchup_history.sql",
    "supabase_historical_odds_backfill.sql",
    "supabase_smartstake_backtest.sql",
    "supabase_mlb_player_game_features.sql",
    "supabase_prop_catalog_snapshots.sql",
    "supabase_owner_runtime_controls.sql",
    "supabase_basketball_advanced_box_score.sql",
    "supabase_prediction_ledger_append_only.sql",
    "supabase_user_feedback_messages.sql",
    "supabase_member_signup_notifications.sql",
    "supabase_owner_operations_security.sql",
    "supabase_provider_availability_snapshots.sql",
    "supabase_single_owner_enforcement.sql",
    "supabase_advisor_role_assignment.sql",
    "supabase_owner_account_rebinding.sql",
    "supabase_prop_learning_system.sql",
    "supabase_pi_learning_ledger.sql",
    "supabase_identity_media_registry.sql",
    "supabase_engagement_action_expansion.sql",
    "supabase_production_observability.sql",
    "supabase_prop_chat_owner_announcements_hardening.sql",
    "supabase_prop_chat_owner_announcements_hardening_v2.sql",
    "supabase_prop_chat_owner_message_length.sql",
)


def main() -> int:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        print("DATABASE_URL is required; no database changes were made.", file=sys.stderr)
        return 2

    sslmode = os.getenv("DATABASE_SSLMODE", "require").strip() or "require"
    if sslmode.lower() not in {"require", "verify-ca", "verify-full"}:
        print(
            "DATABASE_SSLMODE must enforce TLS for migrations.",
            file=sys.stderr,
        )
        return 2
    parsed = urlparse(database_url)
    urls: list[str] = [database_url]
    direct_env_url = os.getenv("SUPABASE_DIRECT_DATABASE_URL", "").strip()
    if direct_env_url:
        urls.append(direct_env_url)
    if (
        parsed.hostname
        and ".pooler.supabase.com" in parsed.hostname.lower()
        and parsed.username
    ):
        project_ref = parsed.username.split(".", 1)[1] if "." in parsed.username else ""
        if project_ref:
            direct_host = f"db.{project_ref}.supabase.co"
            try:
                socket.gethostbyname(direct_host)
            except Exception:
                pass
            else:
                password = quote((parsed.password or ""), safe="")
                direct_db_url = (
                    f"{parsed.scheme}://{parsed.username}:{password}@{direct_host}:{parsed.port}{parsed.path}"
                )
                urls.append(direct_db_url)

    raw_manual_hostaddrs = [
        addr.strip()
        for addr in os.getenv("DATABASE_HOSTADDRS", "").split(",")
        if addr.strip()
    ]
    manual_hostaddrs = []
    for addr in raw_manual_hostaddrs:
        try:
            socket.inet_pton(socket.AF_INET, addr)
        except OSError:
            print(f"Ignoring invalid IPv4 hostaddr: {addr}", file=sys.stderr)
            continue
        manual_hostaddrs.append(addr)

    normalized_urls: list[str] = []
    for candidate_url in urls:
        if candidate_url in normalized_urls:
            continue
        normalized_urls.append(candidate_url)
        parsed_candidate = urlparse(candidate_url)
        base_query = dict(parse_qsl(parsed_candidate.query, keep_blank_values=True))
        for ipv4 in manual_hostaddrs:
            query = dict(base_query)
            query["hostaddr"] = ipv4
            hostaddr_candidate = parsed_candidate._replace(query=urlencode(query, doseq=True))
            hostaddr_url = urlunparse(hostaddr_candidate)
            if hostaddr_url not in normalized_urls:
                normalized_urls.append(hostaddr_url)
        try:
            infos = socket.getaddrinfo(
                parsed_candidate.hostname,
                parsed_candidate.port,
                socket.AF_INET,
                socket.SOCK_STREAM,
            )
        except Exception:
            infos = []
        for entry in infos:
            ipv4 = entry[4][0]
            query = dict(parse_qsl(parsed_candidate.query, keep_blank_values=True))
            query["hostaddr"] = ipv4
            hostaddr_candidate = parsed_candidate._replace(
                query=urlencode(query, doseq=True)
            )
            hostaddr_url = urlunparse(hostaddr_candidate)
            if hostaddr_url not in normalized_urls:
                normalized_urls.append(hostaddr_url)
    urls = normalized_urls

    for candidate_url in urls:
        try:
            with psycopg.connect(candidate_url, sslmode=sslmode, connect_timeout=20) as connection:
                connection.execute(
                    """create table if not exists public.prop_intelligence_schema_migrations (
                        filename text primary key,
                        checksum text not null,
                        applied_at timestamptz not null default now()
                    )"""
                )
                connection.commit()

                for filename in MIGRATIONS:
                    path = ROOT / filename
                    sql = path.read_text(encoding="utf-8")
                    checksum = hashlib.sha256(sql.encode("utf-8")).hexdigest()
                    existing = connection.execute(
                        "select checksum from public.prop_intelligence_schema_migrations where filename = %s",
                        (filename,),
                    ).fetchone()
                    if existing:
                        if existing[0] != checksum:
                            raise RuntimeError(
                                f"Previously applied migration changed: {filename}. "
                                "Create a new migration instead of editing deployed SQL."
                            )
                        print(f"skip {filename}")
                        continue

                    print(f"apply {filename}")
                    try:
                        connection.execute(sql)
                        connection.execute(
                            "insert into public.prop_intelligence_schema_migrations(filename, checksum) values (%s, %s)",
                            (filename, checksum),
                        )
                        connection.commit()
                    except Exception:
                        connection.rollback()
                        raise

                rls_disabled = connection.execute(
                    """
                    select c.relname
                    from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public'
                      and c.relkind in ('r', 'p')
                      and not c.relrowsecurity
                    order by c.relname
                    """
                ).fetchall()
                if rls_disabled:
                    names = ", ".join(str(row[0]) for row in rls_disabled)
                    raise RuntimeError(
                        f"Public tables without RLS detected: {names}"
                    )

                exposed_proprietary = connection.execute(
                    """
                    select table_name, grantee
                    from information_schema.role_table_grants
                    where table_schema = 'public'
                      and grantee in ('anon', 'authenticated')
                      and table_name in (
                        'billing_webhook_events',
                        'sportsbook_line_snapshots',
                        'prop_market_intelligence',
                        'prediction_snapshots',
                        'player_stretch_embeddings',
                        'player_fatigue_features',
                        'officiating_tendency_profiles',
                        'team_matchup_profiles',
                        'security_events',
                        'matchup_feature_snapshots',
                        'paper_trade_entries',
                        'paper_trade_results',
                        'model_challenger_evaluations',
                        'pregame_context_observations',
                        'basketball_defender_matchups',
                        'historical_odds_backfill_jobs',
                        'smartstake_mlb_prop_closes'
                      )
                    """
                ).fetchall()
                if exposed_proprietary:
                    raise RuntimeError(
                        "Browser grants remain on proprietary tables: "
                        f"{exposed_proprietary}"
                    )

                anonymous_definers = connection.execute(
                    """
                    select p.oid::regprocedure::text
                    from pg_proc p
                    join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public'
                      and p.prosecdef
                      and has_function_privilege(
                        'anon',
                        p.oid,
                        'EXECUTE'
                      )
                    order by 1
                    """
                ).fetchall()
                if anonymous_definers:
                    raise RuntimeError(
                        "Anonymous execution remains on SECURITY DEFINER functions: "
                        f"{anonymous_definers}"
                    )

            print("Supabase migrations are current.")
            return 0
        except Exception:
            if candidate_url != urls[-1]:
                print(
                    "Migration connection with configured URL failed. Retrying direct host candidate...",
                    file=sys.stderr,
                )
                continue
            if candidate_url != database_url and direct_env_url:
                print(
                    "Migration failed with both DATABASE_URL and SUPABASE_DIRECT_DATABASE_URL.",
                    file=sys.stderr,
                )
            raise


if __name__ == "__main__":
    raise SystemExit(main())
