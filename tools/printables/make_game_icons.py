"""Pixel-art icons of the entertainment games, 24x24, drawn here.

Usage:
    python tools/printables/make_game_icons.py

Writes client/assets/ui/game_icons/<game>.png for the lounge menu and the open-rooms list: clicker
(lucky cat), blackjack (21), roulette, checkers, memory (Alfa pairs), defuse (bug bomb) and bug_hunt.
Each icon has its own dominant colour and a dark outline, so it reads on the paper buttons and on the
red primary one alike.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/ui/game_icons"
SIZE = 24

INK = (29, 29, 31, 255)
WHITE = (255, 255, 255, 255)
PAPER = (251, 250, 248, 255)
SHADE = (225, 219, 210, 255)
RED = (239, 49, 36, 255)
RED_DARK = (176, 30, 22, 255)
GOLD = (247, 201, 72, 255)
GOLD_DARK = (196, 140, 30, 255)
GREEN = (31, 154, 91, 255)
GREEN_DARK = (15, 90, 70, 255)
BLUE = (47, 111, 208, 255)
BLUE_DARK = (28, 66, 140, 255)
PURPLE = (142, 63, 209, 255)
PURPLE_DARK = (88, 34, 140, 255)
ORANGE = (224, 112, 31, 255)
WOOD = (74, 44, 27, 255)
BRASS = (229, 184, 92, 255)
PINK = (240, 150, 160, 255)


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def rect(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, color: tuple) -> None:
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def dots(draw: ImageDraw.ImageDraw, points: tuple, color: tuple, dx: int = 0, dy: int = 0) -> None:
    for x, y in points:
        rect(draw, x + dx, y + dy, 1, 1, color)


def disc(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, color: tuple) -> None:
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def clicker() -> Image.Image:
    """Lucky cat face: gold head, ears, closed happy eyes, pink nose."""
    image, d = canvas()
    for side in (1, -1):
        def x(v: float) -> float:
            return v if side == 1 else 23 - v

        d.polygon([(x(2), 12), (x(4), 0), (x(12), 7)], fill=INK)
        d.polygon([(x(4), 11), (x(5), 3), (x(10), 7)], fill=GOLD)
        d.polygon([(x(5), 8), (x(6), 5), (x(8), 7)], fill=PINK)
    disc(d, 11.5, 14, 10, INK)
    disc(d, 11.5, 14, 9, GOLD)
    rect(d, 4, 18, 16, 4, GOLD_DARK)  # cheek shade
    disc(d, 11.5, 15, 8, GOLD)
    dots(d, ((6, 12), (7, 11), (8, 11), (9, 12)), INK)  # ^ eye
    dots(d, ((14, 12), (15, 11), (16, 11), (17, 12)), INK)
    rect(d, 11, 15, 2, 1, PINK)
    dots(d, ((10, 17), (11, 16), (12, 16), (13, 17)), INK)  # mouth
    for y in (15, 17):
        rect(d, 2, y, 4, 1, INK)  # whiskers
        rect(d, 18, y, 4, 1, INK)
    return image


def blackjack() -> Image.Image:
    """Two fanned cards: a black spade ace behind a red king of hearts."""
    image, d = canvas()
    rect(d, 1, 3, 12, 17, INK)
    rect(d, 2, 4, 10, 15, WHITE)
    dots(d, ((4, 5), (3, 6), (5, 6), (3, 7), (4, 7), (5, 7), (3, 8), (5, 8)), INK)  # A
    d.polygon([(7, 10), (4, 14), (10, 14)], fill=INK)  # spade
    rect(d, 5, 13, 5, 2, INK)
    rect(d, 7, 15, 1, 2, INK)
    rect(d, 10, 5, 13, 18, INK)
    rect(d, 11, 6, 11, 16, WHITE)
    dots(d, ((12, 7), (12, 8), (12, 9), (12, 10), (13, 8), (14, 7), (14, 9), (15, 10)), RED)  # K
    rect(d, 14, 12, 2, 2, RED)  # heart
    rect(d, 17, 12, 2, 2, RED)
    rect(d, 13, 13, 7, 2, RED)
    rect(d, 14, 15, 5, 1, RED)
    rect(d, 15, 16, 3, 1, RED)
    rect(d, 16, 17, 1, 1, RED)
    return image


def roulette() -> Image.Image:
    """Wheel seen from above: red and black pockets, green zero, brass hub and the ball."""
    image, d = canvas()
    disc(d, 11.5, 11.5, 11.5, INK)
    disc(d, 11.5, 11.5, 10.5, WOOD)
    for i in range(12):
        color = GREEN if i == 0 else (RED if i % 2 else INK)
        d.pieslice([2, 2, 21, 21], i * 30 - 90, i * 30 - 60, fill=color)
    disc(d, 11.5, 11.5, 6, WOOD)
    disc(d, 11.5, 11.5, 5, BRASS)
    rect(d, 11, 7, 2, 10, GOLD_DARK)  # hub cross
    rect(d, 7, 11, 10, 2, GOLD_DARK)
    rect(d, 11, 11, 2, 2, WHITE)
    disc(d, 17.5, 4.5, 2, INK)  # ball
    disc(d, 17.5, 4.5, 1.2, WHITE)
    return image


def checkers() -> Image.Image:
    """Board corner with a stacked king and a single piece."""
    image, d = canvas()
    rect(d, 0, 12, 24, 12, INK)
    for row in range(3):
        for col in range(6):
            rect(d, 1 + col * 4 - (0 if row % 2 else 0), 13 + row * 4 - (1 if row == 2 else 0), 4, 4 if row < 2 else 3, WOOD if (row + col) % 2 else BRASS)
    for y, color, dark in ((14, RED, RED_DARK), (10, RED, RED_DARK), (6, RED, RED_DARK)):
        d.ellipse([1, y - 1, 13, y + 6], fill=INK)
        d.ellipse([2, y, 12, y + 5], fill=dark)
        d.ellipse([2, y - 1, 12, y + 4], fill=color)
    dots(d, ((5, 6), (7, 4), (9, 6)), GOLD)  # crown
    rect(d, 5, 7, 5, 1, GOLD)
    d.ellipse([12, 13, 23, 20], fill=INK)
    d.ellipse([13, 14, 22, 19], fill=PAPER)
    d.ellipse([13, 13, 22, 18], fill=WHITE)
    d.ellipse([15, 14, 20, 17], outline=SHADE)
    return image


def memory() -> Image.Image:
    """A face-down card and a turned one with the Alfa "A", like the pairs game."""
    image, d = canvas()
    rect(d, 1, 2, 11, 16, INK)
    rect(d, 2, 3, 9, 14, BLUE)
    rect(d, 3, 4, 7, 12, BLUE_DARK)
    for y in range(5, 15, 3):
        rect(d, 4, y, 5, 1, BLUE)
    rect(d, 11, 6, 12, 17, INK)
    rect(d, 12, 7, 10, 15, WHITE)
    d.polygon([(17, 9), (13, 18), (15, 18), (17, 13), (19, 18), (21, 18)], fill=RED)  # A
    rect(d, 14, 19, 7, 2, RED)
    return image


def defuse() -> Image.Image:
    """Round bomb with a lit fuse and a running timer."""
    image, d = canvas()
    disc(d, 10, 14, 9, INK)
    disc(d, 10, 14, 8, (60, 62, 72, 255))
    disc(d, 7, 11, 2.5, (120, 124, 136, 255))  # shine
    rect(d, 13, 3, 5, 5, INK)  # cap
    rect(d, 14, 4, 3, 3, (120, 124, 136, 255))
    dots(d, ((17, 2), (18, 1), (19, 1), (20, 2)), WOOD)  # fuse
    dots(d, ((21, 0), (22, 1), (20, 0), (22, 3), (23, 2)), GOLD)  # spark
    rect(d, 21, 1, 2, 2, ORANGE)
    rect(d, 4, 16, 13, 4, INK)  # timer display
    rect(d, 5, 17, 11, 2, (20, 40, 30, 255))
    dots(d, ((6, 17), (7, 18), (9, 17), (10, 18), (12, 17), (13, 18), (14, 17)), (90, 230, 120, 255))
    return image


def bug_hunt() -> Image.Image:
    """Green bug under a red crosshair."""
    image, d = canvas()
    for y in (9, 13, 17):
        rect(d, 3, y, 18, 1, INK)  # legs
    dots(d, ((8, 3), (7, 2), (15, 3), (16, 2)), INK)  # antennae
    d.ellipse([7, 4, 16, 9], fill=INK)
    d.ellipse([8, 5, 15, 8], fill=GREEN_DARK)
    d.ellipse([6, 8, 17, 21], fill=INK)
    d.ellipse([7, 9, 16, 20], fill=GREEN)
    rect(d, 11, 9, 1, 11, GREEN_DARK)
    dots(d, ((9, 12), (14, 12), (9, 16), (14, 16)), GREEN_DARK)
    dots(d, ((9, 6), (14, 6)), WHITE)
    d.ellipse([1, 1, 22, 22], outline=RED, width=2)
    rect(d, 11, 0, 2, 5, RED)
    rect(d, 11, 19, 2, 5, RED)
    rect(d, 0, 11, 5, 2, RED)
    rect(d, 19, 11, 5, 2, RED)
    return image


ICONS = {
    "clicker": clicker,
    "blackjack": blackjack,
    "roulette": roulette,
    "checkers": checkers,
    "memory": memory,
    "defuse": defuse,
    "bug_hunt": bug_hunt,
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in ICONS.items():
        draw().save(OUT / f"{name}.png")
    print(f"icons written to {OUT}")


if __name__ == "__main__":
    main()
