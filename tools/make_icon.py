#!/usr/bin/env python3
"""AimFind 应用图标生成器（纯标准库，不需要 Pillow）。

    python3 tools/make_icon.py

输出 1024×1024 不透明 PNG 到 AppIcon.appiconset/icon-1024.png。
iOS 图标**不能带透明通道**，所以背景铺满整张。想调整就改下面的常量，重跑一次即可。
"""

import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), os.pardir,
                   "Resources", "Assets", "AimFind-iOS.xcassets", "AppIcon.appiconset", "icon-1024.png")

# 颜色（0–255）
TOP = (14, 30, 27)          # 背景上端：墨绿黑
BOTTOM = (27, 58, 50)       # 背景下端：稍亮，给一点层次
FRAME = (243, 247, 245)     # 取景框与暗条码：近白
DIM = (108, 138, 130)       # 未命中的条码：灰绿
FOUND = (78, 216, 160)      # 命中的那一根：与 AccentColor 同族的亮绿

# 几何（单位 = 画布边长）
INSET = 0.185               # 取景框离边缘的距离
ARM = 0.145                 # 每条臂长
STROKE = 0.028              # 臂宽
FEATHER = 0.0045            # 边缘羽化，代替超采样做抗锯齿
BAR_TOP, BAR_BOTTOM = 0.372, 0.628
# 亮的那一根更宽、更高：它是"找到了"这件事的主角，不能只靠颜色赢
FOUND_TOP, FOUND_BOTTOM = 0.328, 0.672
BARS = [                    # (左边界, 宽度, 是否高亮)
    (0.338, 0.024, False),
    (0.390, 0.040, False),
    (0.472, 0.056, True),
    (0.556, 0.036, False),
    (0.622, 0.024, False),
]


def rect_alpha(x, y, box, feather=FEATHER):
    x0, y0, x1, y1 = box
    if x <= x0 - feather or x >= x1 + feather or y <= y0 - feather or y >= y1 + feather:
        return 0.0
    hx = max(0.0, min(1.0, (feather + min(x - x0, x1 - x)) / (2.0 * feather)))
    hy = max(0.0, min(1.0, (feather + min(y - y0, y1 - y)) / (2.0 * feather)))
    return hx * hy


def brackets(u, v):
    """四个 L 形取景角，返回覆盖度。"""
    x0, y0, x1, y1 = INSET, INSET, 1 - INSET, 1 - INSET
    arms = [
        (x0, y0, x0 + ARM, y0 + STROKE),          # 左上 横
        (x0, y0, x0 + STROKE, y0 + ARM),          # 左上 竖
        (x1 - ARM, y0, x1, y0 + STROKE),          # 右上 横
        (x1 - STROKE, y0, x1, y0 + ARM),          # 右上 竖
        (x0, y1 - STROKE, x0 + ARM, y1),          # 左下 横
        (x0, y1 - ARM, x0 + STROKE, y1),          # 左下 竖
        (x1 - ARM, y1 - STROKE, x1, y1),          # 右下 横
        (x1 - STROKE, y1 - ARM, x1, y1),          # 右下 竖
    ]
    total = 0.0
    for box in arms:
        total = max(total, rect_alpha(u, v, box))
    return total


def bar_mask(u, v):
    """返回 (暗条覆盖度, 亮条覆盖度)：亮条压在暗条之上。"""
    dim = found = 0.0
    for left, width, highlight in BARS:
        top, bottom = (FOUND_TOP, FOUND_BOTTOM) if highlight else (BAR_TOP, BAR_BOTTOM)
        a = rect_alpha(u, v, (left, top, left + width, bottom))
        if highlight:
            found = max(found, a)
        else:
            dim = max(dim, a)
    return dim, found


def paint(u, v):
    """自上而下的背景渐变 + 中心微亮，再按覆盖度叠加各图层。"""
    glow = 0.10 * max(0.0, 1.0 - ((u - 0.5) ** 2 + (v - 0.47) ** 2) / 0.13)
    color = [TOP[i] + (BOTTOM[i] - TOP[i]) * v + 255 * glow for i in range(3)]

    dim, found = bar_mask(u, v)
    for alpha, layer in ((dim, DIM), (brackets(u, v), FRAME), (found, FOUND)):
        if alpha > 0:
            color = [c + (lc - c) * alpha for c, lc in zip(color, layer)]
    return [int(max(0, min(255, round(c)))) for c in color]


def write_png(path, width, height, rows):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)


def main():
    step = 1.0 / SIZE
    rows = []
    for y in range(SIZE):
        v = (y + 0.5) * step
        row = bytearray()
        for x in range(SIZE):
            row += bytes(paint((x + 0.5) * step, v))
        rows.append(bytes(row))
    target = os.path.normpath(OUT)
    write_png(target, SIZE, SIZE, rows)
    print("wrote", target, os.path.getsize(target), "bytes")


if __name__ == "__main__":
    main()
