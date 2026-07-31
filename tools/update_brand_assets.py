"""Generate every application brand asset from Final Master Logo.png."""

from __future__ import annotations

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "assets" / "branding" / "Final Master Logo.png"
NAVY = (8, 13, 21)


def save_optimized(image: Image.Image, relative: str) -> None:
    destination = ROOT / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(destination, "PNG", optimize=True, compress_level=9)


def fit(source: Image.Image, width: int, height: int, scale: float = 1.0) -> Image.Image:
    canvas = Image.new("RGB", (width, height), NAVY)
    ratio = min(width / source.width, height / source.height) * scale
    resized = source.resize(
        (round(source.width * ratio), round(source.height * ratio)),
        Image.Resampling.LANCZOS,
    )
    canvas.paste(resized, ((width - resized.width) // 2, (height - resized.height) // 2))
    return canvas


def main() -> None:
    with Image.open(MASTER) as opened:
        master = opened.convert("RGB")

    # Full artwork stays intact for brand surfaces and login/splash screens.
    save_optimized(master, "assets/branding/prop_intelligence_master.png")
    full_ui = fit(master, 768, 768, 0.98)
    save_optimized(full_ui, "assets/branding/prop_intelligence_logo.png")
    save_optimized(full_ui, "assets/branding/prop_intelligence_logo_transparent.png")

    # The owner requires the complete master artwork on every application icon,
    # including the PROP INTELLIGENCE wordmark and FIND THE EDGE tagline.
    icon = fit(master, 1024, 1024, 0.94)
    save_optimized(icon, "assets/branding/prop_intelligence_icon.png")

    save_optimized(fit(master, 673, 632, 0.96), "assets/players/logo.png")
    save_optimized(fit(icon, 512, 512), "assets/players/logo_icon.png")
    save_optimized(fit(master, 1080, 1920, 0.84), "assets/players/Splash_Dark.png")
    save_optimized(fit(master, 1080, 1920, 0.84), "assets/players/Splash_Light.png")

    android = {
        "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
        "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
        "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    ios = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    legacy = {
        "Icon-App-1024x1024@1x.png": 1024,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83_5x83_5@2x.png": 167,
        "ic_launcher.png": 192,
        "ic_launcher_foreground.png": 432,
        "ic_launcher_round.png": 192,
    }
    for path, size in android.items():
        save_optimized(fit(icon, size, size), path)
    for name, size in ios.items():
        save_optimized(
            fit(icon, size, size),
            f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}",
        )
    for name, size in legacy.items():
        save_optimized(fit(icon, size, size), f"assets/players/{name}")
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_optimized(
            fit(icon, size, size),
            f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png",
        )
    for name, size in {
        "Icon-192.png": 192,
        "Icon-512.png": 512,
        "Icon-maskable-192.png": 192,
        "Icon-maskable-512.png": 512,
    }.items():
        save_optimized(fit(icon, size, size), f"web/icons/{name}")
    save_optimized(fit(icon, 64, 64), "web/favicon.png")

    ico_path = ROOT / "windows/runner/resources/app_icon.ico"
    icon.save(ico_path, format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (256, 256)])
    print("Updated all logo, splash, PWA, Android, iOS, macOS, and Windows assets.")


if __name__ == "__main__":
    main()
