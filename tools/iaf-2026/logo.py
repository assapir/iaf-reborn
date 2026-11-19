#!/usr/bin/env python3
"""Modern IAF's logo (modern-iaf/branding/): the user's pick of 19 Nov 2026, concept 4 "the four-ship" with the
roundel E3, the medium disc (Approvals A67). Four F-35s in finger-four over the two names, a faint roundel centred
behind the jets and the big name. Writes into modern-iaf/branding/:

- lockup_<lang>_<mode>.svg and .png (240 px tall): en = MODERN IAF big, הזרוע הארוכה small; he = the other way
  round; light = for a light background, dark = for a dark one. Transparent, cropped to the drawing.
- bar_<lang>_<mode>.svg and .png (240 px tall): the compact horizontal lockup for a top bar or a small panel: the
  mark (the four-ship over the faint disc, as in the app icon) on the language's leading side (en: left, he: right)
  and the one name beside it in one line (en: MODERN IAF, he: הזרוע הארוכה).
- icon.svg (64 px and up) and icon_small.svg (32 and 16 px: bigger jets), icon_<px>.png at 1024 … 16 px: the
  four-ship and the disc on the navy tile, no text.

Our own drawing: the jets' outline is traced from the game's F-35I model, which is based on andertan's CC BY 4.0
model (docs/credits.md); the letters are the repo's Heebo (OFL) as paths; the roundel is a ring and a six-pointed
star. The colours are the front end's (modern-iaf/menu/look.gd).
Run: python3 -I tools/iaf-2026/logo.py   (needs fontTools, rsvg-convert, ImageMagick)"""
import math
import os
import subprocess
import tempfile

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "modern-iaf/branding")
FONT = os.path.join(ROOT, "modern-iaf/data/fonts/Heebo-VariableFont_wght.ttf")
NAVY, ACCENT, WHITE, MUTED, EDGE = "#001e50", "#5b8cff", "#f2f5fa", "#a9b8d4", "#5a73a3"
HE_SCALE = 1456 / 1178  # Heebo's Hebrew letters are 0.575 em tall, its capitals 0.711 em
LOCKUP_PX = 240  # the lockups' PNG height: the front end's top bar (64 canvas px) on a 4K screen, with room
ICON_PX = (1024, 512, 256, 128, 64, 32, 16)

# The F-35 planform from straight above, traced from shared/extra/planes/f35i/f35i.gltf: nose up, 100 long (y -50..50).
JET = [(-0.14, -49.86), (-0.97, -48.47), (-2.14, -45.8), (-3.17, -42.21), (-3.95, -37.4), (-5.78, -22.87),
       (-6.34, -20.8), (-6.72, -20.73), (-7.37, -21.1), (-9.68, -23.03), (-10.65, -20.41), (-11.05, -17.05),
       (-11.52, -4.65), (-14.01, -0.02), (-34.75, 13.84), (-34.8, 23.78), (-12.05, 29.53), (-13.51, 33.46),
       (-23.45, 40.18), (-23.31, 46), (-6.48, 50), (-5.18, 41.3), (-3.84, 36.74), (-2.64, 39.35), (-2.22, 39.85),
       (-1.89, 39.9), (-1.23, 39.69), (-0.56, 39.89), (-0.05, 39.67), (0.54, 39.89), (1.16, 39.69), (1.62, 39.89),
       (2.22, 39.84), (2.65, 39.33), (3.83, 36.77), (5.17, 41.22), (6.48, 50.01), (23.45, 45.96), (23.45, 40.17),
       (13.56, 33.49), (12, 29.54), (34.73, 23.81), (34.77, 13.84), (13.99, -0.02), (11.54, -4.57), (11.06, -16.97),
       (10.59, -20.58), (9.68, -23.03), (7.36, -21.09), (6.51, -20.66), (6.32, -20.81), (5.78, -22.93), (4.01, -36.83),
       (3.14, -42.33), (2.49, -44.78), (1.57, -47.21), (0.15, -49.9), (0.01, -50.06)]
FINGER4 = [(0, 0), (-0.78, 0.58), (0.78, 0.58), (1.56, 1.16)]  # lead, #2 left behind, #3 and #4 right, in jet lengths


