#!/usr/bin/env python3
"""
MacZoomer app icon generator.

Design:
- macOS-style squircle background with a vibrant coral->red diagonal gradient
  (echoes ZoomIt's red heritage while feeling native to macOS Big Sur+).
- White magnifying glass tilted 35 degrees, with a "+" inside the lens (zoom-in).
- Subtle drop shadow under the glass for depth.

Usage:
    python3 scripts/make-app-icon.py

Generates:
- /tmp/maczoomer_master.png (1024x1024 master)
- All standard macOS icon sizes inside the AppIcon.appiconset

Requires: Pillow (`pip install Pillow`), `sips`, `iconutil` (macOS built-ins).
"""

import math
import os
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFilter

SCALE = 4
SIZE = 1024 * SCALE
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASTER_PATH = "/tmp/maczoomer_master.png"
APPICON_SET = os.path.join(
    REPO_ROOT,
    "Sources/MacZoomer/Resources/Assets.xcassets/AppIcon.appiconset",
)
ICON_SIZES = [16, 32, 128, 256, 512]


def squircle_mask(size, radius_ratio=0.225):
    """macOS Big Sur squircle: an approximation using a rounded rect with
    a corner radius of ~22.5% of the side length."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = int(size * radius_ratio)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return mask


def gradient_background(size, top_color, bottom_color):
    """Diagonal linear gradient from top_color (top-left) to bottom_color
    (bottom-right)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    tr, tg, tb = top_color
    br, bg, bb = bottom_color
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            r = int(tr + (br - tr) * t)
            g = int(tg + (bg - tg) * t)
            b = int(tb + (bb - tb) * t)
            px[x, y] = (r, g, b, 255)
    return img


def fast_gradient(size, top, bottom):
    """Faster diagonal gradient via a 2-pixel image stretched + rotated."""
    small = Image.new("RGBA", (2, 2))
    small.putpixel((0, 0), top)
    small.putpixel((1, 0), (
        (top[0] + bottom[0]) // 2,
        (top[1] + bottom[1]) // 2,
        (top[2] + bottom[2]) // 2,
        255,
    ))
    small.putpixel((0, 1), small.getpixel((1, 0)))
    small.putpixel((1, 1), bottom)
    return small.resize((size, size), Image.BICUBIC)


def make_icon():
    # Coral -> red gradient. Top-left lighter coral, bottom-right deeper red.
    top = (255, 138, 92, 255)
    bottom = (227, 47, 78, 255)

    bg = fast_gradient(SIZE, top, bottom)

    mask = squircle_mask(SIZE)
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), mask=mask)

    # Very subtle top sheen — keep low opacity so it doesn't band the lens.
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(highlight)
    hdraw.ellipse(
        [-SIZE * 0.4, -SIZE * 0.85, SIZE * 1.4, SIZE * 0.25],
        fill=(255, 255, 255, 22),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=SIZE * 0.05))
    icon = Image.alpha_composite(icon, _masked(highlight, mask))

    # Magnifying glass geometry (in the icon's own coordinate space).
    cx, cy = SIZE * 0.435, SIZE * 0.435
    ring_outer_r = SIZE * 0.275
    ring_thickness = SIZE * 0.060
    handle_length = SIZE * 0.27
    handle_thickness = SIZE * 0.080
    angle_deg = 35

    glass = draw_magnifier(
        SIZE,
        center=(cx, cy),
        outer_radius=ring_outer_r,
        ring_thickness=ring_thickness,
        handle_length=handle_length,
        handle_thickness=handle_thickness,
        angle_deg=angle_deg,
    )

    # Drop shadow underneath the glass
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.bitmap((0, 0), glass.split()[3], fill=(0, 0, 0, 130))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=SIZE * 0.022))
    offset = int(SIZE * 0.020)
    shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_layer.paste(shadow, (offset, offset), shadow)
    icon = Image.alpha_composite(icon, _masked(shadow_layer, mask))

    # Composite the glass over the icon, clipped to the squircle.
    icon = Image.alpha_composite(icon, _masked(glass, mask))

    # Final downsample to 1024 for the master PNG.
    icon = icon.resize((1024, 1024), Image.LANCZOS)
    icon.save(MASTER_PATH, "PNG")
    print(f"Wrote {MASTER_PATH}")


