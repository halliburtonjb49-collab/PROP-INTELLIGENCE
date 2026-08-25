from pathlib import Path

import imageio.v3 as iio
import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent / "product_footage"
OUTPUT = Path(r"C:\Users\PI\OneDrive\Desktop\PI Prop Intelligence - Product Videos\PI_15_Second_Awareness_Ad_Corrected.mp4")
FPS = 6
SIZE = (1280, 720)
NAVY = (5, 17, 27)
GOLD = (184, 154, 77)
WHITE = (247, 248, 249)
MUTED = (176, 184, 192)


def font(size: int, bold: bool = False):
    name = "arialbd.ttf" if bold else "arial.ttf"
    try:
        return ImageFont.truetype(name, size)
    except OSError:
        return ImageFont.load_default()


def centered(draw, text, y, face, fill):
    box = draw.textbbox((0, 0), text, font=face)
    draw.text(((SIZE[0] - (box[2] - box[0])) / 2, y), text, font=face, fill=fill)


def card(title: str, subtitle: str, count: int, cta: str | None = None):
    frames = []
    logo_path = Path(__file__).resolve().parents[1] / "assets" / "branding" / "Final_Master_Logo_Modern_PI.png"
    logo = Image.open(logo_path).convert("RGBA") if logo_path.exists() else None
    if logo:
        logo.thumbnail((132, 132))
    for index in range(count):
        image = Image.new("RGB", SIZE, NAVY)
        draw = ImageDraw.Draw(image)
        for x in range(0, SIZE[0], 80):
            draw.line((x, 0, x - 260, SIZE[1]), fill=(10, 35, 49), width=1)
        draw.rectangle((0, 0, SIZE[0], 8), fill=GOLD)
        if logo:
            image.paste(logo, ((SIZE[0] - logo.width) // 2, 92), logo)
        centered(draw, title, 260, font(56, True), WHITE)
        centered(draw, subtitle, 340, font(27), MUTED)
        if cta:
            box = draw.textbbox((0, 0), cta, font=font(27, True))
            width = box[2] - box[0] + 70
            left = (SIZE[0] - width) // 2
            draw.rounded_rectangle((left, 430, left + width, 494), radius=14, fill=GOLD)
            centered(draw, cta, 445, font(27, True), NAVY)
        alpha = min(1.0, (index + 1) / 4, (count - index) / 4)
        frames.append((np.asarray(image) * alpha).astype(np.uint8))
    return frames


def clip(path: Path, caption: str, count: int = 12):
    frames = list(iio.imiter(path))
    if not frames:
        return []
    start = max(0, (len(frames) - count) // 2)
    chosen = frames[start : start + count]
    while len(chosen) < count:
        chosen.append(chosen[-1])
    output = []
    for frame in chosen:
        image = Image.fromarray(frame).convert("RGB").resize(SIZE, Image.Resampling.LANCZOS)
        overlay = Image.new("RGBA", SIZE, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        draw.rounded_rectangle((38, 610, 1242, 690), radius=18, fill=(3, 12, 20, 224), outline=GOLD, width=2)
        centered(draw, caption, 630, font(30, True), WHITE)
        output.append(np.asarray(Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")))
    return output


frames = []
frames += card("RESEARCH THE MARKET.", "Live multi-sport intelligence in one professional workspace.", 12)
frames += clip(ROOT / "03_add_remove_selection.mp4", "SCAN LIVE PROPS AND PI SIGNALS")
frames += clip(ROOT / "04_scoreboard.mp4", "FOLLOW LIVE AND UPCOMING GAMES")
frames += clip(ROOT / "02_view_research.mp4", "UNDERSTAND EVERY PI SIGNAL")
frames += clip(ROOT / "03_add_remove_selection.mp4", "BUILD AND ADJUST YOUR RESEARCH")
frames += clip(ROOT / "06_active_slip.mp4", "TRACK ACTIVE RESEARCH IN REAL TIME")
frames += card("BUILD WITH CLARITY.", "Independent sports research and intelligence.", 18, "START YOUR 3-DAY FREE TRIAL")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
iio.imwrite(OUTPUT, frames, fps=FPS, codec="libx264", quality=9, pixelformat="yuv420p")
print(OUTPUT)
