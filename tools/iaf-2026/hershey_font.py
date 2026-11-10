#!/usr/bin/env python3
"""Modern IAF's HUD and display font (modern-iaf/docs/cockpit.md §5): Hershey's Roman Simplex stroke font as a TTF.

    python3 -I tools/iaf-2026/hershey_font.py   # tools/iaf-2026/fonts/futural.jhf -> modern-iaf/data/fonts/HersheySimplex.ttf

The source is Kamal Mostafa's hershey-fonts `futural.jhf` (James Hurt's format; the Hershey Fonts' notice in
modern-iaf/data/fonts/HERSHEY.txt): one line per ASCII glyph from the space, each a vertex count and pairs of letters
(coordinate = letter - 'R', y down), the first pair the glyph's left and right side, " R" lifting the pen. Each stroke
segment becomes a filled bar and each vertex a round dot (octagon) of the same width, all wound the same way, so the
rasteriser's non-zero fill joins them into the drawn line. Needs fontTools.
"""

import math
import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools/iaf-2026/fonts/futural.jhf")
OUT = os.path.join(ROOT, "modern-iaf/data/fonts/HersheySimplex.ttf")
SCALE = 32  # font units per Hershey unit: the capitals' 21 units -> 672 of 1000
BASE = 9  # the Hershey baseline (y down)
WIDTH = 2.0  # the stroke's width in Hershey units, about a tenth of the capitals' height (a HUD's thin line)


def glyphs(path):
    """[(left, right, [stroke, …])] for ASCII 32 on, a stroke a list of (x, y) in Hershey units."""
    out = []
    for line in open(path, encoding="ascii").read().splitlines():
        n = int(line[5:8])
        body = line[8 : 8 + 2 * n]
        pairs = [(ord(body[i]) - 82, ord(body[i + 1]) - 82) for i in range(0, len(body), 2)]
        strokes, cur = [], []
        for p in pairs[1:]:
            if p == (-50, 0):  # " R": pen up
                strokes.append(cur)
                cur = []
            else:
                cur.append(p)
        strokes.append(cur)
        out.append((pairs[0][0], pairs[0][1], [s for s in strokes if s]))
    return out


def contour(pen, pts):
    """A closed contour, wound clockwise (TrueType's filled side) whatever the order given."""
    if sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1])) > 0:
        pts = pts[::-1]
    pen.moveTo(pts[0])
    for p in pts[1:]:
        pen.lineTo(p)
    pen.closePath()


def draw(pen, left, strokes):
    h = WIDTH / 2.0

    def pt(x, y):
        return (round((x - left) * SCALE), round((BASE - y) * SCALE))

    for s in strokes:
        for x, y in s:  # a dot at each vertex: the line's round joins and ends 
            contour(pen, [pt(x + h * math.cos(a), y + h * math.sin(a)) for a in [i * math.pi / 4 for i in range(8)]])
        for (x0, y0), (x1, y1) in zip(s, s[1:]):
            dx, dy = x1 - x0, y1 - y0
            d = math.hypot(dx, dy)
            if d == 0:
                continue
            nx, ny = -dy / d * h, dx / d * h
            contour(pen, [pt(x0 + nx, y0 + ny), pt(x1 + nx, y1 + ny), pt(x1 - nx, y1 - ny), pt(x0 - nx, y0 - ny)])


def build():
    data = glyphs(SRC)[:95]  # ASCII 32-126
    names, cmap, outlines, metrics = [".notdef"], {}, {}, {}
    pen = TTGlyphPen(None)
    outlines[".notdef"], metrics[".notdef"] = pen.glyph(), (500, 0)
    for i, (left, right, strokes) in enumerate(data):
        code = 32 + i
        name = "uni%04X" % code
        pen = TTGlyphPen(None)
        draw(pen, left, strokes)
        g = pen.glyph()
        g.recalcBounds(None)
        names.append(name)
        cmap[code] = name
        outlines[name] = g
        metrics[name] = ((right - left) * SCALE, getattr(g, "xMin", 0))
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(outlines)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=800, descent=-250)
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-250, usWinAscent=800, usWinDescent=250, sCapHeight=672)
    fb.setupNameTable(
        {
            "familyName": "Hershey Simplex",
            "styleName": "Regular",
            "copyright": "The Hershey Fonts were originally created by Dr. A. V. Hershey while working at the U. S. "
            "National Bureau of Standards. The format of the Font data in this distribution was originally created "
            "by James Hurt, Cognition, Inc.",
            "description": "Roman Simplex (futural.jhf) stroked into outlines by Modern IAF's tools/iaf-2026/hershey_font.py",
        }
    )
    fb.setupPost()
    fb.save(OUT)
    print("%s: %d glyphs, %d bytes" % (os.path.relpath(OUT, ROOT), len(data), os.path.getsize(OUT)))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.exit(__doc__)
    build()
