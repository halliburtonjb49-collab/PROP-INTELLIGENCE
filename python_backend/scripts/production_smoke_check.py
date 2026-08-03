"""Compatibility entry point for the security-aware production smoke gate."""

from __future__ import annotations

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from post_deploy_smoke import main  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(main())
