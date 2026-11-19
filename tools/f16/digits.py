# Our digits for the jets' tail numbers (a plain rounded sans, as F-16I 846's: docs/f16i.md §8.1) and the strokes the
# Sufa's fin art shares (sufa.py). Run as a script it writes the digit atlas the game draws every jet's number from
# (shared/aircraft/tail_number.gd, docs/aircraft-models.md "Tail numbers"):
#
#   python3 -I tools/f16/digits.py shared/extra/models/tail_digits.png
#   python3 -I tools/f16/digits.py shared/extra/models/tail_digits_thin.png thin
#
# numpy only (no Blender), so the atlas can be made without the model build.
import struct
import sys
import zlib

import numpy as np


def ellipse(cx, cy, rx, ry, a0=0.0, a1=360.0, n=40):
    t = np.radians(np.linspace(a0, a1, n))
    return list(zip(cx + rx * np.cos(t), cy + ry * np.sin(t)))


def near_line(pts, line, widths):
    """The points [n, 2] within half the local width of the polyline (widths per point, m)."""
    line, widths = np.array(line, dtype=np.float32), np.array(widths, dtype=np.float32)
    out = np.zeros(len(pts), dtype=bool)
    for a, b, wa, wb in zip(line[:-1], line[1:], widths[:-1], widths[1:]):
        d = b - a
        t = np.clip(((pts - a) @ d) / max(float(d @ d), 1e-9), 0, 1)
        out |= np.linalg.norm(pts - (a + t[:, None] * d), axis=1) < (wa + (wb - wa) * t) / 2
    return out


# Centre lines in a unit box (0..1 across, 0..1 up). 8, 4 and 6 traced from 846's photos (SOURCES.md); the others ours
# in the same hand; 9 is the 6 turned half round.
SIX = [ellipse(0.5, 0.3, 0.5, 0.3), [(0.0, 0.3), (0.03, 0.58), (0.14, 0.8), (0.35, 0.96), (0.62, 1.0), (0.9, 0.93)]]
GLYPHS = {
    "0": [ellipse(0.5, 0.5, 0.5, 0.5)],
    "1": [[(0.2, 0.78), (0.62, 1.0), (0.62, 0.0)]],
    "2": [ellipse(0.5, 0.7, 0.5, 0.3, 165, -35) + [(0.0, 0.0), (1.0, 0.0)]],
    "3": [ellipse(0.5, 0.76, 0.44, 0.24, 160, -90), ellipse(0.5, 0.27, 0.5, 0.27, 90, -160)],
    "4": [[(0.74, 0.0), (0.74, 1.0), (0.0, 0.3), (1.0, 0.3)]],
    "5": [[(0.92, 1.0), (0.12, 1.0), (0.06, 0.56)] + ellipse(0.5, 0.32, 0.5, 0.32, 140, -150)],
    "6": SIX,
    "7": [[(0.0, 1.0), (1.0, 1.0), (0.32, 0.0)]],
    "8": [ellipse(0.5, 0.77, 0.42, 0.23), ellipse(0.5, 0.27, 0.5, 0.27)],
    "9": [[(1.0 - u, 1.0 - v) for u, v in line] for line in SIX],
}
# A digit's box: width and stroke as fractions of its height (846's on the fin: 0.19 m wide, 0.05 m strokes, 0.37 m
# tall).
WIDTH, STROKE = 0.19 / 0.37, 0.05 / 0.37
# The thin style, as 109 Squadron's F-16Ds wear it (034 and 027, docs/aircraft-models.md §1.6): narrow and light,
# measured on 034's fin (0.12 m wide, 0.024 m strokes, 0.31 m tall); its 0 has straight sides. The other centre lines
# as above.
THIN_WIDTH, THIN_STROKE = 0.12 / 0.31, 0.024 / 0.31
THIN = dict(GLYPHS, **{"0": [ellipse(0.5, 0.75, 0.5, 0.25, 0, 180) + ellipse(0.5, 0.25, 0.5, 0.25, 180, 360)
                             + [(1.0, 0.75)]]})


def text_ink(uv, text, height, width, pitch, stroke, glyphs=GLYPHS):
    """The points uv [n, 2] (m, across and up from the middle of the text's foot) on the text's strokes."""
    out = np.zeros(len(uv), dtype=bool)
    for k, ch in enumerate(text):
        x0 = (k - (len(text) - 1) / 2) * pitch - width / 2 + stroke / 2
        for line in glyphs[ch]:
            pts = [(x0 + u * (width - stroke), stroke / 2 + v * (height - stroke)) for u, v in line]
            out |= near_line(uv, pts, [stroke] * len(pts))
    return out


def atlas(cell_h=128, ss=4, width=WIDTH, stroke=STROKE, glyphs=GLYPHS):
    """0..9 left to right, each in a cell `width` × 1 of the height, white with the strokes' coverage as alpha
    (ss × ss samples a pixel): rows of RGBA bytes."""
    cw = round(cell_h * width)
    h, w = cell_h * ss, cw * ss
    yy, xx = np.mgrid[0:h, 0:w]
    uv = np.column_stack([((xx.ravel() + 0.5) / w - 0.5) * width, 1.0 - (yy.ravel() + 0.5) / h]).astype(np.float32)
    cells = []
    for ch in "0123456789":
        ink = text_ink(uv, ch, 1.0, width, 0.0, stroke, glyphs).reshape(h, w).astype(np.float32)
        cells.append(ink.reshape(cell_h, ss, cw, ss).mean(axis=(1, 3)))
    a = (np.concatenate(cells, axis=1) * 255).round().astype(np.uint8)
    rgba = np.dstack([np.full_like(a, 255)] * 3 + [a])
    return rgba


def write_png(path, rgba):
    h, w = rgba.shape[:2]
    raw = b"".join(b"\0" + rgba[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    thin = sys.argv[2:] == ["thin"]
    write_png(sys.argv[1], atlas(width=THIN_WIDTH, stroke=THIN_STROKE, glyphs=THIN) if thin else atlas())
