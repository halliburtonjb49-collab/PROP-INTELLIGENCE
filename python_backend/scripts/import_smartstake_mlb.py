"""Download and aggregate one SmartStake month for leakage-safe research."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.smartstake_backtest_service import (  # noqa: E402
    aggregate_month, download_month, fetch_manifest, manifest_megabytes,
    persist_aggregate,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--month", required=True, help="YYYY-MM")
    parser.add_argument("--max-download-mb", required=True, type=float)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--persist", action="store_true", help="Upsert aggregates into the research database")
    args = parser.parse_args()
    manifest = fetch_manifest(args.month)
    size = manifest_megabytes(manifest)
    plan = {"month": args.month, "files": len(manifest), "downloadMB": size,
            "license": "CC-BY-4.0", "evaluationOnlyResults": True}
    print(json.dumps(plan, indent=2))
    if not manifest:
        return 2
    if size > args.max_download_mb:
        print("Download cap exceeded; no files were downloaded.", file=sys.stderr)
        return 2
    if not args.execute:
        print("Dry run only. Add --execute to download and aggregate the month.")
        return 0
    output = args.output or Path.cwd() / f"smartstake-{args.month}-closing.parquet"
    with tempfile.TemporaryDirectory(prefix="pi-smartstake-") as temporary:
        files = download_month(manifest, Path(temporary))
        rows = aggregate_month(files, output)
    persisted = persist_aggregate(output) if args.persist else 0
    print(json.dumps({"output": str(output.resolve()), "aggregatedRows": rows,
                      "persistedRows": persisted}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
