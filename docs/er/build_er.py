"""Builds the ER diagram from docs/schema.dbml.

Tables are placed by hand (LAYOUT); links are routed on a grid around the tables, so no line
crosses a table. Links into the same key share one trunk. Output: er-diagram.svg (hover a table
to highlight its links) and, with Google Chrome installed, er-diagram.pdf.

    python3 docs/er/build_er.py
"""

from __future__ import annotations

import heapq
import html
import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCHEMA = HERE.parent / "schema.dbml"

GRID = 10
TABLE_W = 250
HEADER_H = 30
ROW_H = 20
COL_GAP = 170
ROW_GAP = 40
MARGIN = 60
TOP = MARGIN
STUB = 2 * GRID

# Columns from left to right; "None" starts the lower block of a column at LOWER_Y.
LAYOUT = [
    ["inbox_items", "settings_limits", None, "tasks"],
    ["wallet_ledger", "operations", "activity", "avatars", "inbox", None,
     "player_days", "player_day_tasks", "task_log", "task_assignments", "colleague_meetings",
     "photo_requests"],
    ["users", None, "game_state"],
    ["account_metadata", "office_presence", "suspicious", "reward_requests", None,
     "owned_items", "daily_purchases", "player_outfit", "owned_cars"],
    ["offices", "departments", "raffles", "raffle_tickets", None,
     "shop_items", "wardrobe_items", "cars"],
]
LOWER_Y = 810
# Upper tables of a column may start lower than TOP to line up with their partners.
START_Y = {"inbox_items": 550, "users": TOP + 230}
# The lower block may also start lower.
LOWER_START = {0: 1090, 2: 700, 4: 910}


@dataclass
class Column:
    name: str
    type: str
    pk: bool = False
    fk: bool = False


@dataclass
class Table:
    name: str
    color: str
    note: str
    columns: list[Column] = field(default_factory=list)
    group: str = ""
    x: int = 0
    y: int = 0

    @property
    def h(self) -> int:
        return HEADER_H + ROW_H * len(self.columns) + 6

    def row_y(self, column: str) -> int:
        index = next(i for i, c in enumerate(self.columns) if c.name == column)
        return self.y + HEADER_H + ROW_H // 2 + ROW_H * index

    @property
    def embedded(self) -> bool:
        return self.note.startswith("Вложено")


@dataclass
class Ref:
    fk_table: str
    fk_column: str
    pk_table: str
    pk_column: str
    one_to_one: bool


def parse(text: str) -> tuple[dict[str, Table], list[Ref]]:
    tables: dict[str, Table] = {}
    refs: list[Ref] = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        head = re.match(r"Table (\w+)(?: \[headercolor: (#\w+)\])? \{", line)
        if head:
            table = Table(head.group(1), head.group(2) or "#6E7781", "")
            i += 1
            depth = 1
            while depth:
                line = lines[i].strip()
                if line.startswith("Indexes {"):
                    depth += 1
                elif line == "}":
                    depth -= 1
                elif depth == 2:
                    pk = re.match(r"\(([\w, ]+)\) \[pk\]", line)
                    if pk:
                        for name in pk.group(1).split(","):
                            for column in table.columns:
                                if column.name == name.strip():
                                    column.pk = True
                elif line.startswith("Note:"):
                    table.note = line.split("'")[1]
                elif line:
                    column = re.match(r'(\w+) ("[^"]+"|\S+)(?: \[(.*)\])?', line)
                    if column:
                        settings = column.group(3) or ""
                        table.columns.append(Column(
                            column.group(1), column.group(2).strip('"'),
                            pk=bool(re.match(r"pk\b", settings))))
                i += 1
            tables[table.name] = table
            continue
        group = re.match(r"TableGroup (\w+) \{", line)
        if group:
            i += 1
            while lines[i].strip() != "}":
                tables[lines[i].strip()].group = group.group(1)
                i += 1
        ref = re.match(r"Ref: (\w+)\.(\w+) ([>-]) (\w+)\.(\w+)", line)
        if ref:
            refs.append(Ref(ref.group(1), ref.group(2), ref.group(4), ref.group(5), ref.group(3) == "-"))
        i += 1
    for ref in refs:
        for column in tables[ref.fk_table].columns:
            if column.name == ref.fk_column:
                column.fk = True
    return tables, refs


