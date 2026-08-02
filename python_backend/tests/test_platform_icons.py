import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]


def _size(path: str) -> tuple[int, int]:
    with Image.open(ROOT / path) as image:
        return image.size


def test_platform_launcher_icons_have_required_dimensions() -> None:
    expected = {
        "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
        "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, 72),
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, 96),
        "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, 144),
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, 192),
        "android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png": (432, 432),
        "web/favicon.png": (64, 64),
        "web/icons/Icon-192.png": (192, 192),
        "web/icons/Icon-512.png": (512, 512),
        "web/icons/Icon-maskable-safe-192.png": (192, 192),
        "web/icons/Icon-maskable-safe-512.png": (512, 512),
        "linux/runner/resources/app_icon.png": (512, 512),
    }
    assert {path: _size(path) for path in expected} == expected


def test_apple_asset_catalog_files_match_declared_sizes() -> None:
    catalogs = [
        ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset",
        ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset",
    ]
    for catalog in catalogs:
        contents = json.loads((catalog / "Contents.json").read_text(encoding="utf-8"))
        for item in contents["images"]:
            filename = item.get("filename")
            if not filename:
                continue
            base = float(item["size"].split("x", 1)[0])
            scale = int(item["scale"].removesuffix("x"))
            expected = round(base * scale)
            with Image.open(catalog / filename) as image:
                assert image.size == (expected, expected)


def test_web_manifest_references_generated_master_icons() -> None:
    manifest = json.loads((ROOT / "web/manifest.json").read_text(encoding="utf-8"))
    sources = {item["src"] for item in manifest["icons"]}
    assert {
        "icons/Icon-192.png",
        "icons/Icon-512.png",
        "icons/Icon-maskable-safe-192.png",
        "icons/Icon-maskable-safe-512.png",
    }.issubset(sources)


def test_windows_icon_contains_desktop_sizes() -> None:
    with Image.open(ROOT / "windows/runner/resources/app_icon.ico") as icon:
        assert {(16, 16), (32, 32), (48, 48), (256, 256)}.issubset(
            icon.info["sizes"]
        )
