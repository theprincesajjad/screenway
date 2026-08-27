#!/usr/bin/env python3
"""Generates Screenway's app icon PNG into the asset catalog.

Deliberately simple, system-looking mark: a dark square (iOS applies the
rounded mask) with a calm display glyph. No text, no gradients that scream,
no photorealism. Output is opaque RGB (no alpha), as required for the
1024pt App Store / marketing icon slot.

Usage: python3 scripts/generate_app_icon.py
Requires: Pillow (pip3 install pillow)
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
# Supersample for smooth curves, then downscale.
SCALE = 4
S = SIZE * SCALE

OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "Screenway"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon-1024.png"
)

BACKGROUND_TOP = (21, 23, 28)
BACKGROUND_BOTTOM = (12, 14, 18)
SCREEN_FILL = (28, 33, 41)
STROKE = (159, 180, 208)


def main() -> None:
    img = Image.new("RGB", (S, S))
    draw = ImageDraw.Draw(img)

    # Subtle vertical gradient so the dark square doesn't look flat.
    for y in range(S):
        t = y / (S - 1)
        color = tuple(
            round(BACKGROUND_TOP[i] + (BACKGROUND_BOTTOM[i] - BACKGROUND_TOP[i]) * t)
            for i in range(3)
        )
        draw.line([(0, y), (S, y)], fill=color)

    def box(x0: float, y0: float, x1: float, y1: float) -> list[float]:
        return [x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE]

    stroke_width = 40 * SCALE

    # Display: rounded-rect screen outline with a slightly lighter panel.
    draw.rounded_rectangle(
        box(240, 264, 784, 640),
        radius=64 * SCALE,
        fill=SCREEN_FILL,
        outline=STROKE,
        width=stroke_width,
    )

    # Stand: short stem plus a rounded base line.
    draw.rounded_rectangle(box(488, 640, 536, 712), radius=12 * SCALE, fill=STROKE)
    draw.rounded_rectangle(box(368, 712, 656, 752), radius=20 * SCALE, fill=STROKE)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUTPUT, format="PNG")
    print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
