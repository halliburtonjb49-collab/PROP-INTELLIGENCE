from __future__ import annotations

import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"PWA validation failed: {message}")


root = Path(sys.argv[1] if len(sys.argv) > 1 else "web")
manifest_path = root / "manifest.json"
index_path = root / "index.html"

if not manifest_path.is_file() or not index_path.is_file():
    fail("manifest.json or index.html is missing")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
for field in ("name", "short_name", "id", "start_url", "scope", "display"):
    if not manifest.get(field):
        fail(f"manifest field {field!r} is missing")

if manifest["display"] not in {"standalone", "fullscreen", "minimal-ui"}:
    fail("display mode is not installable")

sizes = set()
for icon in manifest.get("icons", []):
    icon_path = root / icon.get("src", "")
    if not icon_path.is_file():
        fail(f"icon does not exist: {icon_path}")
    sizes.add(icon.get("sizes"))
if not {"192x192", "512x512"}.issubset(sizes):
    fail("192x192 and 512x512 icons are required")

html = index_path.read_text(encoding="utf-8").lower()
for marker in (
    'rel="manifest"',
    'name="theme-color"',
    'name="viewport"',
    'apple-mobile-web-app-capable',
    'pwa_install.js',
):
    if marker not in html:
        fail(f"index.html is missing {marker}")

if root.name == "web" and not (root / "flutter_service_worker.js").is_file():
    fail("Flutter service worker is missing from the production build")

print(f"PWA validation passed for {root}")
