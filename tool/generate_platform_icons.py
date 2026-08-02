"""Generate every platform launcher icon from the approved master logo."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "assets"
    / "branding"
    / "app_icons_master_logo"
    / "Prop_Intelligence_Full_Master_App_Icon_1024.png"
)


def resized(source: Image.Image, size: int) -> Image.Image:
    return source.resize((size, size), Image.Resampling.LANCZOS)


def save_png(source: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized(source, size).save(path, optimize=True)


def save_safe_zone(
    source: Image.Image, path: Path, size: int, inset_ratio: float = 0.78
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGB", (size, size), "#07121B")
    inset_size = round(size * inset_ratio)
    inset = resized(source, inset_size)
    offset = (size - inset_size) // 2
    canvas.paste(inset, (offset, offset))
    canvas.save(path, optimize=True)


def generate_asset_catalog(source: Image.Image, catalog: Path) -> None:
    contents = json.loads((catalog / "Contents.json").read_text(encoding="utf-8"))
    for item in contents["images"]:
        filename = item.get("filename")
        if not filename:
            continue
        base = float(item["size"].split("x", 1)[0])
        scale = int(item["scale"].removesuffix("x"))
        save_png(source, catalog / filename, round(base * scale))


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")

    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    for density, size in android_sizes.items():
        save_png(source, android_res / density / "ic_launcher.png", size)
    save_safe_zone(
        source,
        android_res / "drawable-nodpi" / "ic_launcher_foreground.png",
        432,
        inset_ratio=0.66,
    )

    generate_asset_catalog(
        source, ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    )
    generate_asset_catalog(
        source, ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    )

    web = ROOT / "web"
    save_png(source, web / "favicon.png", 64)
    save_png(source, web / "icons" / "apple-touch-icon-180.png", 180)
    for size in (192, 512):
        save_png(source, web / "icons" / f"Icon-{size}.png", size)
        save_png(source, web / "icons" / f"Icon-maskable-{size}.png", size)
        save_safe_zone(source, web / "icons" / f"Icon-maskable-safe-{size}.png", size)

    windows_icon = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    source.save(
        windows_icon,
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    save_png(source, ROOT / "linux" / "runner" / "resources" / "app_icon.png", 512)


if __name__ == "__main__":
    main()
