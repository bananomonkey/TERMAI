#!/usr/bin/env python3
"""Генератор иконки TERMAI: ЭЛТ-монитор с зелёным экраном, пиксельными
глазами и улыбкой-треугольником. Запуск из mobile/:  python3 tool/make_icon.py
"""
import math
import random
from PIL import Image, ImageDraw

W = 1024
GREEN = (46, 139, 61, 255)
BODY = (72, 72, 72, 255)
BODY_DARK = (44, 44, 44, 255)
BODY_LIGHT = (92, 92, 92, 255)
SCREEN_BEZEL = (26, 26, 26, 255)
BLACK = (8, 8, 8, 255)


def rounded(draw, box, r, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def draw_monitor(size, transparent=False, scale=0.92, disc=False):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0) if transparent else (10, 10, 10, 255))
    d = ImageDraw.Draw(img)

    if disc:
        # круглая подложка: иконка читается круглой даже под squircle-маской
        r = size * 0.455
        c = size / 2
        d.ellipse([c - r, c - r, c + r, c + r],
                  fill=(34, 26, 21, 255), outline=(120, 86, 66, 255),
                  width=max(3, size // 90))
        r2 = r - size * 0.018
        d.ellipse([c - r2, c - r2, c + r2, c + r2],
                  outline=(74, 56, 43, 255), width=max(2, size // 220))

    margin = int(size * (1 - scale) / 2)
    x0, y0 = margin, margin
    x1, y1 = size - margin, size - margin

    # корпус
    rounded(d, (x0, y0, x1, y1), int(size * 0.055), BODY, BODY_DARK, max(4, size // 110))
    rounded(d, (x0 + size * 0.018, y0 + size * 0.014, x1 - size * 0.018, y0 + size * 0.10),
            int(size * 0.03), BODY_LIGHT)
    rounded(d, (x0 + size * 0.018, y0 + size * 0.03, x1 - size * 0.018, y0 + size * 0.075),
            int(size * 0.03), BODY)

    # внутренняя рамка
    bx0, by0 = x0 + size * 0.072, y0 + size * 0.078
    bx1, by1 = x1 - size * 0.072, y1 - size * 0.088
    rounded(d, (bx0, by0, bx1, by1), int(size * 0.045), BODY_DARK)
    rounded(d, (bx0 + size * 0.012, by0 + size * 0.012, bx1 - size * 0.012, by1 - size * 0.012),
            int(size * 0.038), SCREEN_BEZEL)

    # экран
    sx0, sy0 = bx0 + size * 0.030, by0 + size * 0.030
    sx1, sy1 = bx1 - size * 0.030, by1 - size * 0.030
    rounded(d, (sx0, sy0, sx1, sy1), int(size * 0.035), GREEN)
    sw, sh = int(sx1 - sx0), int(sy1 - sy0)

    # виньетка
    grad = Image.radial_gradient("L").resize((sw, sh))
    dark = Image.new("RGBA", (sw, sh), (10, 40, 14, 0))
    dark.putalpha(grad.point(lambda v: int(v * 0.55)))
    img.alpha_composite(dark, (int(sx0), int(sy0)))

    # сканлайны
    sl = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    sld = ImageDraw.Draw(sl)
    step = max(3, int(size * 0.006))
    for yy in range(0, sh, step):
        sld.line([(0, yy), (sw, yy)], fill=(0, 0, 0, 38), width=max(1, size // 700))
    img.alpha_composite(sl, (int(sx0), int(sy0)))

    # пиксельные глаза (круглая маска)
    def pixel_eye(cx, cy, radius):
        n = 11
        cell = radius * 0.20
        gap = cell * 0.26
        stepv = cell + gap
        for iy in range(n):
            for ix in range(n):
                px = cx + (ix - (n - 1) / 2) * stepv
                py = cy + (iy - (n - 1) / 2) * stepv
                if math.hypot(px - cx, py - cy) > radius * 0.88:
                    continue
                d.rectangle([px - cell / 2, py - cell / 2, px + cell / 2, py + cell / 2], fill=BLACK)

    eye_y = sy0 + sh * 0.42
    pixel_eye(sx0 + sw * 0.31, eye_y, sw * 0.145)
    pixel_eye(sx0 + sw * 0.69, eye_y, sw * 0.145)

    # улыбка: треугольная U/V из пикселей (края выше, центр ниже)
    cell = sw * 0.022
    gap = cell * 0.24
    stepv = cell + gap
    top_y = sy0 + sh * 0.73
    depth = sh * 0.050
    n = 11
    for i in range(n):
        t = i / (n - 1)
        x = sx0 + sw * (0.39 + 0.22 * t)
        y = top_y + depth * (1 - abs(2 * t - 1))
        d.rectangle([x - cell / 2, y - cell / 2, x + cell / 2, y + cell / 2], fill=BLACK)

    # винты
    def screw(cx, cy, r):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(34, 34, 34, 255),
                  outline=(22, 22, 22, 255), width=max(2, size // 300))
        d.ellipse([cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72],
                  fill=(62, 62, 62, 255))
        w = max(2, size // 220)
        d.line([cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42], fill=(24, 24, 24, 255), width=w)
        d.line([cx - r * 0.42, cy + r * 0.42, cx + r * 0.42, cy - r * 0.42], fill=(24, 24, 24, 255), width=w)

    s = size * 0.035
    screw(x0 + s * 1.1, y0 + s * 1.1, size * 0.028)
    screw(x1 - s * 1.1, y0 + s * 1.1, size * 0.028)
    screw(x0 + s * 1.1, y1 - s * 1.1, size * 0.028)
    screw(x1 - s * 1.1, y1 - s * 1.1, size * 0.028)

    # боковые ручки
    kw, kh = size * 0.028, size * 0.13
    for cx in (x0 - kw * 0.25, x1 + kw * 0.25):
        d.rounded_rectangle([cx - kw / 2, y0 + size * 0.42, cx + kw / 2, y0 + size * 0.42 + kh],
                            radius=kw * 0.28, fill=(58, 58, 58, 255),
                            outline=(26, 26, 26, 255), width=max(2, size // 340))
        for i in range(5):
            yy = y0 + size * 0.42 + kh * (0.18 + i * 0.16)
            d.line([cx - kw * 0.30, yy, cx + kw * 0.30, yy], fill=(36, 36, 36, 255),
                   width=max(1, size // 500))

    # царапины
    rnd = random.Random(7)
    for _ in range(9):
        x = rnd.uniform(x0 + size * 0.06, x1 - size * 0.12)
        y = rnd.uniform(y0 + size * 0.05, y1 - size * 0.08)
        ln = rnd.uniform(size * 0.02, size * 0.06)
        d.line([x, y, x + ln, y - ln * 0.35], fill=(150, 150, 150, 70), width=max(1, size // 600))
    return img


if __name__ == "__main__":
    draw_monitor(1024, transparent=True, scale=0.62, disc=True).convert("RGBA").save("assets/icon/termai.png")
    draw_monitor(1024, transparent=True, scale=0.62, disc=True).save("assets/icon/termai_fg.png")
    print("icons written")
