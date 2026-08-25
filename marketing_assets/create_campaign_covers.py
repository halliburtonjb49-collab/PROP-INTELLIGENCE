from pathlib import Path

import imageio.v3 as iio
from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "product_footage" / "02_view_research.mp4"
LOGO = ROOT.parent / "assets" / "branding" / "Final_Master_Logo_Modern_PI.png"
DESKTOP = Path(r"C:\Users\PI\OneDrive\Desktop\PI Prop Intelligence - Marketing Package")
WEB = ROOT.parent / "marketing_site" / "assets" / "campaign"
NAVY = (3, 13, 21)
GOLD = (184, 154, 77)
WHITE = (247, 248, 249)
MUTED = (184, 191, 197)


def font(size, bold=False):
    try:
        return ImageFont.truetype("arialbd.ttf" if bold else "arial.ttf", size)
    except OSError:
        return ImageFont.load_default()


def center(draw, text, y, face, fill, width):
    box = draw.textbbox((0, 0), text, font=face)
    draw.text(((width - box[2] + box[0]) / 2, y), text, font=face, fill=fill)


frames = list(iio.imiter(SOURCE))
product = Image.fromarray(frames[len(frames) // 2]).convert("RGB")
logo = Image.open(LOGO).convert("RGBA")


def cover(size, title, subtitle, filename, vertical=False):
    w, h = size
    canvas = Image.new("RGB", size, NAVY)
    draw = ImageDraw.Draw(canvas)
    for x in range(0, w + 300, max(70, w // 15)):
        draw.line((x, 0, x - 320, h), fill=(10, 35, 49), width=1)
    canvas = canvas.filter(ImageFilter.GaussianBlur(0.25))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, w, max(8, h // 150)), fill=GOLD)
    logo_copy = logo.copy()
    logo_copy.thumbnail((150 if not vertical else 190, 150 if not vertical else 190))
    canvas.paste(logo_copy, ((w - logo_copy.width) // 2, 50 if not vertical else 130), logo_copy)
    title_y = 205 if not vertical else 390
    center(draw, title, title_y, font(54 if not vertical else 64, True), WHITE, w)
    center(draw, subtitle, title_y + 72, font(25 if not vertical else 34), MUTED, w)
    shot = product.copy()
    shot.thumbnail((int(w * .88), int(h * (.48 if not vertical else .42))), Image.Resampling.LANCZOS)
    shot_x = (w - shot.width) // 2
    shot_y = 330 if not vertical else 650
    canvas.paste(shot, (shot_x, shot_y))
    draw.rounded_rectangle((shot_x - 4, shot_y - 4, shot_x + shot.width + 4, shot_y + shot.height + 4), radius=16, outline=GOLD, width=4)
    cta = "START YOUR 3-DAY FREE TRIAL"
    cta_y = h - (88 if not vertical else 190)
    box = draw.textbbox((0, 0), cta, font=font(25 if not vertical else 34, True))
    cta_w = box[2] - box[0] + 70
    cta_x = (w - cta_w) // 2
    draw.rounded_rectangle((cta_x, cta_y, cta_x + cta_w, cta_y + (58 if not vertical else 78)), radius=14, fill=GOLD)
    center(draw, cta, cta_y + (14 if not vertical else 20), font(25 if not vertical else 34, True), NAVY, w)
    canvas.save(filename, quality=95)


DESKTOP.mkdir(parents=True, exist_ok=True)
WEB.mkdir(parents=True, exist_ok=True)
cover((1280, 720), "RESEARCH THE MARKET.", "Build with clarity.", DESKTOP / "PI_YouTube_Thumbnail.jpg")
cover((1080, 1080), "LIVE PROP INTELLIGENCE", "Research organized in one workspace.", DESKTOP / "PI_Square_Social_Cover.jpg")
cover((1080, 1920), "BUILD WITH CLARITY", "Live sports research wherever you are.", DESKTOP / "PI_Vertical_Reels_Cover.jpg", True)
cover((1280, 720), "RESEARCH THE MARKET.", "Build with clarity.", WEB / "campaign-poster.jpg")
print(DESKTOP)
