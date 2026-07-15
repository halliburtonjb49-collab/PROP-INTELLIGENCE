import argparse
import json
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from providers.api_sports_provider import ApiSportsProvider


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Test API-Sports key and connectivity without exposing a web endpoint.",
    )
    parser.add_argument(
        "--base-url",
        default="https://v1.basketball.api-sports.io",
        help="API-Sports base URL to test.",
    )
    parser.add_argument(
        "--endpoint",
        default="/status",
        help="Endpoint path to request.",
    )
    parser.add_argument(
        "--param",
        action="append",
        default=[],
        help="Optional query params in key=value format (repeatable).",
    )
    return parser


def parse_params(raw_params: list[str]) -> dict[str, str]:
    params: dict[str, str] = {}
    for item in raw_params:
        if "=" not in item:
            raise ValueError(
                f"Invalid --param '{item}'. Expected key=value format."
            )
        key, value = item.split("=", 1)
        key = key.strip()
        if not key:
            raise ValueError("Parameter key cannot be empty.")
        params[key] = value
    return params


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        params = parse_params(args.param)
        provider = ApiSportsProvider(args.base_url)
        payload = provider.get(args.endpoint, params=params)
    except Exception as exc:
        print("API-Sports test failed:")
        print(str(exc))
        return 1

    print("API-Sports test succeeded.")
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
