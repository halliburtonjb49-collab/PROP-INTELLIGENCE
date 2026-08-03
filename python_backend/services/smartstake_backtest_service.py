"""Research-only SmartStake MLB prop importer with leakage-safe aggregation."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import duckdb
import requests

from database.postgres import database_is_configured, get_database_pool

HF_TREE_URL = "https://huggingface.co/api/datasets/SmartStake/mlb-player-props/tree/main"
HF_RESOLVE_URL = "https://huggingface.co/datasets/SmartStake/mlb-player-props/resolve/main"


def monthly_files(entries: object, month: str) -> list[dict[str, object]]:
    prefix = f"mon={month}/"
    if not isinstance(entries, list):
        return []
    return sorted(
        [{"path": str(item["path"]), "size": int(item.get("size") or 0)}
         for item in entries if isinstance(item, dict)
         and str(item.get("path") or "").startswith(prefix)
         and str(item.get("path") or "").endswith(".parquet")],
        key=lambda item: str(item["path"]),
    )


def fetch_manifest(month: str) -> list[dict[str, object]]:
    response = requests.get(HF_TREE_URL, params={"recursive": "true", "expand": "false"}, timeout=30)
    response.raise_for_status()
    return monthly_files(response.json(), month)


def manifest_megabytes(files: list[dict[str, object]]) -> float:
    return round(sum(int(item["size"]) for item in files) / 1_000_000, 2)


def download_month(files: list[dict[str, object]], target: Path) -> list[Path]:
    target.mkdir(parents=True, exist_ok=True)
    local: list[Path] = []
    for item in files:
        path = str(item["path"])
        destination = target / Path(path).name
        if not destination.exists() or destination.stat().st_size != int(item["size"]):
            with requests.get(f"{HF_RESOLVE_URL}/{path}", stream=True, timeout=120) as response:
                response.raise_for_status()
                with destination.open("wb") as output:
                    for chunk in response.iter_content(chunk_size=1024 * 1024):
                        if chunk:
                            output.write(chunk)
        local.append(destination)
    return local


def aggregate_month(files: list[Path], output: Path) -> int:
    """Collapse minute quotes to one opening/closing record per book/prop."""
    connection = duckdb.connect()
    quoted = ",".join("'" + str(path).replace("'", "''") + "'" for path in files)
    connection.execute(f"""
        copy (
          with quotes as (
            select * from read_parquet([{quoted}])
            where ts < start_time and side in ('over','under')
          ), collapsed as (
            select game_id,start_time,lower(player) player,lower(market) market,line,book,side,
                   arg_min(odds,ts) opening_odds,arg_max(odds,ts) closing_odds,
                   min(ts) opening_at,max(ts) closing_at,any_value(result) result,
                   any_value(won) won
            from quotes group by all
          )
          select o.game_id,o.start_time,o.player,o.market,o.line,o.book,
                 o.opening_odds opening_over_odds,u.opening_odds opening_under_odds,
                 o.closing_odds closing_over_odds,u.closing_odds closing_under_odds,
                 least(o.opening_at,u.opening_at) opening_at,
                 greatest(o.closing_at,u.closing_at) closing_at,
                 coalesce(o.result,u.result) result,o.won over_won
          from collapsed o join collapsed u using(game_id,start_time,player,market,line,book)
          where o.side='over' and u.side='under'
        ) to '{str(output).replace("'", "''")}' (format parquet, compression zstd)
    """)
    count = connection.execute(f"select count(*) from read_parquet('{str(output).replace("'", "''")}')").fetchone()[0]
    connection.close()
    return int(count)


def persist_aggregate(path: Path, *, batch_size: int = 2000) -> int:
    if not database_is_configured():
        raise RuntimeError("DATABASE_URL is required to persist SmartStake research data")
    source = duckdb.connect()
    result = source.execute(f"select * from read_parquet('{str(path).replace("'", "''")}')")
    persisted = 0
    with get_database_pool().connection() as connection, connection.cursor() as cursor:
        while True:
            batch = result.fetchmany(batch_size)
            if not batch:
                break
            cursor.executemany(
                """insert into smartstake_mlb_prop_closes
                (game_id,start_time,player,market,line,book,opening_over_odds,
                 opening_under_odds,closing_over_odds,closing_under_odds,
                 opening_at,closing_at,result,over_won)
                values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                on conflict (game_id,player,market,line,book) do update set
                  opening_over_odds=excluded.opening_over_odds,
                  opening_under_odds=excluded.opening_under_odds,
                  closing_over_odds=excluded.closing_over_odds,
                  closing_under_odds=excluded.closing_under_odds,
                  opening_at=excluded.opening_at,closing_at=excluded.closing_at,
                  result=excluded.result,over_won=excluded.over_won,imported_at=now()""",
                batch,
            )
            connection.commit()
            persisted += len(batch)
    source.close()
    return persisted
