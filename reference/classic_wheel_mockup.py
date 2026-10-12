import sys
from PIL import Image, ImageEnhance
atlas = Image.open(sys.argv[1]).convert("RGBA"); out = sys.argv[2]
crop = lambda x, y, w, h: atlas.crop((x, y, x + w, y + h))
R = 142; C = 160; N = 2 * C
quarter = crop(1, 1, 142, 142)                 # top-left quadrant, its bottom-right corner = wheel centre
wedge_top = crop(169, 145, 166, 115)           # highlighted top wedge
wedge_side = crop(172, 263, 115, 166)          # highlighted side wedge
disc = crop(373, 228, 135, 135); shadow = crop(371, 371, 140, 140)
center = crop(0, 426, 86, 86); xbtn = crop(96, 448, 60, 60)
icons = {"N": crop(467, 70, 26, 52), "E": crop(389, 70, 54, 52), "S": crop(464, 6, 46, 52), "W": crop(400, 6, 32, 52)}

def paste_c(canvas, im, cx, cy):
    canvas.alpha_composite(im, (round(cx - im.width / 2), round(cy - im.height / 2)))

def wheel(hot=None):
    c = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    bg = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    paste_c(bg, shadow.resize((2 * R + 8, 2 * R + 8)), C, C + 3)
    d = ImageEnhance.Brightness(disc.resize((2 * R, 2 * R))).enhance(0.28)
    paste_c(bg, d, C, C)
    c.alpha_composite(bg)
    if hot == "N": paste_c(c, wedge_top, C, C - R + wedge_top.height / 2 + 4)
    if hot == "S": paste_c(c, wedge_top.rotate(180), C, C + R - wedge_top.height / 2 - 4)
    if hot == "W": paste_c(c, wedge_side, C - R + wedge_side.width / 2 + 4, C)
    if hot == "E": paste_c(c, wedge_side.transpose(Image.FLIP_LEFT_RIGHT), C + R - wedge_side.width / 2 - 4, C)
    for k, rot in ((0, 0), (1, -90), (2, 180), (3, 90)):
        q = quarter.rotate(rot)
        ox, oy = [(C - R, C - R), (C, C - R), (C, C), (C - R, C)][k]
        c.alpha_composite(q, (ox, oy))
    paste_c(c, center, C, C); paste_c(c, xbtn, C, C)
    r_icon = R * 0.62
    for k, (dx, dy) in {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}.items():
        paste_c(c, icons[k], C + dx * r_icon, C + dy * r_icon)
    return c

states = [None, "N", "E", "S", "W"]
sheet = Image.new("RGBA", (N * 5, N), (58, 74, 66, 255))
for i, s in enumerate(states): sheet.alpha_composite(wheel(s), (i * N, 0))
sheet.save(out)
