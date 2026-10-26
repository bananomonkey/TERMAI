#!/usr/bin/env python3
"""Иконка TERMAI: круглый зелёный экран с пиксельными глазами и улыбкой.
Без железной рамки, без ободка и без границ — только экран и лицо.
Запуск из mobile/:  python3 tool/make_icon.py
"""
import math
from PIL import Image, ImageChops, ImageDraw

GREEN = (46, 139, 61, 255)
BLACK = (8, 8, 8, 255)


def face_icon(size=1024, mouth_open=False):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = cy = size / 2
    r = size * 0.47
    box = [cx - r, cy - r, cx + r, cy + r]

    # зелёный экран — сам по себе круглая иконка, без рамки
    d.ellipse(box, fill=GREEN)

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse(box, fill=255)

    # мягкая виньетка по краям экрана (не граница, а глубина CRT)
    grad = Image.radial_gradient("L").resize((size, size))
    dark = Image.new("RGBA", (size, size), (8, 30, 12, 0))
    alpha = grad.point(lambda v: int(v * 0.45))
    dark.putalpha(ImageChops.multiply(alpha, mask))
    img.alpha_composite(dark)

    # сканлайны
    sl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sl)
    step = max(3, int(size * 0.006))
    for y in range(int(cy - r), int(cy + r), step):
        sd.line([(cx - r, y), (cx + r, y)], fill=(0, 0, 0, 34),
                width=max(1, size // 700))
    sl.putalpha(ImageChops.multiply(sl.getchannel("A"), mask))
    img.alpha_composite(sl)

    # пиксельные глаза
    def eye(ex, ey, radius):
        n = 11
        cell = radius * 0.20
        gap = cell * 0.26
        stepv = cell + gap
        for iy in range(n):
            for ix in range(n):
                px = ex + (ix - (n - 1) / 2) * stepv
                py = ey + (iy - (n - 1) / 2) * stepv
                if math.hypot(px - ex, py - ey) > radius * 0.88:
                    continue
                d.rectangle([px - cell / 2, py - cell / 2, px + cell / 2, py + cell / 2],
                            fill=BLACK)

    eye(cx - size * 0.175, cy - size * 0.04, size * 0.125)
    eye(cx + size * 0.175, cy - size * 0.04, size * 0.125)

    if mouth_open:
        # открытый рот: пиксельный овал, как кадр разговора
        cell = size * 0.022
        step = cell * 1.18
        cols, rows = 9, 5
        my = cy + size * 0.195
        for iy in range(rows):
            for ix in range(cols):
                nx = (ix - (cols - 1) / 2) / ((cols - 1) / 2)
                ny = (iy - (rows - 1) / 2) / ((rows - 1) / 2)
                if abs(nx) ** 2.6 + abs(ny) ** 2.0 > 1:
                    continue
                x = cx + (ix - (cols - 1) / 2) * step
                y = my + (iy - (rows - 1) / 2) * step
                d.rectangle(
                    [x - cell / 2, y - cell / 2, x + cell / 2, y + cell / 2],
                    fill=BLACK)
    else:
        # маленькая улыбка-треугольник (V)
        cell = size * 0.020
        top_y = cy + size * 0.155
        depth = size * 0.045
        n = 11
        for i in range(n):
            t = i / (n - 1)
            x = cx + size * (-0.105 + 0.21 * t)
            y = top_y + depth * (1 - abs(2 * t - 1))
            d.rectangle(
                [x - cell / 2, y - cell / 2, x + cell / 2, y + cell / 2],
                fill=BLACK)
    return img


if __name__ == "__main__":
    face_icon(1024).save("assets/icon/termai.png")
    face_icon(1024).save("assets/icon/termai_fg.png")
    face_icon(512, mouth_open=False).save("assets/icon/termai_closed.png")
    face_icon(512, mouth_open=True).save("assets/icon/termai_open.png")
    print("icons written")
