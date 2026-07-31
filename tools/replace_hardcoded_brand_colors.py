"""Replace legacy brand literals in Flutter custom widgets with AppColors.

Provider-specific colors are intentionally excluded so sportsbook and team
identity colors remain accurate. Run from the repository root.
"""

from __future__ import annotations

import os
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
APP_COLORS = LIB / "theme" / "app_colors.dart"

COLOR_MAP = {
    "FFFFC400": "gold",
    "FFF2BC35": "gold",
    "FFFFC72C": "gold",
    "FFFFD700": "goldHighlight",
    "FFFFD166": "goldHighlight",
    "FFD6B35A": "goldMid",
    "FF8B6813": "goldShadow",
    "FF8D6810": "goldShadow",
    "FF201A06": "goldSurface",
    "FF211C0B": "goldSurface",
    "FF36B9FF": "blue",
    "FF050A0F": "bgBase",
    "FF06111B": "bgBase",
    "FF06111C": "bgBase",
    "FF07131D": "sidebar",
    "FF07111B": "sidebar",
    "FF09141D": "sidebar",
    "FF0A1520": "sidebar",
    "FF0B151E": "sidebar",
    "FF0C1824": "bgPanel",
    "FF101D28": "bgPanel",
    "FF111D27": "bgPanel",
    "FF102131": "panelLight",
    "FF273445": "chromeShadow",
    "FF273B49": "chromeShadow",
    "FF283846": "chromeShadow",
    "FF293946": "chromeShadow",
    "FF294052": "chromeShadow",
    "FF344758": "gunmetalLight",
    "FF34495A": "gunmetalLight",
    "FF8B98A8": "textMuted",
    "FF8997A5": "textMuted",
    "FF8EA0AD": "textMuted",
    "FF96A4B2": "textSecondary",
    "FF98A6B8": "textSecondary",
    "FF9EB1C4": "textSecondary",
    "FFC8CED6": "silver",
    "FFD7DEE5": "silver",
    "FF59E769": "success",
    "FF56D38A": "success",
    "FF23D75F": "success",
    "FFFF4D5A": "danger",
    "FFFF5360": "danger",
    "FFFF5D68": "danger",
    "FFE53935": "danger",
}

COLOR_PATTERN = re.compile(
    r"(?<![\w.])(?:const\s+)?Color\(0x(" + "|".join(COLOR_MAP) + r")\)"
)


def import_path_for(path: Path) -> str:
    relative = os.path.relpath(APP_COLORS, path.parent).replace(os.sep, "/")
    return relative


def add_import(source: str, import_path: str) -> str:
    statement = f"import '{import_path}' as brand_colors;"
    if statement in source:
        return source
    imports = list(re.finditer(r"^import\s+[^;]+;\s*$", source, re.MULTILINE))
    if not imports:
        return statement + "\n\n" + source
    insert_at = imports[-1].end()
    return source[:insert_at] + "\n" + statement + source[insert_at:]


def rewrite(path: Path) -> int:
    source = path.read_text(encoding="utf-8-sig")
    prefix = "app_colors" if path == LIB / "main.dart" else "brand_colors"
    replacements = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal replacements
        replacements += 1
        return f"{prefix}.AppColors.{COLOR_MAP[match.group(1)]}"

    updated = COLOR_PATTERN.sub(replace, source)
    if not replacements:
        return 0
    if prefix == "brand_colors":
        updated = add_import(updated, import_path_for(path))
    path.write_text(updated, encoding="utf-8", newline="\n")
    return replacements


def main() -> None:
    total = 0
    changed = 0
    excluded = {APP_COLORS, LIB / "theme" / "prop_intelligence_colors.dart"}
    for path in sorted(LIB.rglob("*.dart")):
        if path in excluded:
            continue
        count = rewrite(path)
        if count:
            changed += 1
            total += count
            print(f"{path.relative_to(ROOT)}: {count}")
    print(f"Replaced {total} legacy color literals across {changed} files.")


if __name__ == "__main__":
    main()
