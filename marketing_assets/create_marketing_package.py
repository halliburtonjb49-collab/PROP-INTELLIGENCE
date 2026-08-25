from pathlib import Path

import imageio.v3 as iio
import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent / "product_footage"
OUT = Path(r"C:\Users\PI\OneDrive\Desktop\PI Prop Intelligence - Marketing Package")
LOGO = Path(__file__).resolve().parents[1] / "assets" / "branding" / "Final_Master_Logo_Modern_PI.png"
FPS = 6
NAVY = (5, 17, 27)
GOLD = (184, 154, 77)
WHITE = (247, 248, 249)
MUTED = (174, 184, 193)


def face(size, bold=False):
    try:
        return ImageFont.truetype("arialbd.ttf" if bold else "arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def center(draw, text, y, font, fill, width):
    box = draw.textbbox((0, 0), text, font=font)
    draw.text(((width - box[2] + box[0]) / 2, y), text, font=font, fill=fill)


def title_frames(title, subtitle, count, size=(1280, 720), cta=None):
    logo = Image.open(LOGO).convert("RGBA") if LOGO.exists() else None
    if logo:
        logo.thumbnail((130, 130) if size[0] > size[1] else (170, 170))
    frames = []
    for i in range(count):
        image = Image.new("RGB", size, NAVY)
        draw = ImageDraw.Draw(image)
        for x in range(0, size[0] + 200, 80):
            draw.line((x, 0, x - 260, size[1]), fill=(10, 35, 49), width=1)
        draw.rectangle((0, 0, size[0], 8), fill=GOLD)
        if logo:
            y_logo = 70 if size[0] > size[1] else 160
            image.paste(logo, ((size[0] - logo.width) // 2, y_logo), logo)
        y_title = 245 if size[0] > size[1] else 430
        center(draw, title, y_title, face(54 if size[0] > size[1] else 52, True), WHITE, size[0])
        center(draw, subtitle, y_title + 80, face(25 if size[0] > size[1] else 26), MUTED, size[0])
        if cta:
            box = draw.textbbox((0, 0), cta, font=face(26, True))
            w = box[2] - box[0] + 70
            x = (size[0] - w) // 2
            y = y_title + 170
            draw.rounded_rectangle((x, y, x + w, y + 64), radius=14, fill=GOLD)
            center(draw, cta, y + 16, face(26, True), NAVY, size[0])
        alpha = min(1.0, (i + 1) / 4, (count - i) / 4)
        frames.append((np.asarray(image) * alpha).astype(np.uint8))
    return frames


def source_frames(name):
    return [Image.fromarray(frame).convert("RGB") for frame in iio.imiter(ROOT / name)]


def landscape_segment(name, caption, count):
    source = source_frames(name)
    start = max(0, (len(source) - count) // 2)
    selected = source[start:start + count] or source
    while len(selected) < count:
        selected.append(selected[-1])
    frames = []
    for image in selected:
        image = image.resize((1280, 720), Image.Resampling.LANCZOS)
        overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        draw.rounded_rectangle((38, 610, 1242, 690), radius=18, fill=(3, 12, 20, 228), outline=GOLD, width=2)
        center(draw, caption, 630, face(30, True), WHITE, 1280)
        frames.append(np.asarray(Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")))
    return frames


def vertical_segment(name, heading, caption, count):
    source = source_frames(name)
    start = max(0, (len(source) - count) // 2)
    selected = source[start:start + count] or source
    while len(selected) < count:
        selected.append(selected[-1])
    frames = []
    for shot in selected:
        canvas = Image.new("RGB", (720, 1280), NAVY)
        draw = ImageDraw.Draw(canvas)
        for x in range(0, 900, 72):
            draw.line((x, 0, x - 300, 1280), fill=(10, 35, 49), width=1)
        center(draw, heading, 110, face(38, True), GOLD, 720)
        shot.thumbnail((680, 720), Image.Resampling.LANCZOS)
        x = (720 - shot.width) // 2
        canvas.paste(shot, (x, 265))
        draw.rounded_rectangle((25, 1005, 695, 1160), radius=20, fill=(3, 12, 20), outline=GOLD, width=2)
        center(draw, caption, 1050, face(26, True), WHITE, 720)
        center(draw, "pipropsintell.com", 1195, face(24, True), GOLD, 720)
        frames.append(np.asarray(canvas))
    return frames


def write(name, frames):
    OUT.mkdir(parents=True, exist_ok=True)
    iio.imwrite(OUT / name, frames, fps=FPS, codec="libx264", quality=9, pixelformat="yuv420p")


# 30-second product walkthrough.
walkthrough = title_frames("FROM LIVE DATA TO CLEAR RESEARCH", "One workspace. Every step connected.", 18)
walkthrough += landscape_segment("03_add_remove_selection.mp4", "REVIEW LIVE PROPS AND PI SIGNALS", 30)
walkthrough += landscape_segment("02_view_research.mp4", "OPEN THE RESEARCH BEHIND THE SIGNAL", 30)
walkthrough += landscape_segment("03_add_remove_selection.mp4", "ADD OR REMOVE A SELECTION IN ONE TAP", 30)
walkthrough += landscape_segment("04_scoreboard.mp4", "FOLLOW LIVE AND UPCOMING GAMES", 30)
walkthrough += landscape_segment("06_active_slip.mp4", "TRACK ACTIVE RESEARCH IN REAL TIME", 24)
walkthrough += title_frames("RESEARCH THE MARKET. BUILD WITH CLARITY.", "Independent sports research and intelligence.", 18, cta="START YOUR 3-DAY FREE TRIAL")
write("PI_30_Second_Product_Demo.mp4", walkthrough)

# Vertical social master.
vertical = title_frames("RESEARCH WITH CLARITY", "Live sports intelligence wherever you are.", 12, (720, 1280))
vertical += vertical_segment("03_add_remove_selection.mp4", "LIVE PROP RESEARCH", "SCAN PI SIGNALS", 18)
vertical += vertical_segment("02_view_research.mp4", "PI TRUST", "SEE WHY THE SIGNAL MATTERS", 18)
vertical += vertical_segment("04_scoreboard.mp4", "LIVE SCOREBOARD", "FOLLOW TODAY'S GAMES", 18)
vertical += vertical_segment("06_active_slip.mp4", "ACTIVE RESEARCH", "TRACK EVERY SELECTION", 18)
vertical += title_frames("BUILD WITH CLARITY", "Independent research. Professional workflow.", 12, (720, 1280), "START YOUR 3-DAY FREE TRIAL")
write("PI_15_Second_Vertical_Social_Ad.mp4", vertical)

# Focused feature spots.
features = [
    ("PI_Feature_PI_Trust.mp4", "PI TRUST & VIEW RESEARCH", "02_view_research.mp4", "UNDERSTAND THE RESEARCH BEHIND EVERY SIGNAL"),
    ("PI_Feature_Live_Props.mp4", "LIVE PROP INTELLIGENCE", "03_add_remove_selection.mp4", "REVIEW, SELECT, AND ADJUST WITH CLARITY"),
    ("PI_Feature_Scoreboard_Slips.mp4", "FROM GAMES TO ACTIVE RESEARCH", "04_scoreboard.mp4", "FOLLOW THE BOARD AND STAY ORGANIZED"),
]
for filename, title, source, caption in features:
    frames = title_frames(title, "PI Prop Intelligence", 12)
    frames += landscape_segment(source, caption, 36)
    if "Scoreboard" in filename:
        frames += landscape_segment("06_active_slip.mp4", "TRACK ACTIVE RESEARCH IN REAL TIME", 18)
    frames += title_frames("BUILD WITH CLARITY", "Start your three-day free trial.", 12)
    write(filename, frames)

voiceover = """PI PROP INTELLIGENCE - 30-SECOND VOICE-OVER

Sports research moves fast. PI Prop Intelligence brings live props, provider data, PI Trust signals, and game information into one professional workspace.

Choose your sport. Review the market. Open View Research to understand the signal behind each selection. Add or remove research in one tap, follow live and upcoming games, and keep every active selection organized.

Research the market. Build with clarity. Start your three-day free trial at pipropsintell.com.

Responsible-use disclosure: PI Prop Intelligence provides independent sports research and intelligence only. It does not facilitate wagering or accept bets.
"""
(OUT / "PI_30_Second_Voiceover_Script.txt").write_text(voiceover, encoding="utf-8")
print(OUT)
