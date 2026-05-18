#!/usr/bin/env python3
"""Generate placeholder GIFs for the README demo section.

Run once to populate `docs/demos/*.gif` with branded "recording coming
soon" placeholders. As you record each real demo and convert it via
`scripts/mp4-to-gif.sh`, the real GIF overwrites the placeholder and the
README image references stay valid throughout.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "demos"

# Each entry: (filename, title, subtitle, hotkey, accent_hue_rgb)
DEMOS = [
    ("zoom.gif",        "Zoom",         "Freeze + magnify any region",                 "⌘1",          (255, 99,  72)),
    ("live-zoom.gif",   "Live Zoom",    "Real-time magnification that follows you",    "⌘4",          (255, 149, 0)),
    ("drawing.gif",     "Drawing",      "Pens, shapes, text, blur, whiteboard",        "⌘2",          (88,  86,  214)),
    ("break-timer.gif", "Break Timer",  "Full-screen countdown between sessions",      "⌘3",          (52,  199, 89)),
    ("screenshots.gif", "Screenshots",  "Full screen, region — copy or save as PNG",   "⌘6 / ⌘⇧6",    (0,   122, 255)),
    ("recording.gif",   "Recording",    "Capture full screen, region, or window",      "⌘5 / ⌘⇧5",    (255, 45,  85)),
]

WIDTH, HEIGHT = 720, 360
SCALE = 2  # supersample for crisp anti-aliased text


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ):
        if Path(candidate).exists():
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                continue
    return ImageFont.load_default()


def draw_centered(draw: ImageDraw.ImageDraw, text: str, y: int, font, fill, w: int) -> None:
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((w - tw) / 2, y), text, font=font, fill=fill)


def render_one(out_path: Path, title: str, subtitle: str, hotkey: str, accent: tuple[int, int, int]) -> None:
    w, h = WIDTH * SCALE, HEIGHT * SCALE
    img = Image.new("RGB", (w, h), (24, 24, 28))

    # soft radial gradient with the accent color
    grad = Image.new("RGB", (w, h), (24, 24, 28))
    gdraw = ImageDraw.Draw(grad)
    cx, cy = w // 2, h // 2
    max_r = int(((cx ** 2) + (cy ** 2)) ** 0.5)
    for r in range(max_r, 0, -8):
        t = 1 - (r / max_r)
        mix = lambda base, ax: int(base + (ax - base) * t * 0.35)
        col = (mix(24, accent[0]), mix(24, accent[1]), mix(28, accent[2]))
        gdraw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    grad = grad.filter(ImageFilter.GaussianBlur(radius=40))
    img.paste(grad, (0, 0))

    draw = ImageDraw.Draw(img)

    title_font = load_font(int(64 * SCALE))
    sub_font = load_font(int(28 * SCALE))
    hotkey_font = load_font(int(34 * SCALE))
    note_font = load_font(int(22 * SCALE))

    # accent pill behind the hotkey
    bbox = draw.textbbox((0, 0), hotkey, font=hotkey_font)
    pad_x, pad_y = int(28 * SCALE), int(12 * SCALE)
    pill_w = (bbox[2] - bbox[0]) + pad_x * 2
    pill_h = (bbox[3] - bbox[1]) + pad_y * 2
    pill_x = (w - pill_w) // 2
    pill_y = int(60 * SCALE)
    draw.rounded_rectangle(
        (pill_x, pill_y, pill_x + pill_w, pill_y + pill_h),
        radius=int(pill_h / 2),
        fill=accent,
    )
    hk_x = pill_x + pad_x - bbox[0]
    hk_y = pill_y + pad_y - bbox[1]
    draw.text((hk_x, hk_y), hotkey, font=hotkey_font, fill=(255, 255, 255))

    draw_centered(draw, title, int(170 * SCALE), title_font, (245, 245, 250), w)
    draw_centered(draw, subtitle, int(255 * SCALE), sub_font, (210, 210, 220), w)
    draw_centered(
        draw,
        "Demo recording coming soon",
        int(305 * SCALE),
        note_font,
        (180, 180, 195),
        w,
    )

    img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)

    img.save(out_path, format="GIF", optimize=True)
    print(f"  → {out_path.relative_to(ROOT)}  ({out_path.stat().st_size // 1024} KB)")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Writing {len(DEMOS)} placeholder GIFs to {OUT_DIR.relative_to(ROOT)}/")
    for filename, title, subtitle, hotkey, accent in DEMOS:
        render_one(OUT_DIR / filename, title, subtitle, hotkey, accent)
    print("Done.")


if __name__ == "__main__":
    main()