def _masked(layer, mask):
    """Apply the squircle alpha mask to a same-size RGBA layer."""
    out = layer.copy()
    alpha = out.split()[3]
    new_alpha = Image.new("L", out.size, 0)
    new_alpha.paste(alpha, (0, 0), mask=mask)
    out.putalpha(new_alpha)
    return out


def populate_appiconset():
    """Downsample the master PNG into all standard macOS icon sizes and
    overwrite the AppIcon.appiconset entries in place. Idempotent."""
    if not os.path.isdir(APPICON_SET):
        os.makedirs(APPICON_SET, exist_ok=True)

    for base in ICON_SIZES:
        for scale_factor in (1, 2):
            pixel_size = base * scale_factor
            suffix = "@2x" if scale_factor == 2 else ""
            filename = f"icon_{base}x{base}{suffix}.png"
            target = os.path.join(APPICON_SET, filename)
            subprocess.run(
                ["sips", "-z", str(pixel_size), str(pixel_size),
                 MASTER_PATH, "--out", target],
                check=True, capture_output=True,
            )
    print(f"Wrote {len(ICON_SIZES) * 2} icon variants → {APPICON_SET}")



def draw_magnifier(size, center, outer_radius, ring_thickness,
                   handle_length, handle_thickness, angle_deg):
    """Build the magnifying glass on a transparent canvas. Returns RGBA."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    cx, cy = center

    # Handle: a rotated rounded rectangle reaching from the glass edge outward
    # toward the bottom-right.
    rad = math.radians(angle_deg)
    handle_start_offset = outer_radius - ring_thickness * 0.05
    handle_end_offset = handle_start_offset + handle_length

    start_x = cx + math.cos(rad) * handle_start_offset
    start_y = cy + math.sin(rad) * handle_start_offset
    end_x = cx + math.cos(rad) * handle_end_offset
    end_y = cy + math.sin(rad) * handle_end_offset

    handle_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    handle_draw = ImageDraw.Draw(handle_layer)
    handle_half = handle_thickness / 2
    handle_draw.rounded_rectangle(
        [
            cx + handle_start_offset - 4,
            cy - handle_half,
            cx + handle_end_offset,
            cy + handle_half,
        ],
        radius=handle_half,
        fill=(255, 255, 255, 255),
    )
    handle_layer = handle_layer.rotate(
        angle_deg, center=(cx, cy), resample=Image.BICUBIC
    )
    layer = Image.alpha_composite(layer, handle_layer)
    draw = ImageDraw.Draw(layer)

    # Outer ring of the lens.
    draw.ellipse(
        [cx - outer_radius, cy - outer_radius,
         cx + outer_radius, cy + outer_radius],
        fill=(255, 255, 255, 255),
    )
    inner_r = outer_radius - ring_thickness
    # Punch out the lens interior so the coral gradient shows through —
    # cleaner read at small sizes than a translucent tint.
    draw.ellipse(
        [cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r],
        fill=(0, 0, 0, 0),
    )

    # Plus sign inside the lens.
    plus_len = inner_r * 1.05
    plus_thick = ring_thickness * 0.78
    draw.rounded_rectangle(
        [cx - plus_len / 2, cy - plus_thick / 2,
         cx + plus_len / 2, cy + plus_thick / 2],
        radius=plus_thick / 2,
        fill=(255, 255, 255, 255),
    )
    draw.rounded_rectangle(
        [cx - plus_thick / 2, cy - plus_len / 2,
         cx + plus_thick / 2, cy + plus_len / 2],
        radius=plus_thick / 2,
        fill=(255, 255, 255, 255),
    )

    return layer


if __name__ == "__main__":
    make_icon()
    populate_appiconset()