class Face:
    """One weight of Heebo: glyph outlines, advances and the kerning pairs."""

    def __init__(self, w):
        f = instancer.instantiateVariableFont(TTFont(FONT), {"wght": w})
        self.cmap, self.gs, self.upm, self.hmtx = f.getBestCmap(), f.getGlyphSet(), f["head"].unitsPerEm, f["hmtx"]
        self.pairs = []
        gpos = f["GPOS"].table
        idx = {i for fr in gpos.FeatureList.FeatureRecord if fr.FeatureTag == "kern" for i in fr.Feature.LookupListIndex}
        for i in sorted(idx):
            lk = gpos.LookupList.Lookup[i]
            for st in [s.ExtSubTable for s in lk.SubTable] if lk.LookupType == 9 else lk.SubTable:
                if getattr(st, "Coverage", None) is not None and st.__class__.__name__ == "PairPos":
                    self.pairs.append((st, {g: n for n, g in enumerate(st.Coverage.glyphs)}))

    def kern(self, a, b):
        for st, cov in self.pairs:
            if a not in cov:
                continue
            if st.Format == 1:
                for r in st.PairSet[cov[a]].PairValueRecord:
                    if r.SecondGlyph == b:
                        return getattr(r.Value1, "XAdvance", 0) or 0
                continue
            c1, c2 = st.ClassDef1.classDefs.get(a, 0), st.ClassDef2.classDefs.get(b, 0)
            return getattr(st.Class1Record[c1].Class2Record[c2].Value1, "XAdvance", 0) or 0
        return 0

    def run(self, s, size, track=0):
        """The glyphs in visual order (Hebrew reversed) with their x from 0, and the run's width."""
        names = [self.cmap[ord(c)] for c in s]
        if any("֐" <= c <= "׿" for c in s):
            names.reverse()
        sc, x, out = size / self.upm, 0.0, []
        for i, n in enumerate(names):
            out.append((n, x))
            x += self.hmtx[n][0] * sc + track
            if i + 1 < len(names):
                x += self.kern(n, names[i + 1]) * sc
        return out, x - track

    def path(self, n, size, tx, ty):
        sc = size / self.upm
        pen = SVGPathPen(self.gs, ntos=lambda v: f"{v:.2f}".rstrip("0").rstrip("."))
        self.gs[n].draw(TransformPen(pen, (sc, 0, 0, -sc, tx, ty)))
        return pen.getCommands()


_faces = {}


def face(w):
    if w not in _faces:
        _faces[w] = Face(w)
    return _faces[w]


def width(s, w, size, track=0):
    return face(w).run(s, size, track)[1]


def tp(s, w, size, x, y, fill, track=0):
    """One line of text as a path, centred on x, its baseline at y."""
    run, wd = face(w).run(s, size, track)
    d = "".join(face(w).path(n, size, x - wd / 2 + gx, y) for n, gx in run)
    return f'<path fill="{fill}" d="{d}"/>'


def poly(pts):
    return "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + "Z"


def formation(cx, cy, length, fill):
    """The finger-four, nose up, centred on (cx, cy)."""
    x0, x1 = min(p[0] for p in FINGER4) - 0.34, max(p[0] for p in FINGER4) + 0.34
    y0, y1 = -0.5, max(p[1] for p in FINGER4) + 0.5
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    sc = length / 100
    return "".join(
        f'<path fill="{fill}" d="{poly([(cx + (px - mx) * length + sc * x, cy + (py - my) * length + sc * y) for x, y in JET])}"/>'
        for px, py in FINGER4)


def faint(x, y, r, dark):
    """The faint roundel in the accent blue: a tinted disc (on dark only), its ring and its six-pointed star."""
    disc, line = (0.10, 0.22) if dark else (0.0, 0.16)
    star = "".join(poly([(x + r * 0.78 * math.sin(math.radians(a)), y - r * 0.78 * math.cos(math.radians(a)))
                         for a in (a0, a0 + 120, a0 + 240)]) for a0 in (0, 60))
    return (f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{r:.2f}" fill="{ACCENT}" fill-opacity="{disc}"/>'
            f'<g opacity="{line}"><circle cx="{x:.2f}" cy="{y:.2f}" r="{r * 0.93:.2f}" fill="none" stroke="{ACCENT}" '
            f'stroke-width="{r * 0.14:.2f}"/><path fill="{ACCENT}" d="{star}"/></g>')


