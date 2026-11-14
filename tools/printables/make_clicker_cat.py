"""Pixel-art lucky cat of the clicker: a red waving cat with a gold collar and a coin, drawn here.

Usage:
    python tools/printables/make_clicker_cat.py [--preview out.png]

Writes client/assets/ui/clicker_cat.png: 13 rows (gold level 0..12) by 4 frames of the waving paw
(the game plays them 0-1-2-3-2-1), each 128x128. Every rebirth turns one more part of the cat gold
(content/clicker.json "gold"): ears, whiskers, the waving paw, feet, tail, crown, patterns, arms,
head, body, shine, cosmos.

Each part is a simple 3D shape (ellipsoid, tube, disc). Its normal gives the light from the top
left, a bounce light from the rug and a glint; the light is quantised into a five-tone palette with
ordered dithering, parts in front cast a one-tone shadow, and the outline takes the darkest tone of
its part (dark red, dark gold) instead of plain black. Face, paw pads, coin letter, whiskers and
the crown are drawn over by hand.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/ui/clicker_cat.png"
FRAME = 128
FRAMES = 4
LEVELS = 13
OX, OY = 16, 12  # cat origin inside the frame: room for the crown, whiskers and sparkles


def rgb(hex_color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = hex_color.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


# Five tones dark -> light, then the outline and the glint.
RED = [rgb(c) for c in ("#6e1019", "#a3161d", "#d02520", "#ef4130", "#ff7a5c")]
RED_LINE = rgb("#2e070d")
RED_GLINT = rgb("#ffc4ad")
GOLD = [rgb(c) for c in ("#7a4209", "#b06e14", "#e09c2a", "#f8cd4e", "#fff0a6")]
GOLD_LINE = rgb("#3f2004")
GOLD_GLINT = rgb("#ffffff")
INK = rgb("#2a0b10")
EAR_IN = [rgb("#2c0e14"), rgb("#4a1820"), rgb("#6e2a30")]
PAD = [rgb("#a8475c"), rgb("#e07a8c"), rgb("#ffb3be")]
BLUSH = rgb("#ff8f86")
WHISKER = rgb("#fff1e4")
NOSE = [rgb("#3a1216"), rgb("#7c3a42")]
LETTER = [rgb("#6f120e"), rgb("#d3261c"), rgb("#ff6e52")]
GEMS = {"ruby": (rgb("#8e0f1c"), rgb("#ff3a4a"), rgb("#ffc0c6")), "sapphire": (rgb("#123a8c"), rgb("#3a8cff"), rgb("#c6e2ff"))}
STAR = rgb("#ffffff")
COSMIC = rgb("#8ff0ff")
AURA = (rgb("#b45cff", 170), rgb("#7a4cff", 90))

LIGHT = (-0.55, -0.7, 0.75)
BOUNCE = (0.35, 0.8, 0.3)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# Parts, front to back: a pixel keeps the first part that claims it.
# The waving arm is in front of the collar and the whiskers: it never passes through them.
ORDER = ["coin", "paw_up", "arm_up", "collar", "paw_side", "foot_l", "foot_r", "head", "ear_l", "ear_r", "body", "tail"]
GOLD_PARTS = {
    1: {"ear_l", "ear_r"},
    3: {"paw_up"},
    4: {"foot_l", "foot_r", "paw_side"},
    5: {"tail"},
    8: {"arm_up"},
    9: {"head"},
    10: {"body"},
}
ALWAYS_GOLD = {"coin", "collar"}
# Waving paw: centre of the paw per frame (up -> bent forward).
PAWS = [(78.0, 38.0), (80.0, 40.5), (81.5, 43.5), (82.5, 46.5)]
# The waving arm grows from a round shoulder on the body.
SHOULDER = (66.0, 72.0)
COIN = (43.0, 84.0)


def norm(v: tuple) -> tuple:
    length = math.sqrt(sum(c * c for c in v))
    return tuple(c / length for c in v)


L = norm(LIGHT)
B = norm(BOUNCE)
H = norm((L[0], L[1], L[2] + 1.0))


def ellipsoid(x: float, y: float, cx: float, cy: float, rx: float, ry: float) -> tuple | None:
    nx, ny = (x - cx) / rx, (y - cy) / ry
    d = nx * nx + ny * ny
    if d > 1.0:
        return None
    return (nx, ny, math.sqrt(1.0 - d))


def tube(x: float, y: float, a: tuple, b: tuple, r: float, r_end: float | None = None) -> tuple | None:
    """A tube from a to b, its radius going from r to r_end (the same when omitted)."""
    ax, ay = a
    dx, dy = b[0] - ax, b[1] - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    px, py = x - (ax + t * dx), y - (ay + t * dy)
    r = r + ((r if r_end is None else r_end) - r) * t
    d = math.hypot(px, py) / r
    if d > 1.0:
        return None
    return (px / r, py / r, math.sqrt(max(0.0, 1.0 - d * d)))


def triangle(x: float, y: float, a: tuple, b: tuple, c: tuple) -> bool:
    def side(p: tuple, q: tuple) -> float:
        return (x - q[0]) * (p[1] - q[1]) - (p[0] - q[0]) * (y - q[1])

    d1, d2, d3 = side(a, b), side(b, c), side(c, a)
    return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


def ear(x: float, y: float, tip: tuple, base_a: tuple, base_b: tuple) -> tuple | None:
    if not triangle(x, y, tip, base_a, base_b):
        return None
    cx = (tip[0] + base_a[0] + base_b[0]) / 3.0
    cy = (tip[1] + base_a[1] + base_b[1]) / 3.0 + 3.0
    nx, ny = (x - cx) / 13.0, (y - cy) / 16.0
    return norm((nx, ny, 1.0))


def head(x: float, y: float) -> tuple | None:
    n = ellipsoid(x, y, 45, 39, 33, 26)
    if n:
        return n
    # Fluffy cheek tufts.
    for tri in (((11, 41), (19, 37), (18, 48)), ((10, 50), (18, 46), (20, 55)), ((79, 41), (71, 37), (72, 48)), ((80, 50), (72, 46), (70, 55))):
        if triangle(x, y, *tri):
            return norm(((x - 45) / 30.0, (y - 42) / 26.0, 0.35))
    return None


COLLAR_HALF_WIDTH = 21.0


def collar_centre(x: float) -> float:
    """The collar runs just under the chin, so it sits on the neck."""
    return 39.0 + 26.0 * math.sqrt(max(0.0, 1.0 - ((x - 45.0) / 33.0) ** 2)) + 0.6


def collar(x: float, y: float) -> tuple | None:
    side = (x - 45.0) / COLLAR_HALF_WIDTH
    if abs(side) > 1.0:
        return None
    # Thinner towards the ends: the band turns round the neck.
    half = 3.8 * math.sqrt(1.0 - side ** 4)
    t = (y - collar_centre(x)) / max(half, 0.1)
    if abs(t) > 1.0:
        return None
    return norm((side * 1.4, t, math.sqrt(1.0 - t * t) * math.sqrt(max(0.0, 1.0 - side * side)) + 0.15))


def coin(x: float, y: float) -> tuple | None:
    cx, cy = COIN
    radius = 13.5
    d = math.hypot(x - cx, y - cy)
    if d > radius:
        return None
    if d > radius - 2.6:  # bevelled rim
        k = (d - (radius - 2.6)) / 2.6
        return norm(((x - cx) / d * k, (y - cy) / d * k, 1.0 - 0.5 * k))
    if d > radius - 4.2:  # groove inside the rim
        return norm((-(x - cx) / d * 0.6, -(y - cy) / d * 0.6, 0.6))
    return norm(((x - cx) / 40.0, (y - cy) / 40.0, 1.0))


def parts_at(x: float, y: float, frame: int) -> tuple[str, tuple] | None:
    paw = PAWS[frame]
    tests = (
        ("coin", lambda: coin(x, y)),
        ("paw_up", lambda: ellipsoid(x, y, paw[0], paw[1], 10.0, 11.0)),
        ("arm_up", lambda: tube(x, y, SHOULDER, (paw[0] - 1.0, paw[1] + 7.0), 9.6, 7.2)),
        ("collar", lambda: collar(x, y)),
        ("paw_side", lambda: ellipsoid(x, y, 17, 80, 8.6, 9.2)),
        ("foot_l", lambda: ellipsoid(x, y, 33, 104, 9.6, 6.8)),
        ("foot_r", lambda: ellipsoid(x, y, 59, 104, 9.6, 6.8)),
        ("head", lambda: head(x, y)),
        ("ear_l", lambda: ear(x, y, (18.5, 2.0), (12.0, 31.0), (38.0, 17.0))),
        ("ear_r", lambda: ear(x, y, (71.5, 2.0), (78.0, 31.0), (52.0, 17.0))),
        ("body", lambda: ellipsoid(x, y, 45, 85, 31, 25)),
        ("tail", lambda: tube(x, y, (68.0, 100.0), (85.0, 88.0), 5.0) or ellipsoid(x, y, 86, 81, 5.2, 7.5)),
    )
    for name, test in tests:
        n = test()
        if n:
            return name, n
    return None


def ear_inner(x: float, y: float) -> float:
    """0 outside the inner ear, else depth 1 (rim) .. 3 (deep)."""
    for tip, a, b in (((19.5, 7.0), (16.0, 27.0), (33.0, 18.0)), ((70.5, 7.0), (74.0, 27.0), (57.0, 18.0))):
        if triangle(x, y, tip, a, b):
            return 1.0 + 2.0 * max(0.0, min(1.0, (y - 7.0) / 18.0))
    return 0.0


def gold_set(level: int) -> set[str]:
    parts = set(ALWAYS_GOLD)
    for at, names in GOLD_PARTS.items():
        if level >= at:
            parts |= names
    return parts


def dot(a: tuple, b: tuple) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def shoulder_seam(front: str, back: str, x: int, y: int) -> bool:
    """No line where the arm grows out of the body: the shoulder is one rounded shape."""
    return front == "arm_up" and back == "body" and math.hypot(x - SHOULDER[0], y - SHOULDER[1] - 2.0) < 11.5


class Canvas:
    def __init__(self) -> None:
        self.img = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        # Pixels of the waving arm and its outline: details drawn later (face, blush, whiskers,
        # collar studs) stay behind it.
        self.arm: set[tuple[int, int]] = set()

    def put(self, x: float, y: float, color: tuple, over_arm: bool = False) -> None:
        if not over_arm and (int(round(x)), int(round(y))) in self.arm:
            return
        px, py = int(round(OX + x)), int(round(OY + y))
        if 0 <= px < FRAME and 0 <= py < FRAME:
            self.img.putpixel((px, py), color)

    def get(self, x: int, y: int) -> tuple:
        px, py = OX + x, OY + y
        if 0 <= px < FRAME and 0 <= py < FRAME:
            return self.img.getpixel((px, py))
        return (0, 0, 0, 0)


def render_body(canvas: Canvas, frame: int, golden: set[str]) -> dict:
    parts: dict = {}
    for y in range(-6, 116):
        for x in range(-8, 104):
            hit = parts_at(x + 0.5, y + 0.5, frame)
            if hit:
                parts[(x, y)] = hit
    for (x, y), (name, n) in parts.items():
        gold = name in golden
        palette = GOLD if gold else RED
        light = max(0.0, dot(n, L))
        bounce = max(0.0, dot(n, B))
        value = 0.25 + 0.95 * light + 0.35 * bounce * (1.0 - light)
        if name == "head" and ellipsoid(x + 0.5, y + 0.5, 45, 50, 10, 5.5):
            value += 0.25  # lighter muzzle
        # A part in front casts a shadow down and to the right.
        for sx, sy in ((-1, -2), (-2, -3), (0, -2)):
            other = parts.get((x + sx, y + sy))
            if other and ORDER.index(other[0]) < ORDER.index(name) and other[0] != "collar":
                value -= 0.28
                break
        threshold = (BAYER[y % 4][x % 4] + 0.5) / 16.0
        tone = int(max(0.0, min(4.0, value * 4.0 - 0.6 + (threshold - 0.5) * 0.45)) + 0.0)
        tone = max(0, min(4, tone))
        color = palette[tone]
        if dot(n, H) > (0.994 if gold else 0.997) and name not in ("coin",):
            color = GOLD_GLINT if gold else RED_GLINT
        if name in ("ear_l", "ear_r"):
            depth = ear_inner(x + 0.5, y + 0.5)
            if depth:
                color = EAR_IN[max(0, min(2, int(3.2 - depth)))]
                # Light fur strands from the base of the ear.
                if depth > 2.2 and (x * 3 + y) % 7 == 0:
                    color = palette[2]
        canvas.put(x, y, color)
    # Outline: dark tone of the part around the silhouette and in front of the parts behind it.
    for (x, y), (name, _n) in parts.items():
        line = GOLD_LINE if name in golden else RED_LINE
        inner = (GOLD if name in golden else RED)[0]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            other = parts.get((x + dx, y + dy))
            if other is None:
                canvas.put(x + dx, y + dy, line)
            elif other[0] != name and ORDER.index(name) < ORDER.index(other[0]) and name != "collar" and not (name == "head" and other[0] in ("ear_l", "ear_r", "body")) and not shoulder_seam(name, other[0], x, y):
                canvas.put(x + dx, y + dy, inner if name != "coin" else GOLD_LINE)
    for (x, y), (name, _n) in parts.items():
        if name in ("arm_up", "paw_up"):
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    canvas.arm.add((x + dx, y + dy))
    return parts


def draw_face(canvas: Canvas, golden_head: bool) -> None:
    # Happy closed eyes: thick arcs with a small lash at the outer end.
    for cx, outer in ((31, -1), (59, 1)):
        for dx in range(-6, 7):
            dy = round(dx * dx / 9.0) - 3
            canvas.put(cx + dx, 38 + dy, INK)
            if abs(dx) < 5:
                canvas.put(cx + dx, 37 + dy, INK)
        canvas.put(cx + 7 * outer, 39, INK)
        canvas.put(cx + 8 * outer, 40, INK)
    # Blush, dithered.
    if not golden_head:
        for cx in (23, 67):
            for y in range(44, 49):
                for x in range(cx - 5, cx + 6):
                    inside = ((x - cx) / 5.5) ** 2 + ((y - 46.5) / 2.6) ** 2
                    if inside <= 0.55 or (inside <= 1.0 and (x + y) % 2 == 0):
                        canvas.put(x, y, BLUSH)
    # Nose with a glint.
    for y, (a, b) in enumerate(((42, 48), (43, 47), (44, 46), (45, 45))):
        for x in range(a, b + 1):
            canvas.put(x, 46 + y, NOSE[0])
    canvas.put(43, 46, NOSE[1])
    canvas.put(44, 46, NOSE[1])
    # Mouth "w" with a small pink tongue.
    canvas.put(45, 50, INK)
    canvas.put(45, 51, INK)
    for x, y in ((44, 52), (43, 53), (42, 53), (41, 53), (40, 52), (46, 52), (47, 53), (48, 53), (49, 53), (50, 52)):
        canvas.put(x, y, INK)
    for x in (44, 45, 46):
        canvas.put(x, 54, PAD[1])
    canvas.put(45, 55, PAD[0])
    # Whisker roots.
    for x, y in ((35, 49), (33, 51), (36, 52), (55, 49), (57, 51), (54, 52)):
        canvas.put(x, y, RED[0] if not golden_head else GOLD[1])


def draw_whiskers(canvas: Canvas, golden: bool) -> None:
    """Whiskers go behind the waving arm (Canvas.arm)."""
    color = GOLD[4] if golden else WHISKER
    for y0, bend in ((47, -0.10), (50, 0.0), (53, 0.10)):
        for i in range(17):
            dy = bend * i + 0.004 * i * i
            canvas.put(18 - i, y0 + dy, color)
            canvas.put(72 + i, y0 + dy, color)


def draw_paw_pads(canvas: Canvas, frame: int) -> None:
    px, py = PAWS[frame]
    for x in range(int(px) - 6, int(px) + 7):
        for y in range(int(py) - 1, int(py) + 9):
            d = ((x + 0.5 - px) / 4.4) ** 2 + ((y + 0.5 - py - 4.0) / 3.4) ** 2
            if d <= 1.0:
                canvas.put(x, y, PAD[2] if d < 0.3 and y < py + 4 else (PAD[1] if d < 0.75 else PAD[0]), over_arm=True)
    for bx, by in ((-5.0, -3.5), (0.0, -6.0), (5.0, -3.5)):
        for x in range(int(px + bx) - 3, int(px + bx) + 4):
            for y in range(int(py + by) - 3, int(py + by) + 4):
                d = ((x + 0.5 - px - bx) / 2.1) ** 2 + ((y + 0.5 - py - by) / 2.3) ** 2
                if d <= 1.0:
                    canvas.put(x, y, PAD[2] if d < 0.3 else (PAD[1] if d < 0.8 else PAD[0]), over_arm=True)


def draw_toes(canvas: Canvas, parts: dict, golden: set[str]) -> None:
    for name, cx, cy in (("foot_l", 33, 104), ("foot_r", 59, 104), ("paw_side", 17, 80)):
        line = (GOLD if name in golden else RED)[0]
        for dx in (-3, 3):
            for dy in range(2, 7):
                if parts.get((cx + dx, cy + dy), ("",))[0] == name:
                    canvas.put(cx + dx, cy + dy, line)


def draw_coin(canvas: Canvas) -> None:
    cx, cy = int(COIN[0]), int(COIN[1])
    shape = ["...###...", "...###...", "..##.##..", "..##.##..", ".##...##.", ".#######.", "##.....##", "##.....##", "##.....##"]
    top = cy - 8
    for j, row in enumerate(shape):
        for i, ch in enumerate(row):
            if ch == "#":
                canvas.put(cx - 4 + i + 1, top + j + 1, LETTER[0])
    for j, row in enumerate(shape):
        for i, ch in enumerate(row):
            if ch == "#":
                left_edge = i == 0 or row[i - 1] != "#"
                canvas.put(cx - 4 + i, top + j, LETTER[2] if left_edge and j < 7 else LETTER[1])
    for i in range(-1, 10):
        canvas.put(cx - 4 + i + 1, top + 13, LETTER[0])
        canvas.put(cx - 4 + i, top + 11, LETTER[2] if i == -1 else LETTER[1])
        canvas.put(cx - 4 + i, top + 12, LETTER[1])
    # Glint on the rim.
    gx, gy = cx - 9, cy - 8
    for dx, dy in ((0, 0), (1, -1), (-1, 1), (1, 1), (0, 2), (0, -2), (-2, 0), (2, 0)):
        canvas.put(gx + dx, gy + dy, GOLD_GLINT if abs(dx) + abs(dy) <= 1 or (dx, dy) == (1, -1) else GOLD[4])


def draw_bail(canvas: Canvas, parts: dict) -> None:
    """The loop that hangs the coin on the collar."""
    cx = int(COIN[0])
    top = int(collar_centre(cx)) + 1
    for y in range(top, top + 4):
        for x in range(cx - 2, cx + 3):
            if parts.get((x, y), ("",))[0] == "coin":
                continue
            edge = x in (cx - 2, cx + 2) or y == top + 3
            canvas.put(x, y, GOLD_LINE if edge else (GOLD[4] if x == cx - 1 else GOLD[2]))


def draw_collar_studs(canvas: Canvas, parts: dict) -> None:
    for x in range(28, 64, 6):
        y = round(collar_centre(x + 0.5) - 0.5)
        if parts.get((x, y), ("",))[0] != "collar":
            continue
        canvas.put(x, y - 1, GOLD_GLINT)
        canvas.put(x, y, GOLD[4])
        canvas.put(x, y + 1, GOLD[1])


def draw_crown(canvas: Canvas) -> None:
    left, right, base = 31, 59, 12
    spikes = [(31, 6), (38, 2), (45, -1), (52, 2), (59, 6)]
    for x in range(left, right + 1):
        peak = max(min(sy + abs(x - sx) * 1.4 for sx, sy in spikes), base - 6)
        for y in range(int(peak), base + 1):
            tone = 4 if y < peak + 1.5 else (3 if x < 45 else 2)
            if y >= base - 1:
                tone = 1
            canvas.put(x, y, GOLD[tone])
        canvas.put(x, int(peak) - 1, GOLD_LINE)
        canvas.put(x, base + 1, GOLD_LINE)
    for sx, sy in spikes:
        canvas.put(sx, sy - 2, GOLD[4])
        canvas.put(sx, sy - 3, GOLD_LINE)
    canvas.put(left - 1, base, GOLD_LINE)
    canvas.put(right + 1, base, GOLD_LINE)
    for gx, kind in ((45, "ruby"), (37, "sapphire"), (53, "sapphire")):
        dark, mid, light = GEMS[kind]
        for x, y, c in ((gx - 1, 7, mid), (gx, 7, mid), (gx + 1, 7, dark), (gx - 1, 8, mid), (gx, 8, dark), (gx + 1, 8, dark), (gx, 6, mid), (gx, 9, dark)):
            canvas.put(x, y, c)
        canvas.put(gx - 1, 7, light)


def draw_patterns(canvas: Canvas, parts: dict) -> None:
    """Gold flame marks on the forehead and swirls on the flanks."""
    flame = [(45, 16), (45, 17), (44, 18), (45, 18), (46, 18), (44, 19), (45, 19), (46, 19), (45, 20)]
    for side in (-1, 1):
        flame += [(45 + side * 6, 19), (45 + side * 6, 20), (45 + side * 7, 21), (45 + side * 6, 21)]
    swirl = []
    for t in range(14):
        a = t / 13.0 * math.pi * 1.2
        swirl.append((round(19 + 5 * math.cos(a)), round(90 - 6 * math.sin(a))))
        swirl.append((round(71 - 5 * math.cos(a)), round(90 - 6 * math.sin(a))))
    for x, y in flame + swirl:
        if parts.get((x, y), ("",))[0] in ("head", "body"):
            canvas.put(x, y, GOLD[3])
            if parts.get((x, y + 1), ("",))[0] in ("head", "body") and (x, y + 1) not in flame + swirl:
                canvas.put(x, y + 1, GOLD[1])


def sparkle(img: Image.Image, x: int, y: int, size: int) -> None:
    for k in range(-size, size + 1):
        for px, py in ((x + k, y), (x, y + k)):
            if 0 <= px < FRAME and 0 <= py < FRAME:
                alpha = 255 if abs(k) < size else 120
                img.putpixel((px, py), (255, 255, 255, alpha))
    for px, py in ((x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1)):
        if size > 2 and 0 <= px < FRAME and 0 <= py < FRAME:
            img.putpixel((px, py), (255, 240, 170, 160))


def aura(img: Image.Image) -> Image.Image:
    glow = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    alpha = [[img.getpixel((x, y))[3] > 0 for x in range(FRAME)] for y in range(FRAME)]
    for y in range(FRAME):
        for x in range(FRAME):
            if alpha[y][x]:
                continue
            near = min(
                (abs(dx) + abs(dy) for dx in range(-3, 4) for dy in range(-3, 4) if 0 <= x + dx < FRAME and 0 <= y + dy < FRAME and alpha[y + dy][x + dx]),
                default=9,
            )
            if near <= 1:
                glow.putpixel((x, y), AURA[0])
            elif near <= 3 and (x + y) % 2 == 0:
                glow.putpixel((x, y), AURA[1])
    return Image.alpha_composite(glow, img)


def frame_image(level: int, frame: int) -> Image.Image:
    canvas = Canvas()
    golden = gold_set(level)
    parts = render_body(canvas, frame, golden)
    draw_toes(canvas, parts, golden)
    draw_paw_pads(canvas, frame)
    draw_bail(canvas, parts)
    draw_coin(canvas)
    draw_collar_studs(canvas, parts)
    draw_face(canvas, "head" in golden)
    draw_whiskers(canvas, level >= 2)
    if level >= 6:
        draw_crown(canvas)
    if level >= 7:
        draw_patterns(canvas, parts)
    img = canvas.img
    if level >= 12:
        for (x, y), (name, _n) in parts.items():
            if name in ("head", "body", "arm_up", "tail") and (x * 7 + y * 13 + frame * 5) % 53 == 0:
                canvas.put(x, y, COSMIC if (x + y) % 3 else STAR, over_arm=True)
        img = aura(canvas.img)
    if level >= 11:
        spots = [(10, 22), (114, 30), (8, 92), (118, 98), (100, 8), (22, 118)]
        for i, (x, y) in enumerate(spots):
            phase = (i + frame) % 4
            if phase != 3:
                sparkle(img, x, y, (1, 2, 3)[phase])
    return img


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    sheet = Image.new("RGBA", (FRAME * FRAMES, FRAME * LEVELS), (0, 0, 0, 0))
    frames = {}
    for level in range(LEVELS):
        for frame in range(FRAMES):
            frames[(level, frame)] = frame_image(level, frame)
            sheet.paste(frames[(level, frame)], (frame * FRAME, level * FRAME))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT)
    print("wrote", OUT.relative_to(ROOT))
    if args.preview:
        cols = 5
        preview = Image.new("RGBA", (FRAME * cols, FRAME * 4), (27, 20, 32, 255))
        shots = [(level, 0) for level in range(LEVELS)] + [(0, f) for f in range(1, FRAMES)] + [(12, 2)]
        for i, key in enumerate(shots[: cols * 4]):
            preview.alpha_composite(frames[key], ((i % cols) * FRAME, (i // cols) * FRAME))
        preview.resize((preview.width * 2, preview.height * 2), Image.NEAREST).save(args.preview)


if __name__ == "__main__":
    main()
