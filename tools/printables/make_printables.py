"""Printable room emblems for the doors and ArUco markers for the scavenger hunt.

Room ids and names are read from the game sources, so the posters always match the office map:
  - client/scripts/world/office_layout.gd, analytics_layout.gd  (add_room calls)
  - client/localization/strings.csv        (room names)
  - client/assets/brand/emblems            (the emblem of each room: emblems.json and <id>.png)
  - server/content/tasks.json               (scavenger hunt markers)

Usage:
    pip install -r tools/requirements.txt
    python tools/printables/make_printables.py --out build/printables

Output: one PNG per room and marker (A5-ish, 150 dpi) plus printables.pdf with all pages.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

import cv2
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
LAYOUTS = [ROOT / "client/scripts/world/office_layout.gd", ROOT / "client/scripts/world/analytics_layout.gd"]
EMBLEMS = ROOT / "client/assets/brand/emblems"
STRINGS = ROOT / "client/localization/strings.csv"
TASKS = ROOT / "server/content/tasks.json"
PAGE = (874, 1240)  # A5 at 150 dpi
RED = (239, 49, 36)
INK = (29, 29, 31)
MARKER_DICTIONARY = cv2.aruco.DICT_4X4_50
MARKER_PIXELS = 600


def load_strings() -> dict[str, str]:
    with STRINGS.open(encoding="utf-8") as file:
        return {row["keys"]: row["ru"] for row in csv.DictReader(file)}


def load_rooms(strings: dict[str, str]) -> list[tuple[str, str]]:
    pattern = re.compile(r'add_room\(&"(?P<id>\w+)", "(?P<key>\w+)"')
    rooms: list[tuple[str, str]] = []
    for layout in LAYOUTS:
        source = layout.read_text(encoding="utf-8")
        rooms += [(match["id"], strings.get(match["key"], match["id"])) for match in pattern.finditer(source)]
    return rooms


def load_emblems() -> dict[str, str]:
    """Room id -> emblem id."""
    catalog = json.loads((EMBLEMS / "emblems.json").read_text(encoding="utf-8"))
    return {emblem["room"]: emblem["id"] for emblem in catalog["emblems"]}


def load_markers(strings: dict[str, str]) -> list[tuple[int, str]]:
    markers: dict[int, str] = {}
    for task in json.loads(TASKS.read_text(encoding="utf-8"))["tasks"]:
        for target in task.get("params", {}).get("targets", []):
            markers[int(target["marker"])] = strings.get(target["name"], target["name"])
    return sorted(markers.items())


def font(size: int) -> ImageFont.ImageFont:
    for name in ("arialbd.ttf", "DejaVuSans-Bold.ttf", "Arial Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def page(title: str, subtitle: str, picture: Image.Image, footer: str, smooth: bool = False) -> Image.Image:
    sheet = Image.new("RGB", PAGE, "white")
    draw = ImageDraw.Draw(sheet)
    draw.rectangle((0, 0, PAGE[0], 90), fill=RED)
    draw.text((PAGE[0] // 2, 45), "АЛЬФА ОФИС", fill="white", font=font(44), anchor="mm")
    draw.text((PAGE[0] // 2, 170), title, fill=INK, font=font(60), anchor="mm")
    draw.text((PAGE[0] // 2, 240), subtitle, fill=INK, font=font(28), anchor="mm")
    # Codes stay sharp; emblem pictures keep their proportions and are scaled smoothly.
    if smooth:
        picture = picture.copy()
        picture.thumbnail((640, 640), Image.LANCZOS)
        if max(picture.size) < 640:
            scale = 640 / max(picture.size)
            picture = picture.resize((round(picture.width * scale), round(picture.height * scale)), Image.LANCZOS)
    else:
        picture = picture.resize((640, 640), Image.NEAREST)
    sheet.paste(picture, ((PAGE[0] - picture.width) // 2, 300 + (640 - picture.height) // 2))
    draw.text((PAGE[0] // 2, 1010), footer, fill=(110, 106, 100), font=font(24), anchor="mm")
    return sheet


def room_page(room_id: str, name: str, emblem_id: str) -> Image.Image:
    picture = Image.open(EMBLEMS / f"{emblem_id}.png").convert("RGB")
    subtitle = "Наведи камеру в игре: персонаж перейдёт сюда"
    return page(name, subtitle, picture, f"Эмблема комнаты: {emblem_id}", smooth=True)


def marker_page(marker_id: int, name: str) -> Image.Image:
    dictionary = cv2.aruco.getPredefinedDictionary(MARKER_DICTIONARY)
    marker = cv2.aruco.generateImageMarker(dictionary, marker_id, MARKER_PIXELS)
    # White quiet zone around the marker helps detection.
    bordered = cv2.copyMakeBorder(marker, 80, 80, 80, 80, cv2.BORDER_CONSTANT, value=255)
    picture = Image.fromarray(bordered).convert("RGB")
    return page(name, "Охота за предметами: наклей на предмет", picture, f"ArUco DICT_4X4_50, id {marker_id}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=ROOT / "build/printables")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    strings = load_strings()
    emblems = load_emblems()
    pages: list[Image.Image] = []
    for room_id, name in load_rooms(strings):
        if room_id not in emblems:
            raise SystemExit(f"Room {room_id} has no emblem in {EMBLEMS / 'emblems.json'}")
        sheet = room_page(room_id, name, emblems[room_id])
        sheet.save(args.out / f"room_{room_id}.png")
        pages.append(sheet)
    for marker_id, name in load_markers(strings):
        sheet = marker_page(marker_id, name)
        sheet.save(args.out / f"marker_{marker_id}.png")
        pages.append(sheet)
    # The PDF writer stores pages as JPEG: make sure every Pillow format plugin is registered.
    Image.init()
    pages[0].save(args.out / "printables.pdf", save_all=True, append_images=pages[1:], resolution=150)
    print(f"{len(pages)} pages written to {args.out}")


if __name__ == "__main__":
    main()