def place(tables: dict[str, Table]) -> tuple[int, int]:
    width = height = 0
    for index, column in enumerate(LAYOUT):
        x = MARGIN + index * (TABLE_W + COL_GAP)
        y = TOP
        lower = False
        for name in column:
            if name is None:
                lower = True
                y = max(y, LOWER_START.get(index, LOWER_Y))
                continue
            table = tables[name]
            y = max(y, START_Y.get(name, y))
            table.x, table.y = x, y
            y += table.h + ROW_GAP
            height = max(height, y)
        width = x + TABLE_W
    del lower
    return width + MARGIN, height + MARGIN


# --- Routing -------------------------------------------------------------------------

DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1)]


class Router:
    def __init__(self, tables: dict[str, Table], width: int, height: int):
        self.cols = width // GRID + 1
        self.rows = height // GRID + 1
        self.blocked = bytearray(self.cols * self.rows)
        for table in tables.values():
            x0 = (table.x - GRID) // GRID
            x1 = (table.x + TABLE_W + GRID) // GRID
            y0 = (table.y - GRID) // GRID
            y1 = (table.y + table.h + GRID) // GRID
            for gy in range(max(0, y0), min(self.rows, y1 + 1)):
                for gx in range(max(0, x0), min(self.cols, x1 + 1)):
                    self.blocked[gy * self.cols + gx] = 1
        # cell -> list of (net, axis); axis 0 = horizontal, 1 = vertical
        self.wires: dict[int, list[tuple[str, int]]] = {}

    def cost_of(self, cell: int, axis: int, net: str) -> float:
        cost = 0.0
        for other, other_axis in self.wires.get(cell, ()):
            if other == net:
                return -0.6  # share the trunk of links into the same key
            cost += 60 if other_axis == axis else 8
        return cost

    def route(self, start: tuple[int, int, int], goal: tuple[int, int, int], net: str) -> tuple[float, list[tuple[int, int]]]:
        """start/goal: (gx, gy, direction index). Leaves start along its direction, enters goal along its."""
        sx, sy, sd = start
        gx, gy, gd = goal
        frontier = [(0.0, 0.0, sx, sy, sd)]
        best = {(sx, sy, sd): 0.0}
        came: dict[tuple[int, int, int], tuple[int, int, int]] = {}
        while frontier:
            _, cost, x, y, d = heapq.heappop(frontier)
            if (x, y) == (gx, gy) and d == gd:
                path = [(x, y)]
                state = (x, y, d)
                while state in came:
                    state = came[state]
                    path.append(state[:2])
                return cost, path[::-1]
            if cost > best.get((x, y, d), 1e18):
                continue
            for nd, (dx, dy) in enumerate(DIRS):
                if (dx, dy) == (-DIRS[d][0], -DIRS[d][1]):
                    continue
                nx, ny = x + dx, y + dy
                if not (0 <= nx < self.cols and 0 <= ny < self.rows):
                    continue
                cell = ny * self.cols + nx
                if self.blocked[cell] and (nx, ny) != (gx, gy):
                    continue
                step = 1 + self.cost_of(cell, 0 if dy == 0 else 1, net)
                if nd != d:
                    step += 12
                new = cost + max(step, 0.3)
                if new < best.get((nx, ny, nd), 1e18):
                    best[(nx, ny, nd)] = new
                    came[(nx, ny, nd)] = (x, y, d)
                    estimate = abs(nx - gx) + abs(ny - gy)
                    heapq.heappush(frontier, (new + estimate * 0.3, new, nx, ny, nd))
        return float("inf"), []

    def commit(self, path: list[tuple[int, int]], net: str) -> None:
        for (x0, y0), (x1, y1) in zip(path, path[1:]):
            axis = 0 if y0 == y1 else 1
            for cell in (y0 * self.cols + x0, y1 * self.cols + x1):
                entry = (net, axis)
                if entry not in self.wires.setdefault(cell, []):
                    self.wires[cell].append(entry)


