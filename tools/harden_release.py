"""Fail a release when backend security or dependency checks fail."""

from __future__ import annotations

from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SKIPPED_PARTS = {
    ".dart_tool", ".git", ".pytest_cache", ".venv", "build", "node_modules",
    "__pycache__",
}
DEBUG_PATTERN = re.compile(r"\bDEBUG\s*=\s*True\b", re.IGNORECASE)


def run_check(command: list[str], description: str) -> bool:
    print(f"\n[***] {description} [***]")
    executable = command[0]
    if shutil.which(executable) is None:
        print(
            f"FAILED: {executable} is not installed. "
            "Run: python -m pip install -r requirements-dev.txt"
        )
        return False
    completed = subprocess.run(command, cwd=ROOT, text=True, check=False)
    if completed.returncode == 0:
        print("PASSED")
        return True
    print(f"FAILED with exit code {completed.returncode}")
    return False


def check_for_debug_flags() -> bool:
    print("\n[***] Hardcoded Python debug flags [***]")
    findings: list[tuple[Path, int]] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".py", ".env"}:
            continue
        if any(part in SKIPPED_PARTS for part in path.parts):
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError):
            continue
        findings.extend(
            (path.relative_to(ROOT), line_number)
            for line_number, line in enumerate(lines, 1)
            if DEBUG_PATTERN.search(line)
        )
    if not findings:
        print("PASSED")
        return True
    for path, line_number in findings:
        print(f"FAILED: hardcoded debug mode in {path}:{line_number}")
    return False


def main() -> int:
    checks = [
        run_check(
            [
                "bandit", "-r", "python_backend", "-x",
                "python_backend/tests,python_backend/.venv",
                "-lll", "-iii", "-q",
            ],
            "Bandit high-severity/high-confidence security gate",
        ),
        run_check(
            ["pip-audit", "-r", "requirements.txt", "--progress-spinner", "off"],
            "Production dependency vulnerability audit",
        ),
        check_for_debug_flags(),
    ]
    print("\n" + "=" * 48)
    if all(checks):
        print("ALL RELEASE HARDENING CHECKS PASSED")
        return 0
    print("RELEASE HARDENING CHECKS FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
