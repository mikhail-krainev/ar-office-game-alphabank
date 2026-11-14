"""Pixel-art icons of the office HUD buttons (tasks, QR scan, shop, chat, games), 24x24, drawn here.

Usage:
    python tools/printables/make_hud_icons.py

Writes client/assets/ui/hud_icons/<name>.png. The tasks icon sits on the red primary button, the
others on the paper buttons, so their colours are baked in (UiStyle palette).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "client/assets/ui/hud_icons"
SIZE = 24

INK = (29, 29, 31, 255)
RED = (239, 49, 36, 255)
RED_DARK = (176, 30, 22, 255)
WHITE = (255, 255, 255, 255)
PAPER = (251, 250, 248, 255)
SHADE = (225, 219, 210, 255)
GOLD = (247, 201, 72, 255)
GOLD_DARK = (196, 140, 30, 255)
MUTED = (150, 145, 138, 255)


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def rect(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, color: tuple) -> None:
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def tasks() -> Image.Image:
    """Clipboard with two ticked lines and one open, on the red button."""
    image, d = canvas()
    rect(d, 4, 3, 16, 20, RED_DARK)  # shadow edge
    rect(d, 4, 3, 16, 19, WHITE)
    rect(d, 5, 4, 14, 17, PAPER)
    rect(d, 8, 1, 8, 4, GOLD_DARK)  # clip
    rect(d, 9, 1, 6, 3, GOLD)
    rect(d, 11, 0, 2, 2, GOLD_DARK)
    for row, done in ((7, True), (12, True), (17, False)):
        if done:
            # tick
            for dx, dy in ((0, 1), (1, 2), (2, 1), (3, 0), (4, -1)):
                rect(d, 6 + dx, row + dy, 1, 1, RED)
                rect(d, 6 + dx, row + dy + 1, 1, 1, RED)
        else:
            rect(d, 6, row - 1, 4, 4, SHADE)
            rect(d, 7, row, 2, 2, PAPER)
        rect(d, 12, row, 6, 2, MUTED if done else INK)
    return image


def qr() -> Image.Image:
    """Scanner frame corners around a small QR code."""
    image, d = canvas()
    for x, y, sx, sy in ((1, 1, 1, 1), (22, 1, -1, 1), (1, 22, 1, -1), (22, 22, -1, -1)):
        rect(d, min(x, x + sx * 5), y if sy > 0 else y - 1, 6, 2, RED)
        rect(d, x if sx > 0 else x - 1, min(y, y + sy * 5), 2, 6, RED)
    # finder squares
    for fx, fy in ((5, 5), (13, 5), (5, 13)):
        rect(d, fx, fy, 6, 6, INK)
        rect(d, fx + 1, fy + 1, 4, 4, PAPER)
        rect(d, fx + 2, fy + 2, 2, 2, INK)
    for px, py in ((13, 13), (15, 15), (17, 13), (13, 17), (17, 17), (15, 13), (17, 15)):
        rect(d, px, py, 2, 2, INK)
    rect(d, 2, 11, 20, 1, (239, 49, 36, 170))  # scan beam
    return image


def shop() -> Image.Image:
    """Shopping bag with a gold coin."""
    image, d = canvas()
    # handle
    rect(d, 8, 2, 8, 2, INK)
    rect(d, 7, 3, 2, 6, INK)
    rect(d, 15, 3, 2, 6, INK)
    # bag
    rect(d, 3, 7, 18, 16, INK)
    rect(d, 4, 8, 16, 14, RED)
    rect(d, 4, 8, 16, 2, RED_DARK)
    rect(d, 5, 10, 1, 10, (255, 120, 110, 255))  # shine
    # coin
    rect(d, 9, 12, 6, 8, GOLD_DARK)
    rect(d, 8, 13, 8, 6, GOLD_DARK)
    rect(d, 9, 13, 6, 6, GOLD)
    rect(d, 11, 14, 2, 4, GOLD_DARK)
    rect(d, 10, 13, 1, 2, WHITE)
    return image


def chat() -> Image.Image:
    """Speech bubble with three dots and a smaller reply bubble."""
    image, d = canvas()
    # back bubble (reply)
    rect(d, 11, 2, 12, 9, INK)
    rect(d, 12, 3, 10, 7, SHADE)
    # main bubble
    rect(d, 1, 7, 18, 12, INK)
    rect(d, 2, 6, 16, 14, INK)
    rect(d, 2, 8, 16, 10, PAPER)
    rect(d, 3, 7, 14, 12, PAPER)
    # tail
    rect(d, 4, 20, 4, 1, INK)
    rect(d, 4, 21, 2, 1, INK)
    rect(d, 4, 22, 1, 1, INK)
    rect(d, 5, 19, 2, 1, PAPER)
    rect(d, 5, 20, 1, 1, PAPER)
    for x in (5, 9, 13):
        rect(d, x, 12, 2, 2, RED)
    return image


def games() -> Image.Image:
    """Entertainment: a fanned playing card (ace of hearts) behind a casino chip."""
    image, d = canvas()
    # back card, tilted left by a stepped edge
    rect(d, 2, 4, 11, 15, INK)
    rect(d, 3, 5, 9, 13, RED)
    rect(d, 4, 6, 7, 11, RED_DARK)
    rect(d, 5, 7, 5, 9, RED)
    # front card
    rect(d, 7, 1, 12, 17, INK)
    rect(d, 8, 2, 10, 15, WHITE)
    for x, y in ((10, 3), (9, 4), (11, 4), (9, 5), (10, 5), (11, 5), (9, 6), (11, 6)):
        rect(d, x, y, 1, 1, RED)  # rank "A"
    # heart
    rect(d, 11, 8, 2, 2, RED)
    rect(d, 14, 8, 2, 2, RED)
    rect(d, 10, 9, 7, 2, RED)
    rect(d, 11, 11, 5, 1, RED)
    rect(d, 12, 12, 3, 1, RED)
    rect(d, 13, 13, 1, 1, RED)
    # chip
    rect(d, 13, 14, 8, 10, INK)
    rect(d, 12, 15, 10, 8, INK)
    rect(d, 14, 15, 6, 8, GOLD)
    rect(d, 13, 16, 8, 6, GOLD)
    for x, y in ((16, 15), (16, 22), (13, 18), (20, 18)):
        rect(d, x, y, 2, 1 if y in (15, 22) else 2, WHITE)
    rect(d, 15, 17, 4, 4, GOLD_DARK)
    rect(d, 16, 18, 2, 2, GOLD)
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in (("tasks", tasks), ("qr", qr), ("shop", shop), ("chat", chat), ("games", games)):
        draw().save(OUT / f"{name}.png")
    print(f"icons written to {OUT}")


if __name__ == "__main__":
    main()
