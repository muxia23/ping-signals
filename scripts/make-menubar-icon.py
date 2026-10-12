#!/usr/bin/env python3
"""Draws the monochrome menu bar icon (18 pt, 1x and 2x) into <out_dir>. Usage: scripts/make-menubar-icon.py <out_dir>"""
import sys
from PIL import Image, ImageDraw
out = sys.argv[1]
def draw(px):
    S = 16; N = px*S
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    u = N/18  # 18 pt canvas
    cx = N/2
    # ripple rings under the marker (flattened ellipses, open at the top behind the diamond)
    for rx, ry, w in [(8.2, 3.0, 1.3), (5.0, 1.8, 1.4)]:
        cy = 13.4*u
        d.ellipse([cx-rx*u, cy-ry*u, cx+rx*u, cy+ry*u], outline=(0, 0, 0, 255), width=int(w*u))
    # clear a gap around the diamond so it reads as standing on the rings
    top, mid, bot, hw = 1.0*u, 7.4*u, 13.6*u, 4.6*u
    g = 1.3*u
    d.polygon([(cx, top-g), (cx+hw+g, mid), (cx, bot+g), (cx-hw-g, mid)], fill=(0, 0, 0, 0))
    d.polygon([(cx, top), (cx+hw, mid), (cx, bot), (cx-hw, mid)], fill=(0, 0, 0, 255))
    # inner facet cut-out
    d.polygon([(cx, 4.4*u), (cx+1.9*u, mid), (cx, 10.4*u), (cx-1.9*u, mid)], fill=(0, 0, 0, 0))
    return im.resize((px, px), Image.LANCZOS)
draw(18).save(f"{out}/menubar.png"); draw(36).save(f"{out}/menubar@2x.png")
