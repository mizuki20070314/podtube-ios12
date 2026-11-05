"""Builds docs/screens.jpg (a row of CI screenshots) for the README.

usage: python Tools/make_montage.py <screenshots-dir> [names...]
"""
import os
import sys
from PIL import Image

src = sys.argv[1]
names = sys.argv[2:] or ["01_home_dark", "05_watch", "17_controls", "07_comments", "10_shorts", "12_library"]
W = 280
imgs = []
for n in names:
    p = os.path.join(src, n + ".png")
    if not os.path.exists(p):
        print("missing", p)
        continue
    im = Image.open(p).convert("RGB")
    h = int(im.height * W / im.width)
    imgs.append(im.resize((W, h), Image.LANCZOS))

pad = 10
total_w = pad + sum(i.width + pad for i in imgs)
total_h = max(i.height for i in imgs) + pad * 2
canvas = Image.new("RGB", (total_w, total_h), (15, 15, 15))
x = pad
for im in imgs:
    canvas.paste(im, (x, pad))
    x += im.width + pad
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "screens.jpg")
os.makedirs(os.path.dirname(out), exist_ok=True)
canvas.save(out, "JPEG", quality=82, optimize=True)
print("wrote", os.path.normpath(out), canvas.size, os.path.getsize(out), "bytes")