def port(table: Table, column: str, side: str) -> tuple[tuple[int, int], tuple[int, int, int]]:
    """Point on the table edge and the grid state just outside it, heading away (start) for routing."""
    y = table.row_y(column)
    if side == "left":
        edge = (table.x, y)
        cell = ((table.x - STUB) // GRID, y // GRID, 1)
    else:
        edge = (table.x + TABLE_W, y)
        cell = ((table.x + TABLE_W + STUB) // GRID, y // GRID, 0)
    return edge, cell


def route_all(tables: dict[str, Table], refs: list[Ref], router: Router):
    def span(ref: Ref) -> int:
        a, b = tables[ref.fk_table], tables[ref.pk_table]
        return abs(a.x - b.x) + abs(a.row_y(ref.fk_column) - b.row_y(ref.pk_column))

    routes = []
    for ref in sorted(refs, key=span):
        fk, pk = tables[ref.fk_table], tables[ref.pk_table]
        net = f"{ref.pk_table}.{ref.pk_column}"
        best = None
        for fk_side in ("left", "right"):
            for pk_side in ("left", "right"):
                fk_edge, start = port(fk, ref.fk_column, fk_side)
                pk_edge, goal = port(pk, ref.pk_column, pk_side)
                # Enter the target heading toward it.
                goal = (goal[0], goal[1], 0 if pk_side == "left" else 1)
                cost, path = router.route(start, goal, net)
                if path and (best is None or cost < best[0]):
                    best = (cost, path, fk_edge, pk_edge, fk_side, pk_side)
        if best is None:
            raise SystemExit(f"no route for {ref}")
        _, path, fk_edge, pk_edge, fk_side, pk_side = best
        router.commit(path, net)
        points = [fk_edge] + [(x * GRID, y * GRID) for x, y in path] + [pk_edge]
        routes.append((ref, simplify(points), fk_side, pk_side))
    return routes


def simplify(points: list[tuple[int, int]]) -> list[tuple[int, int]]:
    result = [points[0]]
    for point in points[1:]:
        if point == result[-1]:
            continue
        if len(result) >= 2:
            (ax, ay), (bx, by) = result[-2], result[-1]
            if (ax == bx == point[0]) or (ay == by == point[1]):
                result[-1] = point
                continue
        result.append(point)
    return result


def rounded(points: list[tuple[int, int]], radius: int = 6) -> str:
    d = f"M{points[0][0]},{points[0][1]}"
    for i in range(1, len(points) - 1):
        (px, py), (cx, cy), (nx, ny) = points[i - 1], points[i], points[i + 1]
        r = min(radius, (abs(cx - px) + abs(cy - py)) // 2, (abs(nx - cx) + abs(ny - cy)) // 2)
        ix = cx - r * ((cx > px) - (cx < px))
        iy = cy - r * ((cy > py) - (cy < py))
        ox = cx + r * ((nx > cx) - (nx < cx))
        oy = cy + r * ((ny > cy) - (ny < cy))
        d += f" L{ix},{iy} Q{cx},{cy} {ox},{oy}"
    d += f" L{points[-1][0]},{points[-1][1]}"
    return d


# --- Drawing -------------------------------------------------------------------------

def esc(text: str) -> str:
    return html.escape(text, quote=True)


def end_mark(x: int, y: int, side: str, many: bool) -> str:
    """Crow's foot (many) or a double bar (one) at a table edge."""
    s = -1 if side == "left" else 1
    if many:
        return (f'<path d="M{x + s * 12},{y} L{x},{y - 6} M{x + s * 12},{y} L{x},{y} '
                f'M{x + s * 12},{y} L{x},{y + 6} M{x + s * 16},{y - 6} L{x + s * 16},{y + 6}"/>')
    return f'<path d="M{x + s * 8},{y - 6} L{x + s * 8},{y + 6} M{x + s * 13},{y - 6} L{x + s * 13},{y + 6}"/>'


def draw(tables: dict[str, Table], routes, width: int, height: int) -> str:
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
        'font-family="-apple-system, \'Helvetica Neue\', Arial, sans-serif">',
        """<style>
  .bg { fill: #FAFAF7; }
  .card { fill: #FFFFFF; stroke: #D0D7DE; stroke-width: 1; }
  .card.embedded { stroke-dasharray: 5 3; stroke: #9AA4AE; }
  .title { font-size: 13px; font-weight: 700; fill: #FFFFFF; }
  .col { font-size: 11.5px; fill: #24292F; }
  .col.key { font-weight: 700; }
  .type { font-size: 10.5px; fill: #8C959F; font-family: Menlo, monospace; }
  .badge { font-size: 8.5px; font-weight: 700; }
  .link path { fill: none; stroke-width: 1.6; stroke-linejoin: round; }
  .link .mark path { stroke-width: 1.6; }
  .dim .link:not(.on) { opacity: .08; }
  .dim .table:not(.on) { opacity: .25; }
  .link.on path { stroke-width: 2.6; }
</style>""",
        f'<rect class="bg" width="{width}" height="{height}"/>',
    ]
    out.append('<g id="diagram">')
    out.append('<g id="links">')
    for ref, points, fk_side, pk_side in routes:
        color = tables[ref.pk_table].color
        fx, fy = points[0]
        px, py = points[-1]
        out.append(
            f'<g class="link" data-a="{ref.fk_table}" data-b="{ref.pk_table}" stroke="{color}">'
            f'<title>{ref.fk_table}.{ref.fk_column} → {ref.pk_table}.{ref.pk_column}</title>'
            f'<path d="{rounded(points)}"/>'
            f'<g class="mark">{end_mark(fx, fy, fk_side, not ref.one_to_one)}{end_mark(px, py, pk_side, False)}</g></g>')
    out.append('</g>')
    for table in tables.values():
        cls = "card embedded" if table.embedded else "card"
        out.append(f'<g class="table" data-name="{table.name}">')
        out.append(f'<rect class="{cls}" x="{table.x}" y="{table.y}" width="{TABLE_W}" height="{table.h}" rx="6"/>')
        out.append(f'<path d="M{table.x},{table.y + HEADER_H} V{table.y + 6} Q{table.x},{table.y} {table.x + 6},{table.y} '
                   f'H{table.x + TABLE_W - 6} Q{table.x + TABLE_W},{table.y} {table.x + TABLE_W},{table.y + 6} '
                   f'V{table.y + HEADER_H} Z" fill="{table.color}"/>')
        out.append(f'<text class="title" x="{table.x + 10}" y="{table.y + 20}">{table.name}</text>')
        for i, column in enumerate(table.columns):
            cy = table.y + HEADER_H + ROW_H * i
            if i % 2:
                out.append(f'<rect x="{table.x + 1}" y="{cy}" width="{TABLE_W - 2}" height="{ROW_H}" fill="#F6F8FA"/>')
            key = column.pk or column.fk
            bx = table.x + 8
            if column.pk:
                out.append(f'<text class="badge" x="{bx}" y="{cy + 14}" fill="#BF8700">PK</text>')
            if column.fk:
                out.append(f'<text class="badge" x="{bx + (16 if column.pk else 0)}" y="{cy + 14}" fill="#0969DA">FK</text>')
            out.append(f'<text class="col{" key" if key else ""}" x="{table.x + 40}" y="{cy + 14}">{column.name}</text>')
            out.append(f'<text class="type" x="{table.x + TABLE_W - 10}" y="{cy + 14}" text-anchor="end">{esc(column.type)}</text>')
        out.append('</g>')
    out.append('</g>')
    out.append("""<script><![CDATA[
const root = document.getElementById('diagram');
const links = [...document.querySelectorAll('.link')];
document.querySelectorAll('.table').forEach(t => {
  const name = t.dataset.name;
  t.addEventListener('mouseenter', () => {
    root.classList.add('dim');
    t.classList.add('on');
    links.forEach(l => {
      if (l.dataset.a === name || l.dataset.b === name) {
        l.classList.add('on');
        document.querySelector(`.table[data-name="${l.dataset.a}"]`).classList.add('on');
        document.querySelector(`.table[data-name="${l.dataset.b}"]`).classList.add('on');
      }
    });
  });
  t.addEventListener('mouseleave', () => {
    root.classList.remove('dim');
    document.querySelectorAll('.on').forEach(e => e.classList.remove('on'));
  });
});
]]></script>""")
    out.append("</svg>")
    return "\n".join(out)


def export_pdf(svg_path: Path, width: int, height: int) -> None:
    chrome = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
    binary = str(chrome) if chrome.exists() else shutil.which("google-chrome") or shutil.which("chromium")
    if not binary:
        print("Chrome not found: PDF skipped")
        return
    page = HERE / "_print.html"
    page.write_text(
        f"<!doctype html><meta charset='utf-8'><style>@page{{size:{width}px {height}px;margin:0}}"
        f"html,body{{margin:0}}svg{{display:block}}</style>{svg_path.read_text()}", encoding="utf-8")
    try:
        subprocess.run([binary, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                        f"--print-to-pdf={HERE / 'er-diagram.pdf'}", page.as_uri()],
                       check=True, capture_output=True)
    finally:
        page.unlink()


def main() -> None:
    tables, refs = parse(SCHEMA.read_text(encoding="utf-8"))
    width, height = place(tables)
    missing = set(tables) - {name for column in LAYOUT for name in column if name}
    if missing:
        raise SystemExit(f"not placed: {sorted(missing)}")
    routes = route_all(tables, refs, Router(tables, width, height))
    svg_path = HERE / "er-diagram.svg"
    svg_path.write_text(draw(tables, routes, width, height), encoding="utf-8")
    export_pdf(svg_path, width, height)
    print(f"{svg_path} ({width}x{height}, {len(tables)} tables, {len(refs)} links)")


if __name__ == "__main__":
    main()
