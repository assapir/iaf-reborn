# The F-35I cockpit panel (our own art, docs/f35i.md §4): the strip the game draws under the 3D view, in panel
# px x4 (1920 x 352 -> 7680 x 1408, like the converted cockpits): the matte glareshield coaming, the panel body
# with the panoramic display's bezel and glass (the four portals are the game's MFDs drawn over it, cockpit.json
# [MFD] Portals), the standby display (its ball is the game's lens ADI drawn behind a hole), the gear handle and a
# few switches, the canopy sills to both sides. Transparent where the world shows.
#
#   blender -b --python tools/f35i/make_panel.py -- <cockpit dir>
#
# Writes <dir>/f35panel.png, the lights bitmap <dir>/f35lights.png (frames stacked as the game reads them, docs/cockpit.md
# "Panel lights") and the [LIGHTSON] / [LIGHT000..009] / [SLIGHT000..003] / [PANELST] sections of <dir>/cockpit.json.
import json
import math
import os
import sys

import bpy
import numpy as np

OUT_DIR = sys.argv[sys.argv.index("--") + 1]
K = 4  # art px per panel px
W, H = 1920, 352

# Layout (panel px), shared with cockpit.json.
COAMING_X = (560.0, 1360.0)
PCD_BEZEL = (646.0, 44.0, 1274.0, 292.0)
PCD_GLASS = (654.0, 52.0, 1266.0, 284.0)
PORTAL_LINE_Y = 208.0
ESIS_BEZEL = (922.0, 294.0, 998.0, 348.0)
ESIS_CENTRE, ESIS_R = (960.0, 321.0), 22.0


def coaming_top(x):
    """The panel's top edge: a gently curved glareshield, then the sills running down to the strip's ends."""
    u = (x - 960.0) / 400.0
    top = 10.0 + 18.0 * u ** 4
    side_l = 28.0 + (COAMING_X[0] - x) / COAMING_X[0] * 202.0
    side_r = 28.0 + (x - COAMING_X[1]) / (W - COAMING_X[1]) * 202.0
    return np.where(x < COAMING_X[0], side_l, np.where(x > COAMING_X[1], side_r, top))


def rrect(px, py, r, rad):
    """Coverage (0..1, antialiased) of a rounded rect r = (x0, y0, x1, y1) with corner radius `rad`."""
    x0, y0, x1, y1 = r
    cx = np.clip(px, x0 + rad, x1 - rad)
    cy = np.clip(py, y0 + rad, y1 - rad)
    d = np.hypot(px - cx, py - cy) - rad
    return np.clip(0.5 - d * K, 0.0, 1.0)


def disc(px, py, c, rad):
    return np.clip(0.5 - (np.hypot(px - c[0], py - c[1]) - rad) * K, 0.0, 1.0)


