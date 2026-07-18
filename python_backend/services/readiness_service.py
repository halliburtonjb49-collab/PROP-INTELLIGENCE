"""Production data-readiness audit for Intelligence features."""
from database.postgres import database_is_configured, get_database_pool

REQUIRED_TABLES = (
    "historical_basketball_game_logs", "historical_mlb_pitches",
    "player_stretch_embeddings", "prediction_snapshots",
    "officiating_tendency_profiles", "team_matchup_profiles",
    "prop_engagement_events", "compound_prop_alerts", "alert_deliveries",
    "team_schedule", "player_fatigue_features", "user_profiles",
)

MINIMUM_COUNTS = {
    "historical_basketball_game_logs": 500,
    "historical_mlb_pitches": 1000,
    "player_stretch_embeddings": 100,
    "officiating_tendency_profiles": 5,
    "team_matchup_profiles": 5,
}


def assess_readiness(table_counts: dict[str, int | None], graded_predictions: int = 0) -> dict[str, object]:
    missing = [table for table, count in table_counts.items() if count is None]
    insufficient = [{"table": table, "count": table_counts.get(table, 0) or 0, "minimum": minimum}
                    for table, minimum in MINIMUM_COUNTS.items()
                    if table_counts.get(table) is not None and (table_counts.get(table) or 0) < minimum]
    blockers = [f"Missing table: {table}" for table in missing]
    warnings = [f"{row['table']} has {row['count']} rows; target at least {row['minimum']}"
                for row in insufficient]
    if graded_predictions < 100:
        warnings.append(f"Only {graded_predictions} graded predictions; probability calibration needs at least 100")
    status = "blocked" if blockers else "warming" if warnings else "ready"
    return {"status": status, "blockers": blockers, "warnings": warnings,
            "tableCounts": table_counts, "gradedPredictions": graded_predictions,
            "safeToMarketAsCalibrated": status == "ready"}


def production_readiness() -> dict[str, object]:
    if not database_is_configured():
        return {"status": "not_configured", "blockers": ["DATABASE_URL is not configured"],
                "warnings": [], "safeToMarketAsCalibrated": False}
    counts: dict[str, int | None] = {}
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        for table in REQUIRED_TABLES:
            cursor.execute("select to_regclass(%s)", (f"public.{table}",))
            if cursor.fetchone()[0] is None:
                counts[table] = None
                continue
            cursor.execute(f'select count(*) from public."{table}"')
            counts[table] = int(cursor.fetchone()[0])
        graded = 0
        if counts.get("prediction_snapshots") is not None:
            cursor.execute("""select count(*) from prediction_snapshots where graded_at is not null
                and created_at < event_time - interval '5 minutes'""")
            graded = int(cursor.fetchone()[0])
        cursor.execute("""select exists(select 1 from information_schema.columns
            where table_schema='public' and table_name='user_profiles' and column_name='subscription_tier')""")
        if not cursor.fetchone()[0]:
            counts["user_profiles.subscription_tier"] = None
    return assess_readiness(counts, graded)
