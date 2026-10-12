#!/usr/bin/env python3
"""Draws the app icon (1024 px) into <out_dir>/icon.png. Usage: scripts/make-icon.py <out_dir>"""
import sys, math
from PIL import Image, ImageDraw, ImageFilter, ImageChops
out = sys.argv[1]
S = 4; N = 1024*S
def C(v): return int(v*S)

def squircle_mask():
    m = Image.new("L", (N, N), 0)
    cx = cy = N/2; a = C(412); n = 5.0
    pts = []
    for i in range(720):
        t = 2*math.pi*i/720
        c, s = math.cos(t), math.sin(t)
        x = cx + a*math.copysign(abs(c)**(2/n), c)
        y = cy + a*math.copysign(abs(s)**(2/n), s)
        pts.append((x, y))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m

def vgrad(top, bot):
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        f = y/255
        g.putpixel((0, y), tuple(int(top[i]*(1-f)+bot[i]*f) for i in range(3)))
    return g.resize((N, N))

def finish(base, name):
    mask = squircle_mask()
    icon = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    icon.paste(base, (0, 0), mask)
    # drop shadow like macOS icons
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 90), (0, C(14)), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(C(18)))
    final = Image.alpha_composite(sh, icon).resize((1024, 1024), Image.LANCZOS)
    final.save(f"{out}/{name}.png")

def glow(layer, r):
    return layer.filter(ImageFilter.GaussianBlur(C(r)))

# Ping ripple — blue diamond marker with expanding rings on deep navy
def concept_a():
    base = vgrad((22, 34, 58), (8, 12, 24)).convert("RGBA")
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    cx, cy = N/2, C(560)
    for r, w, al in [(330, 14, 70), (250, 18, 120), (170, 22, 190)]:
        d.ellipse([cx-C(r), cy-C(r*0.42), cx+C(r), cy+C(r*0.42)], outline=(80, 170, 255, al), width=C(w))
    g = glow(lay, 10); base = Image.alpha_composite(base, g); base = Image.alpha_composite(base, lay)
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
    # diamond marker standing above the rings
    top, mid, bot, hw = C(200), C(400), C(560), C(150)
    d.polygon([(cx, top), (cx+hw, mid), (cx, bot), (cx-hw, mid)], fill=(70, 160, 255, 255))
    d.polygon([(cx, top), (cx+hw, mid), (cx, mid+C(20))], fill=(140, 205, 255, 255))
    d.polygon([(cx, C(290)), (cx+C(62), mid), (cx, C(470)), (cx-C(62), mid)], fill=(235, 246, 255, 255))
    base = Image.alpha_composite(base, glow(lay, 24)); base = Image.alpha_composite(base, lay)
    finish(base, "icon")

concept_a()