def main():
    ys, xs = np.mgrid[0:H * K, 0:W * K].astype(np.float32)
    px = (xs + 0.5) / K
    py = (ys + 0.5) / K
    rng = np.random.default_rng(35)
    noise = rng.normal(0.0, 1.0, px.shape).astype(np.float32)

    top = coaming_top(px)
    alpha = np.clip(0.5 + (py - top) * K, 0.0, 1.0)
    inside = (px >= COAMING_X[0]) & (px <= COAMING_X[1])

    # Body: dark grey, darker towards the bottom; fine grain.
    rgb = np.empty(px.shape + (3,), np.float32)
    g = 46.0 - 16.0 * (py / H)
    rgb[..., 0] = g
    rgb[..., 1] = g + 2.0
    rgb[..., 2] = g + 5.0
    # Side sills (canopy rails): lighter, a highlight along the top edge and a dark rail line under it.
    sill = ~inside
    d = py - top
    sill_tone = 64.0 - 10.0 * np.clip(d / 120.0, 0.0, 1.0)
    for c, add in ((0, 0.0), (1, 2.0), (2, 4.0)):
        rgb[..., c] = np.where(sill, sill_tone + add, rgb[..., c])
    hi = sill & (d < 3.0)
    rgb[hi] = (96.0, 98.0, 102.0)
    rail = sill & (d > 9.0) & (d < 13.0)
    rgb[rail] = (24.0, 25.0, 27.0)
    # Glareshield coaming: matte anti-glare black-grey with a lighter lip.
    coam = inside & (d < 28.0)
    rgb[coam] = (21.0, 22.0, 24.0)
    lip = inside & (d >= 26.0) & (d < 29.0)
    rgb[lip] = (58.0, 60.0, 64.0)
    rgb += noise[..., None] * 1.6

    def paint(cov, colour):
        nonlocal rgb
        rgb = rgb * (1.0 - cov[..., None]) + np.array(colour, np.float32) * cov[..., None]

    # Panoramic display: bezel, glass (a faint top-to-bottom sheen), portal frames and the lower window strip.
    paint(rrect(px, py, PCD_BEZEL, 10.0), (15.0, 16.0, 18.0))
    glass = rrect(px, py, PCD_GLASS, 4.0)
    sheen = 10.0 + 6.0 * (1.0 - (py - PCD_GLASS[1]) / (PCD_GLASS[3] - PCD_GLASS[1]))
    paint(glass, (0, 0, 0))
    rgb += (glass * np.clip(sheen, 0, 16))[..., None] * np.array([0.55, 0.6, 0.7], np.float32)
    line = (glass > 0.5) & (np.abs(py - PORTAL_LINE_Y) < 0.6)
    for x in (807.0, 960.0, 1113.0):
        line |= (glass > 0.5) & (np.abs(px - x) < 0.6) & (py < PORTAL_LINE_Y)
    rgb[line] = (30.0, 33.0, 37.0)
    for i in range(8):
        x0 = PCD_GLASS[0] + 6 + i * 75.5
        cov = rrect(px, py, (x0, PORTAL_LINE_Y + 6, x0 + 69.0, PCD_GLASS[3] - 6), 2.0)
        edge = cov - rrect(px, py, (x0 + 1, PORTAL_LINE_Y + 7, x0 + 68.0, PCD_GLASS[3] - 7), 2.0)
        rgb += np.clip(edge, 0, 1)[..., None] * np.array([22.0, 26.0, 30.0], np.float32)

    # Standby display: bezel and the hole the lens ADI shows through.
    paint(rrect(px, py, ESIS_BEZEL, 6.0), (15.0, 16.0, 18.0))
    hole = disc(px, py, ESIS_CENTRE, ESIS_R)
    ring = disc(px, py, ESIS_CENTRE, ESIS_R + 2.0) - hole
    paint(np.clip(ring, 0, 1), (70.0, 72.0, 76.0))
    alpha = alpha * (1.0 - hole)

    # Switches left of the display; the gear handle slot (the handle itself is LIGHT009) and the lamp bays.
    for k in range(4):
        cy = 70.0 + k * 40.0
        paint(disc(px, py, (578.0, cy), 7.0), (12.0, 12.0, 13.0))
        paint(disc(px, py, (576.5, cy - 1.5), 3.0), (88.0, 90.0, 94.0))
    paint(rrect(px, py, (589.0, 114.0, 617.0, 186.0), 4.0), (24.0, 25.0, 27.0))
    paint(rrect(px, py, (1288.0, 50.0, 1344.0, 196.0), 4.0), (24.0, 25.0, 27.0))
    paint(rrect(px, py, (616.0, 114.0, 645.0, 148.0), 3.0), (24.0, 25.0, 27.0))
    paint(rrect(px, py, (596.0, 196.0, 636.0, 214.0), 3.0), (24.0, 25.0, 27.0))
    for k in range(3):
        cy = 222.0 + k * 22.0
        paint(disc(px, py, (1316.0, cy), 7.0), (12.0, 12.0, 13.0))
        paint(disc(px, py, (1314.5, cy - 1.5), 3.0), (88.0, 90.0, 94.0))

    # The sills: a console plate along each (switch rows), the throttle on the left, the side-stick on the right,
    # a rivet line along the rail.
    for side in (-1, 1):
        mx = 960.0 + side * (960.0 - px)  # mirrored x: the left sill's frame for both sides
        t = coaming_top(np.where(side < 0, px, 1920.0 - px))
        on = (px < COAMING_X[0]) if side < 0 else (px > COAMING_X[1])
        dd = py - t
        plate = on & (dd > 22.0) & (dd < 66.0) & (np.where(side < 0, px, 1920.0 - px) > 90.0)
        rgb[plate] = rgb[plate] * 0.55
        for i in range(10):
            xx = 140.0 + i * 38.0
            xs_ = xx if side < 0 else 1920.0 - xx
            yy = float(coaming_top(np.float32(xx))) + 34.0
            paint(rrect(px, py, (xs_ - 9.0, yy, xs_ + 9.0, yy + 7.0), 1.5), (78.0, 80.0, 84.0))
            paint(rrect(px, py, (xs_ - 2.0, yy + 13.0, xs_ + 2.0, yy + 22.0), 1.0), (150.0, 152.0, 156.0))
        for i in range(17):
            xx = 30.0 + i * 31.0
            xs_ = xx if side < 0 else 1920.0 - xx
            yy = float(coaming_top(np.float32(xx))) + 6.0
            paint(disc(px, py, (xs_, yy), 1.6), (110.0, 112.0, 116.0))
    # Throttle (left) and side-stick (right) grips rising from the consoles.
    for cx, top_x in ((482.0, 482.0), (1438.0, 482.0)):
        y0 = float(coaming_top(np.float32(top_x))) + 18.0
        paint(rrect(px, py, (cx - 16.0, y0, cx + 16.0, y0 + 64.0), 9.0), (34.0, 35.0, 38.0))
        paint(rrect(px, py, (cx - 12.0, y0 + 4.0, cx + 12.0, y0 + 30.0), 7.0), (62.0, 64.0, 68.0))
        for bx, by in ((-5.0, 11.0), (5.0, 11.0), (0.0, 20.0)):
            paint(disc(px, py, (cx + bx, y0 + by), 2.4), (20.0, 20.0, 22.0))

    save(os.path.join(OUT_DIR, "f35panel.png"), np.dstack([np.clip(rgb / 255.0, 0, 1), alpha]))
    lights()


