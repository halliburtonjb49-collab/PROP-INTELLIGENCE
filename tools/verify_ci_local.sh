#!/usr/bin/env sh
set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "[verify] flutter pub get"
flutter pub get

echo "[verify] flutter analyze"
flutter analyze

echo "[verify] flutter test"
flutter test

if [ -x ".venv/Scripts/python.exe" ]; then
  echo "[verify] python -m pytest (venv)"
  .venv/Scripts/python.exe -m pytest
elif [ -x ".venv/bin/python" ]; then
  echo "[verify] python -m pytest (venv)"
  .venv/bin/python -m pytest
else
  echo "[verify] pytest"
  pytest
fi

echo "[verify] all checks passed"
