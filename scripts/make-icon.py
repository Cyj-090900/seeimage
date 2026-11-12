#!/usr/bin/env python3
"""Generates Resources/AppIcon.icns from code (Pillow + iconutil)."""

import math
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024
SCALE = 2  # supersampling factor


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(size, start, end):
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x / size + y / size) / 2
            pixels[x, y] = lerp(start, end, t)
    return image


def squircle_mask(size, inset, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=radius,
        fill=255,
    )
    return mask


def build_icon():
    canvas = SIZE * SCALE
    inset = int(canvas * 0.085)
    radius = int(canvas * 0.225)

    background = gradient(canvas, (79, 124, 255), (124, 58, 237))
    icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    icon.paste(background, (0, 0), squircle_mask(canvas, inset, radius))

    # Subtle top highlight.
    highlight = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.ellipse(
        (
            -canvas * 0.15,
            -canvas * 0.55,
            canvas * 1.15,
            canvas * 0.35,
        ),
        fill=(255, 255, 255, 46),
    )
    icon = Image.alpha_composite(icon, highlight)

    draw = ImageDraw.Draw(icon)

    # Sun.
    sun_center = (canvas * 0.66, canvas * 0.40)
    sun_radius = canvas * 0.085
    draw.ellipse(
        (
            sun_center[0] - sun_radius,
            sun_center[1] - sun_radius,
            sun_center[0] + sun_radius,
            sun_center[1] + sun_radius,
        ),
        fill=(255, 244, 214, 255),
    )

    # Mountain range clipped to the squircle.
    mountains = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    md = ImageDraw.Draw(mountains)
    base_y = canvas * 0.70

    def ridge(offset, amplitude, color):
        points = [(0, canvas)]
        steps = 128
        for step in range(steps + 1):
            x = canvas * step / steps
            y = base_y + offset + amplitude * math.sin(step / steps * math.pi * 2.6 + 0.6)
            points.append((x, y))
        points.append((canvas, canvas))
        md.polygon(points, fill=color)

    ridge(canvas * 0.005, canvas * 0.045, (255, 255, 255, 235))
    ridge(canvas * 0.075, canvas * 0.055, (255, 255, 255, 165))
    ridge(canvas * 0.155, canvas * 0.040, (32, 26, 84, 220))

    icon = Image.alpha_composite(icon, mountains)

    # Clip everything back to the squircle to remove overflow.
    mask = squircle_mask(canvas, inset, radius)
    clipped = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    clipped.paste(icon, (0, 0), mask)

    return clipped.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    icon = build_icon()
    resources = os.path.join(ROOT, "Resources")
    os.makedirs(resources, exist_ok=True)
    png_path = os.path.join(resources, "AppIcon.png")
    icon.save(png_path)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        specs = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]
        for name, size in specs:
            icon.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))

        icns_path = os.path.join(resources, "AppIcon.icns")
        subprocess.run(
            ["iconutil", "-c", "icns", iconset, "-o", icns_path],
            check=True,
        )

    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    shutil.copyfile(png_path, os.path.join(docs, "icon.png"))
    print("wrote", os.path.join(resources, "AppIcon.icns"))


if __name__ == "__main__":
    main()