def save(path, rgba):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()


# A 5x7 pixel font for the lamp labels.
FONT = {
    "A": ".###.#...##...#######...##...##...#", "B": "####.#...##...#####.#...##...#####.",
    "C": ".#####....#....#....#....#.....####", "D": "####.#...##...##...##...##...#####.",
    "E": "######....#....####.#....#....#####",
    "F": "######....#....####.#....#....#....", "G": ".#####....#....#.####...##...#.####",
    "I": ".###...#....#....#....#....#...###.", "K": "#...##..#.#.#..##...#.#..#..#.#...#",
    "L": "#....#....#....#....#....#....#####", "M": "#...###.###.#.##.#.##...##...##...#",
    "N": "#...###..##.#.##..###...##...##...#", "O": ".###.#...##...##...##...##...#.###.",
    "P": "####.#...##...#####.#....#....#....", "R": "####.#...##...#####.#.#..#..#.#...#",
    "S": ".#####....#.....###.....#....#####.", "T": "#####..#....#....#....#....#....#..",
    "U": "#...##...##...##...##...##...#.###.", " ": "...................................",
}


def text(img, x, y, s, colour):
    """Pixel text (1 font px = K art px) into an (h, w, 4) art image at panel px (x, y)."""
    for n, ch in enumerate(s):
        g = FONT[ch]
        for r in range(7):
            for c in range(5):
                if g[r * 5 + c] == "#":
                    x0, y0 = int((x + n * 6 + c) * K), int((y + r) * K)
                    img[y0:y0 + K, x0:x0 + K] = (*colour, 1.0)


def lamp(img, x, y, w, h, label, colour, lit):
    """A lamp tile at atlas px (x, y): a dark lens, its label dim when off, the lens glowing `colour` when lit."""
    x0, y0, x1, y1 = int(x * K), int(y * K), int((x + w) * K), int((y + h) * K)
    img[y0:y1, x0:x1] = (0.07, 0.07, 0.08, 1.0)
    img[y0 + K:y1 - K, x0 + K:x1 - K] = (*(np.array(colour) * (0.85 if lit else 0.12) + 0.03), 1.0)
    if label:
        tw = len(label) * 6 - 1
        text(img, x + (w - tw) / 2.0, y + (h - 7) / 2.0, label,
             (0.08, 0.06, 0.04) if lit else tuple(np.array(colour) * 0.45 + 0.1))