def lockup(lang, mode):
    """The lockup's drawing (uncropped): the formation, the big name, the two rules and the small name between them,
    and the disc centred between the lead's nose and the small name, as tall as the formation plus the big name."""
    ink, sub = (WHITE, MUTED) if mode == "dark" else (NAVY, EDGE)
    big_en, big_he = ("MODERN IAF", 800, 96, 2), ("הזרוע הארוכה", 800, 96 * HE_SCALE, 0)
    small_en, small_he = ("MODERN IAF", 600, 34, 14), ("הזרוע הארוכה", 600, 34 * HE_SCALE, 3)
    big, small = (big_he, small_en) if lang == "he" else (big_en, small_he)
    wb, ws = width(*big), width(*small)
    cx, jl = (max(wb, ws) + 80) / 2, 72
    dy = 2.16 * (jl - 52)  # the names under the formation, as in concept 4 with its 52-long jets
    cy, r = (6 + 264 + dy) / 2, (216 + dy - 6) / 2 + 4
    rule = max(max(wb, ws) / 2 - ws / 2 - 16, 20)
    return (faint(cx, cy, r, mode == "dark") + formation(cx, 62 + 1.08 * (jl - 52), jl, ACCENT)
            + tp(big[0], big[1], big[2], cx, 216 + dy, ink, big[3])
            + f'<rect x="{cx - wb / 2:.1f}" y="{250 + dy:.1f}" width="{rule:.1f}" height="3" fill="{ACCENT}"/>'
            + f'<rect x="{cx + wb / 2 - rule:.1f}" y="{250 + dy:.1f}" width="{rule:.1f}" height="3" fill="{ACCENT}"/>'
            + tp(small[0], small[1], small[2], cx, 264 + dy, sub, small[3]))


def bar(lang, mode):
    """The horizontal lockup's drawing (uncropped): the mark (the disc, 100 across, and the four-ship as in the app
    icon) on the leading side and the name, its letters 0.44 of the disc tall, centred on the disc."""
    ink = WHITE if mode == "dark" else NAVY
    r, gap, cap = 50, 20, 44
    name = ("הזרוע הארוכה", 800, cap / 0.575, 0) if lang == "he" else ("MODERN IAF", 800, cap / 0.711, 2)
    wn = width(*name)
    cy = 100
    mx, tx = (100 + wn + gap + r, 100 + wn / 2) if lang == "he" else (100, 100 + r + gap + wn / 2)
    return (faint(mx, cy, r, mode == "dark") + formation(mx, cy, r * 66 / 93.6, ACCENT)
            + tp(name[0], name[1], name[2], tx, cy + cap / 2, ink, name[3]))


def icon(small):
    """The app icon on 256 × 256: the navy tile, lit a little from the top so it keeps its edge on a dark desktop, the
    disc and the white four-ship (bigger jets for 32 px and under)."""
    return ('<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#103a86"/>'
            f'<stop offset="1" stop-color="{NAVY}"/></linearGradient></defs>'
            '<rect width="256" height="256" rx="56" fill="url(#tile)"/>'
            + faint(128, 128, 104 * 0.9, True) + formation(128, 128, 72 if small else 66, WHITE))


def svg(box, body, size=None):
    x, y, w, h = box
    pw, ph = size or (w, h)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x:.1f} {y:.1f} {w:.1f} {h:.1f}" width="{pw:.1f}" '
            f'height="{ph:.1f}">{body}</svg>\n')


def crop(body, pad=12):
    """The drawing's box, measured on a render (transparent pixels trimmed), with `pad` units round it."""
    k = 4
    with tempfile.TemporaryDirectory() as tmp:
        src, png = os.path.join(tmp, "a.svg"), os.path.join(tmp, "a.png")
        with open(src, "w", encoding="utf-8") as f:
            f.write(svg((0, 0, 1000, 500), body, (1000 * k, 500 * k)))
        subprocess.run(["rsvg-convert", src, "-o", png], check=True)
        geo = subprocess.run(["magick", png, "-format", "%@", "info:"], check=True, capture_output=True, text=True).stdout
    w, rest = geo.split("x")
    h, x, y = rest.split("+")
    return float(x) / k - pad, float(y) / k - pad, float(w) / k + 2 * pad, float(h) / k + 2 * pad


def write(name, text):
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        f.write(text)


def main():
    os.makedirs(OUT, exist_ok=True)
    for lang in ("en", "he"):
        for kind, draw, pad in (("lockup", lockup, 12), ("bar", bar, 4)):
            for mode in ("light", "dark"):
                body = draw(lang, mode)
                name = f"{kind}_{lang}_{mode}"
                write(name + ".svg", svg(crop(body, pad), body))
                subprocess.run(["rsvg-convert", "-h", str(LOCKUP_PX), os.path.join(OUT, name + ".svg"), "-o",
                                os.path.join(OUT, name + ".png")], check=True)
    for small in (False, True):
        write("icon_small.svg" if small else "icon.svg", svg((0, 0, 256, 256), icon(small)))
    for px in ICON_PX:
        subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), os.path.join(OUT, "icon_small.svg" if px <= 32 else "icon.svg"),
                        "-o", os.path.join(OUT, f"icon_{px}.png")], check=True)


if __name__ == "__main__":
    main()
