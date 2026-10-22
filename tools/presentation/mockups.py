"""Device mockups for the presentation.

Phone screenshots from docs/screenshots become an iPhone with the game open in
Safari (status bar, collapsed Safari toolbar with the LAN address). Admin
screenshots become a macOS Safari window.

Usage: python3 mockups.py <out_dir>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SHOTS = ROOT / "docs" / "screenshots"

SF = "/System/Library/Fonts/SFNS.ttf"
GAME_HOST = "192.168.1.47"
ADMIN_URL = "192.168.1.47:5443"

# Everything below is in pixels at @2x, i.e. 2 px per iOS point.
PT = 2
SCREEN_W, SCREEN_H = 393 * PT, 852 * PT
STATUS_H = 54 * PT
TOOLBAR_H = 44 * PT
VIEWPORT_H = SCREEN_H - STATUS_H - TOOLBAR_H
SCREEN_RADIUS = 55 * PT
BEZEL = 10 * PT
RIM = 3 * PT
BODY_W = SCREEN_W + 2 * (BEZEL + RIM)
BODY_H = SCREEN_H + 2 * (BEZEL + RIM)
BODY_RADIUS = SCREEN_RADIUS + BEZEL + RIM
SHADOW_PAD = 90
SS = 4  # supersampling factor for anti-aliased shapes

# Where the game viewport starts in the original 393x852 screenshots. The
# screenshots were taken full screen, the Safari viewport is 98 pt shorter, so
# the top strip behind the Dynamic Island goes away.
SOURCE_TOP = 124
CRT_EDGE_MAX = 60


def font(size_pt: float, weight: bytes = b"Semibold") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(SF, int(round(size_pt * PT)))
    f.set_variation_by_name(weight)
    return f


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    w, h = size
    big = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * SS - 1, h * SS - 1), radius * SS, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def fill_crt_edges(img: Image.Image) -> Image.Image:
    """The game's CRT shader blackens the outer columns. Mirror the picture into them."""
    out = img.copy()
    src = img.load()
    dst = out.load()
    w, h = img.size
    for y in range(h):
        for side in (0, 1):
            x_at = (lambda k: k) if side == 0 else (lambda k: w - 1 - k)
            k = 0
            while k < CRT_EDGE_MAX and sum(src[x_at(k), y][:3]) < 10:
                k += 1
            if k == 0 or k == CRT_EDGE_MAX:
                continue
            for i in range(k):
                dst[x_at(i), y] = src[x_at(min(2 * k - 1 - i, w - 1)), y]
    return out


def luminance(rgb: tuple[int, int, int]) -> float:
    r, g, b = rgb
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def average(img: Image.Image) -> tuple[int, int, int]:
    return img.convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0))


