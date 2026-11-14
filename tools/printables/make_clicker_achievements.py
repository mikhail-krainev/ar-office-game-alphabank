"""Pixel-art icons of the clicker achievements, one per achievement of server/content/clicker.json.

Usage:
    python tools/printables/make_clicker_achievements.py [--preview out.png]

Writes client/assets/ui/clicker_achievements.png: 32x32 icons in the order of the achievements in
clicker.json; row 0 in colour (received), row 1 grey (not yet). Every icon is drawn here from simple
shapes, then gets a dark outline, so the set matches the pixel art of the cat.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "server/content/clicker.json"
OUT = ROOT / "client/assets/ui/clicker_achievements.png"
SIZE = 32

OUTLINE = (40, 14, 20, 255)
RED = ((150, 20, 24, 255), (226, 38, 30, 255), (255, 110, 86, 255))
GOLD = ((176, 110, 20, 255), (246, 194, 60, 255), (255, 240, 160, 255))
SILVER = ((110, 116, 130, 255), (176, 184, 198, 255), (236, 240, 248, 255))
GREEN = ((26, 110, 60, 255), (46, 170, 90, 255), (140, 230, 160, 255))
BLUE = ((30, 60, 150, 255), (60, 120, 230, 255), (170, 210, 255, 255))
PURPLE = ((70, 30, 120, 255), (130, 70, 210, 255), (210, 170, 255, 255))
PINK = ((168, 71, 92, 255), (224, 122, 140, 255), (255, 179, 190, 255))
BROWN = ((90, 50, 24, 255), (140, 84, 40, 255), (200, 140, 80, 255))
DARK = ((14, 10, 24, 255), (36, 26, 60, 255), (70, 56, 110, 255))
WHITE = (255, 255, 255, 255)


class Icon:
    def __init__(self) -> None:
        self.img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def ellipse(self, box: tuple, palette: tuple, shade: bool = True) -> None:
        x0, y0, x1, y1 = box
        self.d.ellipse(box, fill=palette[1])
        if shade:
            w, h = x1 - x0, y1 - y0
            self.d.ellipse((x0 + w * 0.15, y0 + h * 0.1, x0 + w * 0.55, y0 + h * 0.45), fill=palette[2])
            self.d.arc(box, 20, 160, fill=palette[0], width=max(1, int(min(w, h) / 6)))

    def rect(self, box: tuple, palette: tuple, shade: bool = True) -> None:
        x0, y0, x1, y1 = box
        self.d.rectangle(box, fill=palette[1])
        if shade:
            self.d.rectangle((x0, y0, x1, y0 + max(0, (y1 - y0) // 4)), fill=palette[2])
            self.d.rectangle((x0, y1 - max(0, (y1 - y0) // 4), x1, y1), fill=palette[0])

    def poly(self, points: list, palette: tuple, tone: int = 1) -> None:
        self.d.polygon(points, fill=palette[tone])

    def px(self, x: int, y: int, color: tuple) -> None:
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.img.putpixel((x, y), color)

    def sparkle(self, x: int, y: int, size: int = 2) -> None:
        for k in range(-size, size + 1):
            self.px(x + k, y, WHITE)
            self.px(x, y + k, WHITE)

    def done(self) -> Image.Image:
        src = self.img
        out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        for y in range(SIZE):
            for x in range(SIZE):
                if src.getpixel((x, y))[3] == 0 and any(
                    0 <= x + dx < SIZE and 0 <= y + dy < SIZE and src.getpixel((x + dx, y + dy))[3] > 0
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                ):
                    out.putpixel((x, y), OUTLINE)
        return Image.alpha_composite(out, src)


def paw(icon: Icon, cx: int, cy: int, scale: float, palette: tuple) -> None:
    s = scale
    icon.ellipse((cx - 5 * s, cy - 2 * s, cx + 5 * s, cy + 6 * s), palette)
    for dx, dy in ((-6, -5), (-2, -8), (2, -8), (6, -5)):
        icon.ellipse((cx + (dx - 2) * s, cy + (dy - 2) * s, cx + (dx + 2) * s, cy + (dy + 2) * s), palette, shade=False)


def coin(icon: Icon, cx: int, cy: int, r: int = 5) -> None:
    icon.ellipse((cx - r, cy - r * 0.7, cx + r, cy + r * 0.7), GOLD)
    icon.d.line((cx - 1, cy - 1, cx + 1, cy - 1), fill=GOLD[0])


def stack(icon: Icon, cx: int, base: int, count: int) -> None:
    for i in range(count):
        y = base - i * 3
        icon.d.ellipse((cx - 6, y - 3, cx + 6, y + 3), fill=GOLD[0])
        icon.d.ellipse((cx - 6, y - 4, cx + 6, y + 2), fill=GOLD[1])
    icon.d.ellipse((cx - 4, base - (count - 1) * 3 - 3, cx + 2, base - (count - 1) * 3), fill=GOLD[2])


def cat_head(icon: Icon, body: tuple, ears: tuple, whiskers: tuple | None = None) -> None:
    icon.poly([(6, 14), (8, 3), (15, 10)], ears)
    icon.poly([(26, 14), (24, 3), (17, 10)], ears)
    icon.ellipse((5, 8, 27, 28), body)
    for cx in (11, 21):
        icon.d.arc((cx - 3, 15, cx + 3, 21), 200, 340, fill=OUTLINE, width=1)
    icon.px(16, 21, OUTLINE)
    icon.px(15, 22, OUTLINE)
    icon.px(17, 22, OUTLINE)
    if whiskers:
        for y in (21, 23):
            icon.d.line((1, y, 7, y), fill=whiskers)
            icon.d.line((25, y, 31, y), fill=whiskers)


def crown(icon: Icon, y: int, palette: tuple = GOLD) -> None:
    icon.poly([(7, y + 8), (7, y), (11, y + 4), (16, y - 2), (21, y + 4), (25, y), (25, y + 8)], palette)
    icon.rect((7, y + 6, 25, y + 9), palette)
    icon.px(16, y + 4, RED[1])
    icon.px(11, y + 6, BLUE[1])
    icon.px(21, y + 6, BLUE[1])


def arrow(icon: Icon, cx: int, top: int, palette: tuple) -> None:
    icon.poly([(cx, top), (cx + 6, top + 7), (cx + 2, top + 7), (cx + 2, top + 14), (cx - 2, top + 14), (cx - 2, top + 7), (cx - 6, top + 7)], palette)
    icon.d.line((cx - 1, top + 3, cx - 1, top + 12), fill=palette[2])


def star(icon: Icon, cx: int, cy: int, r: float, palette: tuple) -> None:
    points = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        points.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    icon.poly(points, palette)
    icon.poly(points[:3] + [(cx, cy)], palette, 2)


def draw(achievement_id: str) -> Image.Image:
    icon = Icon()
    d = icon.d
    builders: dict[str, Callable[[], None]] = {
        "taps_100": lambda: paw(icon, 16, 18, 1.2, PINK),
        "taps_1k": lambda: (paw(icon, 11, 22, 0.8, PINK), paw(icon, 21, 12, 0.8, PINK)),
        "taps_10k": lambda: (paw(icon, 16, 19, 1.2, RED), icon.ellipse((12, 18, 20, 24), PINK, shade=False)),
        "taps_100k": lambda: (paw(icon, 16, 19, 1.3, RED), icon.sparkle(4, 6), icon.sparkle(27, 26)),
        "taps_1m": lambda: (paw(icon, 16, 20, 1.3, GOLD), crown(icon, 1), icon.sparkle(4, 24)),
        "total_3": lambda: coin(icon, 16, 16, 9),
        "total_6": lambda: stack(icon, 16, 26, 4),
        "total_9": lambda: (stack(icon, 11, 27, 5), stack(icon, 22, 27, 3)),
        "total_12": lambda: (
            icon.ellipse((5, 10, 27, 30), BROWN),
            icon.rect((12, 5, 20, 10), BROWN),
            d.text((13, 14), "$", fill=GOLD[1]),
        ),
        "total_18": lambda: (
            icon.rect((4, 14, 28, 28), BROWN),
            icon.poly([(4, 14), (8, 7), (24, 7), (28, 14)], BROWN, 2),
            icon.rect((4, 13, 28, 15), GOLD, shade=False),
            icon.rect((14, 16, 18, 21), GOLD, shade=False),
            stack(icon, 16, 9, 1),
        ),
        "total_33": lambda: (
            icon.poly([(16, 29), (4, 13), (9, 6), (23, 6), (28, 13)], BLUE),
            icon.poly([(9, 6), (16, 13), (23, 6)], BLUE, 2),
            icon.poly([(4, 13), (16, 29), (16, 13)], BLUE, 0),
            icon.sparkle(25, 4),
        ),
        "total_50": lambda: (
            d.ellipse((3, 10, 17, 22), outline=PURPLE[1], width=3),
            d.ellipse((15, 10, 29, 22), outline=PURPLE[1], width=3),
            d.arc((3, 10, 17, 22), 200, 290, fill=PURPLE[2], width=1),
        ),
        "total_100": lambda: (
            icon.ellipse((8, 8, 24, 24), BLUE),
            d.arc((1, 12, 31, 21), 150, 390, fill=GOLD[1], width=2),
            icon.sparkle(4, 4, 1),
            icon.sparkle(28, 27, 1),
        ),
        "total_150": lambda: (star(icon, 16, 16, 13, GOLD), icon.sparkle(5, 26), icon.sparkle(27, 5, 1)),
        "total_200": lambda: (
            icon.ellipse((3, 3, 29, 29), DARK, shade=False),
            [icon.px(int(16 + (2 + t * 0.5) * math.cos(t * 0.55 + k * math.pi)), int(16 + (2 + t * 0.5) * math.sin(t * 0.55 + k * math.pi)), PURPLE[2] if t % 3 else WHITE) for k in (0, 1) for t in range(24)],
            icon.ellipse((13, 13, 19, 19), GOLD, shade=False),
        ),
        "total_250": lambda: (
            d.ellipse((2, 9, 30, 23), fill=(255, 140, 60, 255)),
            d.ellipse((4, 11, 28, 21), fill=(255, 210, 120, 255)),
            d.ellipse((9, 8, 23, 24), fill=(0, 0, 0, 255)),
            icon.sparkle(4, 4, 1),
        ),
        "total_300": lambda: (
            icon.ellipse((2, 2, 30, 30), PURPLE, shade=False),
            icon.ellipse((7, 7, 25, 25), BLUE, shade=False),
            icon.ellipse((11, 11, 21, 21), (WHITE, (255, 250, 200, 255), WHITE), shade=False),
            icon.sparkle(5, 6),
            icon.sparkle(26, 24),
            icon.sparkle(25, 6, 1),
        ),
        "gold_1": lambda: cat_head(icon, RED, GOLD),
        "gold_3": lambda: cat_head(icon, RED, GOLD, GOLD[2]),
        "gold_6": lambda: (cat_head(icon, RED, GOLD, GOLD[2]), crown(icon, -1)),
        "gold_9": lambda: (cat_head(icon, GOLD, GOLD, GOLD[2]), crown(icon, -1)),
        "gold_12": lambda: (cat_head(icon, GOLD, GOLD, WHITE), crown(icon, -1), icon.sparkle(3, 27), icon.sparkle(29, 27, 1), icon.sparkle(28, 12, 1)),
        "levels_10": lambda: arrow(icon, 16, 8, GREEN),
        "levels_100": lambda: (arrow(icon, 11, 12, GREEN), arrow(icon, 21, 6, GREEN)),
        "levels_500": lambda: (
            icon.rect((9, 4, 23, 20), DARK),
            icon.rect((4, 20, 28, 24), DARK),
            icon.rect((9, 16, 23, 18), RED, shade=False),
            coin(icon, 24, 27, 4),
        ),
        "levels_1000": lambda: (
            icon.ellipse((7, 3, 25, 19), GOLD),
            icon.rect((14, 18, 18, 24), GOLD),
            icon.rect((9, 24, 23, 28), GOLD),
            d.arc((1, 5, 11, 15), 90, 270, fill=GOLD[0], width=2),
            d.arc((21, 5, 31, 15), 270, 450, fill=GOLD[0], width=2),
        ),
        "combo_max": lambda: (icon.poly([(19, 2), (7, 18), (15, 18), (11, 30), (25, 12), (17, 12)], GOLD), icon.poly([(19, 2), (7, 18), (13, 15)], GOLD, 2)),
        "offline_6": lambda: (
            icon.ellipse((5, 5, 27, 27), GOLD),
            d.ellipse((11, 2, 31, 22), fill=(0, 0, 0, 0)),
            d.text((20, 18), "z", fill=BLUE[2]),
            d.text((25, 12), "z", fill=BLUE[2]),
        ),
        "offline_30": lambda: (
            icon.rect((4, 11, 28, 28), BROWN),
            icon.rect((12, 6, 20, 11), BROWN, shade=False),
            d.rectangle((14, 8, 18, 10), fill=(0, 0, 0, 0)),
            icon.rect((4, 17, 28, 19), BROWN, shade=False),
            icon.rect((14, 16, 18, 21), GOLD, shade=False),
        ),
    }
    if achievement_id not in builders:
        raise SystemExit(f"no icon for achievement {achievement_id!r}: add one to {Path(__file__).name}")
    builders[achievement_id]()
    return icon.done()


def grey(image: Image.Image) -> Image.Image:
    out = Image.new("RGBA", image.size)
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = image.getpixel((x, y))
            v = int((0.3 * r + 0.59 * g + 0.11 * b) * 0.55 + 70)
            out.putpixel((x, y), (v, v, v, a))
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    ids = [a["id"] for a in json.loads(CONTENT.read_text(encoding="utf-8"))["achievements"]]
    sheet = Image.new("RGBA", (SIZE * len(ids), SIZE * 2), (0, 0, 0, 0))
    for i, achievement_id in enumerate(ids):
        icon = draw(achievement_id)
        sheet.paste(icon, (i * SIZE, 0))
        sheet.paste(grey(icon), (i * SIZE, SIZE))
    sheet.save(OUT)
    print("wrote", OUT.relative_to(ROOT), len(ids), "icons")
    if args.preview:
        cols = 10
        rows = math.ceil(len(ids) / cols)
        preview = Image.new("RGBA", (cols * 36, rows * 36 + 36), (251, 250, 248, 255))
        for i in range(len(ids)):
            preview.alpha_composite(sheet.crop((i * SIZE, 0, i * SIZE + SIZE, SIZE)), ((i % cols) * 36 + 2, (i // cols) * 36 + 2))
        for i in range(min(cols, len(ids))):
            preview.alpha_composite(sheet.crop((i * SIZE, SIZE, i * SIZE + SIZE, SIZE * 2)), (i * 36 + 2, rows * 36 + 2))
        preview.resize((preview.width * 3, preview.height * 3), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
