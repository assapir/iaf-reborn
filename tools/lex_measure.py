#!/usr/bin/env python3
"""Planform of a jet model, from tests/godot/_lex_dump.gd's triangle dump, in vapour_fx.gd's fractions (z of the
length from the nose, x of the half span, y above the wingtips' height in lengths): per slice along the length the
planform's half width and the top skin's height at its edge, and a top-view height map (PGM) to find the LEX /
chine / canard by eye. vapour_fx.gd LEX holds the measured spots (docs/rendering.md §6 "LEX plume").
  python3 -I tools/lex_measure.py /tmp/lex/f16_h.gltf.json [OUT.pgm [z,x ...]]"""

import json
import sys


def main() -> None:
    d = json.load(open(sys.argv[1]))
    v = d["v"]
    pts = [(v[i], v[i + 1], v[i + 2]) for i in range(0, len(v), 3)]
    (_, by, bz), (sx, sy, sz) = d["box"]
    half = (d["tips"][1][0] - d["tips"][0][0]) / 2
    axis_y = (d["tips"][0][1] + d["tips"][1][1]) / 2
    print(f"nose {bz:.2f} length {sz:.2f} half span {half:.2f} axis_y {axis_y:.2f} eye {d['eye']}")
    # The triangles seen from above into a height map: the top skin's y per pixel (None: nothing there).
    w_px = 400
    scale = w_px / (2 * max(half, sx / 2) * 1.05)
    h_px = int(sz * scale) + 4
    img = [[None] * w_px for _ in range(h_px)]
    for t in range(0, len(pts) - 2, 3):
        tri = [((z - bz) * scale, w_px / 2 + x * scale, y) for x, y, z in pts[t : t + 3]]
        (a0, b0, y0), (a1, b1, y1), (a2, b2, y2) = tri
        den = (a1 - a0) * (b2 - b0) - (a2 - a0) * (b1 - b0)
        if abs(den) < 1e-9:
            continue
        for i in range(max(int(min(a0, a1, a2)), 0), min(int(max(a0, a1, a2)) + 1, h_px)):
            for j in range(max(int(min(b0, b1, b2)), 0), min(int(max(b0, b1, b2)) + 1, w_px)):
                u = ((i - a0) * (b2 - b0) - (a2 - a0) * (j - b0)) / den
                w = ((a1 - a0) * (j - b0) - (i - a0) * (b1 - b0)) / den
                if u >= -0.01 and w >= -0.01 and u + w <= 1.02:
                    y = y0 + u * (y1 - y0) + w * (y2 - y0)
                    if img[i][j] is None or y > img[i][j]:
                        img[i][j] = y
    # Per slice: the right half's outermost pixel, and the skin there and at 0.8 of the way out.
    for k in range(0, 100, 2):
        i = int(sz * k / 100 * scale)
        row = img[min(i, h_px - 1)]
        js = [j for j in range(w_px // 2, w_px) if row[j] is not None]
        if not js:
            continue
        je = js[-1]
        x = (je - w_px / 2) / scale
        mid = row[int(w_px / 2 + x * 0.8 * scale)]
        mid = (mid - axis_y) / sz if mid is not None else float("nan")
        print(f"z {k / 100:.2f}  x {x / half:.3f}  y edge {(row[je] - axis_y) / sz:+.3f}  y 0.8 in {mid:+.3f}")
    # Spots "z,x" (fractions) after the PGM: the top skin's height there (the highest within 0.01 of the length).
    for spot in sys.argv[3:]:
        z, x = map(float, spot.split(","))
        i0, j0, r = int(z * sz * scale), int(w_px / 2 + x * half * scale), max(int(0.01 * sz * scale), 1)
        ys = [img[i][j] for i in range(i0 - r, i0 + r + 1) for j in range(j0 - r, j0 + r + 1)]
        ys = [y for y in ys if y is not None] if 0 <= i0 < h_px else []
        print(f"spot z {z} x {x}: y " + (f"{(max(ys) - axis_y) / sz:+.4f}" if ys else "none"))
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w") as o:
            o.write(f"P2 {w_px} {h_px} 255\n")
            for i, r in enumerate(img):
                # Grid lines every 0.1 of the length and of the half span.
                grid = {int(sz * k / 10 * scale) for k in range(11)}
                cols = {int(w_px / 2 + s * half * k / 10 * scale) for k in range(11) for s in (-1, 1)}
                o.write(
                    " ".join(
                        str(int(40 + 215 * (y - by) / sy)) if y is not None else ("25" if i in grid or j in cols else "0")
                        for j, y in enumerate(r)
                    )
                    + "\n"
                )


main()
