"""Build leakage-safe MLB player-game feature files from a Statcast Parquet."""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.mlb_parquet_feature_service import (  # noqa: E402
    build_feature_parquets,
    persist_feature_parquets,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--persist", action="store_true",
                        help="Upsert generated features into configured PostgreSQL")
    args = parser.parse_args()
    if not args.source.is_file():
        parser.error(f"Statcast Parquet does not exist: {args.source}")
    result = build_feature_parquets(args.source, args.output_directory)
    if args.persist:
        result["persistence"] = persist_feature_parquets(args.output_directory)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
