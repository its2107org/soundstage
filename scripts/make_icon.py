#!/usr/bin/env python3
"""Draws Soundstage's app icon (light, dark and tinted versions) at 1024 x 1024."""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "App/Assets.xcassets/AppIcon.appiconset"


def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def artwork(bar, waves, glow=None):
    """Transparent layer: a soundbar with sound rings rising from it."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, base = S / 2, 650
    # Rings above the bar.
    for i, (radius, width, alpha) in enumerate([(150, 34, 255), (250, 32, 200), (350, 30, 140)]):
        box = [cx - radius, base - radius, cx + radius, base + radius]
        colour = waves + (alpha,)
        d.arc(box, start=205, end=335, fill=colour, width=width)
        # Rounded ends.
        for ang in (205, 335):
            a = math.radians(ang)
            r = radius - width / 2
            x, y = cx + r * math.cos(a), base + r * math.sin(a)
            d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=colour)
    # The bar itself.
    w, h = 620, 118
    d.rounded_rectangle([cx - w / 2, base - h / 2 + 40, cx + w / 2, base + h / 2 + 40], radius=h / 2, fill=bar + (255,))
    # Speaker grille dots.
    for k in range(9):
        x = cx - 240 + k * 60
        d.ellipse([x - 13, base + 40 - 13, x + 13, base + 40 + 13], fill=waves + (255,))
    if glow:
        g = layer.filter(ImageFilter.GaussianBlur(40))
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        out.alpha_composite(g)
        out.alpha_composite(layer)
        return out
    return layer


def make(name, top, bottom, bar, waves, glow=False):
    bg = gradient(top, bottom).convert("RGBA")
    bg.alpha_composite(artwork(bar, waves, glow))
    bg.convert("RGB").save(f"{OUT}/{name}.png")


copper = (232, 132, 64)
make("icon-light", (255, 176, 102), (214, 92, 38), (40, 28, 24), (255, 246, 236))
make("icon-dark", (34, 30, 30), (8, 8, 10), (236, 230, 222), copper, glow=True)
make("icon-tinted", (24, 24, 24), (0, 0, 0), (235, 235, 235), (170, 170, 170))
print("Icons written to", OUT)