def lights():
    """The lights bitmap and its cockpit.json sections. Frames stack downwards under each light's Top."""
    AW, AH = 120, 190
    img = np.zeros((AH * K, AW * K, 4), np.float32)
    img[..., :3] = (0.0, 1.0, 1.0)  # colour key (cyan) = transparent
    sec = {"LIGHTSON": {"FileName": "f35lights.bmp", "Width": float(AW), "Height": float(AH),
                        "NightRScale": 1.0, "NightGScale": 1.0, "NightBScale": 1.0}}
    amber, red, green = (1.0, 0.62, 0.05), (1.0, 0.12, 0.08), (0.2, 1.0, 0.25)
    # Caution lamps right of the display (LIGHT i: label, colour); LIGHT002 (right engine fire) and 007 (hook) off.
    cautions = [(0, "CAUTION", amber), (1, "FIRE", red), (3, "AI", red), (4, "SAM", red), (5, "SPD BRK", green),
                (6, "ECM", green), (8, "AP", green)]
    for n, (i, label, col) in enumerate(cautions):
        ax, ay = 0, n * 24
        lamp(img, ax, ay, 44, 12, label, col, False)
        lamp(img, ax, ay + 12, 44, 12, label, col, True)
        sec["LIGHT%03d" % i] = {"Active": 1.0, "Left": float(ax), "Top": float(ay), "Right": float(ax + 44),
                                "Bottom": float(ay + 12), "OffsetX": 1294.0, "OffsetY": 54.0 + n * 20.0}
        if i == 1:
            sec["LIGHT001"]["Blink"] = 1.0
    sec["LIGHT002"] = {"Active": 0.0}
    sec["LIGHT007"] = {"Active": 0.0}
    # Gear lamps (nose, left, right): unlit / red in transit / green down and locked; then the flaps lamp.
    for j, (gx, gy, label) in enumerate(((626.0, 118.0, "N"), (619.0, 134.0, "L"), (633.0, 134.0, "R"))):
        ax, ay = 48, j * 30
        for f, col in enumerate(((0.3, 0.3, 0.3), red, green)):
            lamp(img, ax, ay + f * 10, 10, 10, "", col, f > 0)
        sec["SLIGHT%03d" % j] = {"Active": 1.0, "Left": float(ax), "Top": float(ay), "Right": float(ax + 10),
                                 "Bottom": float(ay + 10), "OffsetX": gx, "OffsetY": gy}
    ax, ay = 48, 96
    for f, col in enumerate(((0.3, 0.3, 0.3), amber, green)):
        lamp(img, ax, ay + f * 12, 34, 12, "FLAPS", col, f > 0)
    sec["SLIGHT003"] = {"Active": 1.0, "Left": float(ax), "Top": float(ay), "Right": float(ax + 34),
                        "Bottom": float(ay + 12), "OffsetX": 599.0, "OffsetY": 199.0}
    # Gear handle (LIGHT009): frame 0 up .. 2 down; a lever with the wheel-shaped knob (lit red while moving).
    ax, hw, hh = 90, 24, 60
    yy, xx = np.mgrid[0:hh * K, 0:hw * K]
    fx, fy = (xx + 0.5) / K, (yy + 0.5) / K
    for f in range(3):
        tile = np.zeros((hh * K, hw * K, 4), np.float32)
        tile[..., :3] = (0.0, 1.0, 1.0)
        knob_y = 10.0 + f * 20.0
        bar = (np.abs(fx - hw / 2) < 2.2) & (fy > min(knob_y, 30.0)) & (fy < max(knob_y, 30.0) + 2)
        tile[bar] = (0.55, 0.56, 0.55, 1.0)
        knob = np.hypot(fx - hw / 2, fy - knob_y) < 9.0
        tile[knob] = (0.82, 0.83, 0.80, 1.0)
        tile[np.hypot(fx - hw / 2, fy - knob_y) < 4.5] = (0.6, 0.12, 0.1, 1.0) if f == 1 else (0.35, 0.36, 0.36, 1.0)
        img[f * hh * K:(f + 1) * hh * K, ax * K:(ax + hw) * K] = tile
    sec["LIGHT009"] = {"Active": 1.0, "Left": float(ax), "Top": 0.0, "Right": float(ax + hw), "Bottom": float(hh),
                       "OffsetX": 591.0, "OffsetY": 120.0, "AnimFrames": 3.0, "AnimTime": 600.0}
    save(os.path.join(OUT_DIR, "f35lights.png"), img)
    # PANELST (unused by the exe, docs/cockpit.md): the top edge at x = 0, 120, ..., 1800.
    sec["PANELST"] = {"OFFSET%02d" % i: float(round(float(coaming_top(np.float32(x))))) for i, x in enumerate(range(0, 1920, 120))}
    path = os.path.join(OUT_DIR, "cockpit.json")
    c = json.load(open(path))
    for k in [k for k in c if k.startswith(("LIGHT", "SLIGHT"))]:
        del c[k]
    c.update(sec)
    json.dump(c, open(path, "w"), indent=1)
    print("LIGHTS", sorted(k for k in sec if "LIGHT" in k))


main()
