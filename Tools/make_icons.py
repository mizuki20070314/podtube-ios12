"""Generates the app icon set (no external assets needed).

usage: python Tools/make_icons.py
Writes PNGs + Contents.json into PodTube/Resources/Assets.xcassets/AppIcon.appiconset
"""
import json
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "PodTube", "Resources",
                   "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)

S = 1024 * 2  # supersampled canvas


def lerp(a, b, t):
    return int(a + (b - a) * t)


def make_master():
    # red vertical gradient background
    img = Image.new("RGB", (S, S))
    px = img.load()
    top = (255, 48, 64)
    bottom = (190, 0, 24)
    for y in range(S):
        t = y / (S - 1)
        c = (lerp(top[0], bottom[0], t), lerp(top[1], bottom[1], t), lerp(top[2], bottom[2], t))
        for x in range(S):
            px[x, y] = c
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = S // 2
    # soft shadow ring
    r = int(S * 0.285)
    d.ellipse([cx - r, cy - r + 14, cx + r, cy + r + 14], fill=(0, 0, 0, 60))
    # white disc
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
    # red play triangle (optically centered: shifted right a bit)
    tri_h = int(r * 1.05)
    tri_w = int(r * 0.92)
    x0 = cx - tri_w // 2 + int(r * 0.10)
    d.polygon([(x0, cy - tri_h // 2), (x0, cy + tri_h // 2), (x0 + tri_w, cy)], fill=(222, 8, 32, 255))
    return img.resize((1024, 1024), Image.LANCZOS)


master = make_master()

# (pt size, scale, idiom)
specs = [
    (20, 2), (20, 3), (29, 2), (29, 3), (40, 2), (40, 3), (60, 2), (60, 3),
]
images = []
for pt, scale in specs:
    px_size = pt * scale
    name = "icon-%dpt@%dx.png" % (pt, scale)
    master.resize((px_size, px_size), Image.LANCZOS).save(os.path.join(OUT, name))
    images.append({"size": "%dx%d" % (pt, pt), "idiom": "iphone", "filename": name, "scale": "%dx" % scale})

master.save(os.path.join(OUT, "icon-1024.png"))
images.append({"size": "1024x1024", "idiom": "ios-marketing", "filename": "icon-1024.png", "scale": "1x"})

with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)

with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
    json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)

print("wrote", len(images), "icons to", os.path.normpath(OUT))