def draw_status_bar(screen: Image.Image, dark_text: bool) -> None:
    ink = (0, 0, 0, 255) if dark_text else (255, 255, 255, 255)
    layer = Image.new("RGBA", (SCREEN_W * SS, STATUS_H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    s = PT * SS
    cy = 29.5 * s

    time_font = ImageFont.truetype(SF, int(17 * s))
    time_font.set_variation_by_name(b"Semibold")
    tw = d.textlength("9:41", font=time_font)
    d.text((66 * s - tw / 2, cy), "9:41", font=time_font, fill=ink, anchor="lm")

    # Cellular: four bars, bottom aligned.
    x = 300 * s
    for i, bh in enumerate((4.5, 6.8, 9.1, 11.4)):
        bx = x + i * 4.6 * s
        d.rounded_rectangle((bx, cy + 5.7 * s - bh * s, bx + 3 * s, cy + 5.7 * s), 0.9 * s, fill=ink)

    # Wi-Fi: three arcs and a dot, drawn as pie slices with the background cut out.
    wx, wy = 330 * s, cy + 5.6 * s
    for r in (11.5, 7.6, 3.8):
        d.pieslice((wx - r * s, wy - r * s, wx + r * s, wy + r * s), 225, 315, fill=ink)
        inner = r - 2.4
        if inner > 0:
            d.pieslice(
                (wx - inner * s, wy - inner * s, wx + inner * s, wy + inner * s),
                220,
                320,
                fill=(0, 0, 0, 0),
            )

    # Battery: outline, charge and the cap.
    bx0, bw, bh = 347 * s, 25 * s, 12 * s
    by0 = cy - bh / 2
    faded = ink[:3] + (95,)
    d.rounded_rectangle((bx0, by0, bx0 + bw, by0 + bh), 4 * s, outline=faded, width=int(1.1 * s))
    d.rounded_rectangle((bx0 + 2 * s, by0 + 2 * s, bx0 + bw * 0.78, by0 + bh - 2 * s), 2.2 * s, fill=ink)
    d.rounded_rectangle((bx0 + bw + 1.2 * s, cy - 2.2 * s, bx0 + bw + 2.6 * s, cy + 2.2 * s), 1 * s, fill=faded)

    layer = layer.resize((SCREEN_W, STATUS_H), Image.LANCZOS)
    screen.alpha_composite(layer, (0, 0))


def draw_collapsed_toolbar(screen: Image.Image, viewport: Image.Image) -> None:
    """Safari collapses its toolbar to the host name while a page is being used."""
    strip = viewport.crop((0, VIEWPORT_H - TOOLBAR_H, SCREEN_W, VIEWPORT_H))
    material = strip.transpose(Image.FLIP_TOP_BOTTOM).filter(ImageFilter.GaussianBlur(26))
    is_dark = luminance(average(strip)) < 90
    veil = (28, 28, 30, 200) if is_dark else (249, 249, 249, 214)
    material = Image.alpha_composite(material.convert("RGBA"), Image.new("RGBA", material.size, veil))
    top = STATUS_H + VIEWPORT_H
    screen.alpha_composite(material, (0, top))
    d = ImageDraw.Draw(screen)
    hairline = (255, 255, 255, 40) if is_dark else (0, 0, 0, 38)
    d.line((0, top, SCREEN_W, top), fill=hairline, width=1)
    ink = (235, 235, 245, 255) if is_dark else (30, 30, 32, 255)
    d.text((SCREEN_W / 2, top + 13 * PT), GAME_HOST, font=font(12.5, b"Medium"), fill=ink, anchor="mm")
    home = (255, 255, 255, 235) if is_dark else (0, 0, 0, 235)
    hw = 139 * PT
    hy = SCREEN_H - 8 * PT - 5 * PT
    d.rounded_rectangle(((SCREEN_W - hw) / 2, hy, (SCREEN_W + hw) / 2, hy + 5 * PT), 3 * PT, fill=home)


def build_screen(shot: Path) -> Image.Image:
    raw = Image.open(shot).convert("RGB")
    viewport = fill_crt_edges(raw.crop((0, SOURCE_TOP, SCREEN_W, SOURCE_TOP + VIEWPORT_H)))
    screen = Image.new("RGBA", (SCREEN_W, SCREEN_H), (0, 0, 0, 255))

    # Safari tints the status bar area with the colour at the top of the page.
    tint = average(viewport.crop((0, 0, SCREEN_W, 6)))
    screen.paste(Image.new("RGBA", (SCREEN_W, STATUS_H), tint + (255,)), (0, 0))
    screen.paste(viewport.convert("RGBA"), (0, STATUS_H))
    draw_status_bar(screen, dark_text=luminance(tint) > 140)
    draw_collapsed_toolbar(screen, viewport)
    return screen


def build_phone(shot: Path) -> Image.Image:
    screen = build_screen(shot)
    canvas_w, canvas_h = BODY_W + 2 * SHADOW_PAD, BODY_H + 2 * SHADOW_PAD
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))

    # Soft contact shadow under the body.
    shadow = Image.new("L", (canvas_w, canvas_h), 0)
    body_mask = rounded_mask((BODY_W, BODY_H), BODY_RADIUS)
    shadow.paste(body_mask.point(lambda v: v * 0.42), (SHADOW_PAD, SHADOW_PAD + 22))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas.paste(Image.new("RGBA", canvas.size, (20, 12, 12, 255)), (0, 0), shadow)

    ox, oy = SHADOW_PAD, SHADOW_PAD
    draw_side_buttons(canvas, ox, oy)

    # Black titanium rim with a lighter outer edge.
    canvas.paste(Image.new("RGBA", (BODY_W, BODY_H), (122, 122, 126, 255)), (ox, oy), body_mask)
    inner_size = (BODY_W - 2 * PT, BODY_H - 2 * PT)
    inner_mask = rounded_mask(inner_size, BODY_RADIUS - PT)
    canvas.paste(Image.new("RGBA", inner_size, (58, 58, 61, 255)), (ox + PT, oy + PT), inner_mask)

    bezel_size = (SCREEN_W + 2 * BEZEL, SCREEN_H + 2 * BEZEL)
    bezel_mask = rounded_mask(bezel_size, SCREEN_RADIUS + BEZEL)
    canvas.paste(Image.new("RGBA", bezel_size, (6, 6, 7, 255)), (ox + RIM, oy + RIM), bezel_mask)

    sx, sy = ox + RIM + BEZEL, oy + RIM + BEZEL
    canvas.paste(screen, (sx, sy), rounded_mask((SCREEN_W, SCREEN_H), SCREEN_RADIUS))

    island_w, island_h = 125 * PT, 37 * PT
    island = rounded_mask((island_w, island_h), island_h // 2)
    canvas.paste(Image.new("RGBA", (island_w, island_h), (0, 0, 0, 255)), (sx + (SCREEN_W - island_w) // 2, sy + 11 * PT), island)
    return canvas


def draw_side_buttons(canvas: Image.Image, ox: int, oy: int) -> None:
    color = (70, 70, 74, 255)
    d = ImageDraw.Draw(canvas)
    depth = 2 * PT
    for top, length in ((120, 30), (178, 56), (248, 56)):
        y0 = oy + top * PT
        d.rounded_rectangle((ox - depth, y0, ox + 4 * PT, y0 + length * PT), PT, fill=color)
    y0 = oy + 200 * PT
    d.rounded_rectangle((ox + BODY_W - 4 * PT, y0, ox + BODY_W + depth, y0 + 96 * PT), PT, fill=color)


# ---------------------------------------------------------------- macOS Safari

MAC_TOOLBAR_H = 52 * PT
MAC_RADIUS = 11 * PT


def build_browser(shot: Path, view_w_pt: int, view_h_pt: int) -> Image.Image:
    raw = Image.open(shot).convert("RGB")
    view_w, view_h = view_w_pt * PT, view_h_pt * PT
    scale = view_w / raw.width
    page = raw.resize((view_w, round(raw.height * scale)), Image.LANCZOS).crop((0, 0, view_w, view_h))
    if page.height < view_h:
        filled = Image.new("RGB", (view_w, view_h), page.getpixel((view_w // 2, page.height - 1)))
        filled.paste(page, (0, 0))
        page = filled

    win_w, win_h = view_w, view_h + MAC_TOOLBAR_H
    window = Image.new("RGBA", (win_w, win_h), (255, 255, 255, 255))
    window.paste(page, (0, MAC_TOOLBAR_H))
    draw_mac_toolbar(window)

    pad = SHADOW_PAD
    canvas = Image.new("RGBA", (win_w + 2 * pad, win_h + 2 * pad), (0, 0, 0, 0))
    mask = rounded_mask((win_w, win_h), MAC_RADIUS)
    shadow = Image.new("L", canvas.size, 0)
    shadow.paste(mask.point(lambda v: v * 0.30), (pad, pad + 18))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.paste(Image.new("RGBA", canvas.size, (20, 12, 12, 255)), (0, 0), shadow)
    outline = rounded_mask((win_w + 2, win_h + 2), MAC_RADIUS + 1)
    canvas.paste(Image.new("RGBA", (win_w + 2, win_h + 2), (0, 0, 0, 60)), (pad - 1, pad - 1), outline)
    canvas.paste(window, (pad, pad), mask)
    return canvas


def draw_mac_toolbar(window: Image.Image) -> None:
    w = window.width
    d = ImageDraw.Draw(window)
    d.rectangle((0, 0, w, MAC_TOOLBAR_H), fill=(246, 246, 246, 255))
    d.line((0, MAC_TOOLBAR_H - 1, w, MAC_TOOLBAR_H - 1), fill=(222, 222, 222, 255), width=PT)
    cy = MAC_TOOLBAR_H / 2
    for i, color in enumerate(((255, 95, 87), (254, 188, 46), (40, 200, 64))):
        cx = (20 + i * 20) * PT
        d.ellipse((cx - 6 * PT, cy - 6 * PT, cx + 6 * PT, cy + 6 * PT), fill=color + (255,))

    icon = (120, 120, 124, 255)
    # Sidebar toggle.
    x = 92 * PT
    d.rounded_rectangle((x, cy - 7 * PT, x + 20 * PT, cy + 7 * PT), 3 * PT, outline=icon, width=int(1.4 * PT))
    d.line((x + 7 * PT, cy - 7 * PT, x + 7 * PT, cy + 7 * PT), fill=icon, width=int(1.4 * PT))
    # Back and forward chevrons.
    for bx, direction, ink in ((140, -1, icon), (172, 1, (190, 190, 194, 255))):
        px = bx * PT
        d.line(
            (px + 3 * PT * -direction, cy - 6 * PT, px - 3 * PT * -direction, cy, px + 3 * PT * -direction, cy + 6 * PT),
            fill=ink,
            width=int(1.8 * PT),
            joint="curve",
        )

    field_w = min(520 * PT, int(w * 0.42))
    fx0 = (w - field_w) // 2
    d.rounded_rectangle((fx0, cy - 15 * PT, fx0 + field_w, cy + 15 * PT), 8 * PT, fill=(229, 229, 231, 255))
    d.text((w / 2, cy), ADMIN_URL, font=font(13, b"Regular"), fill=(40, 40, 42, 255), anchor="mm")

    # Share, new tab and tab overview on the right.
    rx = w - 26 * PT
    d.rounded_rectangle((rx - 7 * PT, cy - 5 * PT, rx + 7 * PT, cy + 9 * PT), 3 * PT, outline=icon, width=int(1.4 * PT))
    d.rectangle((rx - 7 * PT, cy - 7 * PT, rx + 7 * PT, cy - 3 * PT), fill=(246, 246, 246, 255))
    rx -= 36 * PT
    d.line((rx - 7 * PT, cy, rx + 7 * PT, cy), fill=icon, width=int(1.6 * PT))
    d.line((rx, cy - 7 * PT, rx, cy + 7 * PT), fill=icon, width=int(1.6 * PT))
    rx -= 36 * PT
    d.rounded_rectangle((rx - 6 * PT, cy - 9 * PT, rx + 9 * PT, cy + 6 * PT), 3 * PT, outline=icon, width=int(1.4 * PT))


ADMIN_VIEWS = {
    "admin-04-stats": (1280, 760),
    "admin-17-manager-panel": (1280, 760),
    "admin-13-offices": (1280, 760),
    "admin-10-limits": (1280, 760),
}


def main(out_dir: str) -> None:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for shot in sorted(SHOTS.glob("[0-9]*.png")):
        if shot.stem == "16-office-screen":
            continue
        build_phone(shot).save(out / f"phone-{shot.stem}.png", optimize=True)
    for name, (vw, vh) in ADMIN_VIEWS.items():
        build_browser(SHOTS / f"{name}.png", vw, vh).save(out / f"browser-{name}.png", optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
