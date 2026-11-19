"""plot.py OUT SRC(soi|s2) E0 N0 E1 N1 M_PER_PX [rows.json]: the picture with the base's layers (BASE, D set)."""
import json, math, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo_any import D, layers, extra
out, src, e0, n0, e1, n1, m = sys.argv[1], sys.argv[2], *map(float, sys.argv[3:8])
box = json.load(open(f"{D}/box.json"))
px0 = 2.0 if src == "soi" else 10.0
f = f"{D}/soi_2m.tif" if src == "soi" else f"{D}/s2_rgb.png"
x0, y0 = (e0 - box["e0"]) / px0, (box["n1"] - n1) / px0
w, h = (e1 - e0) / px0, (n1 - n0) / px0
W, H = round((e1 - e0) / m), round((n1 - n0) / m)
look = ["-channel", "RGB", "-contrast-stretch", "1%x1%", "+channel"] if src == "s2" else []
cmd = ["magick", f, "-crop", f"{w:.0f}x{h:.0f}+{x0:.0f}+{y0:.0f}", "+repage", *look, "-filter", "Lanczos",
       "-resize", f"{W}x{H}!", "-fill", "none", "-strokewidth", "1"]
def px(p): return f"{(p[0] - e0) / m:.1f},{(n1 - p[1]) / m:.1f}"
L, X = layers(), extra()
for k, col in {"runway": "red", "taxiway": "cyan", "apron": "yellow", "hangar": "magenta", "boundary": "white"}.items():
    for line in L[k]:
        cmd += ["-stroke", col, "-draw", "polyline " + " ".join(px(p) for p in line)]
for _, r, _, _ in ([] if len(sys.argv) > 8 else X["building"]):
    cmd += ["-stroke", "orange", "-draw", "polyline " + " ".join(px(p) for p in r)]
for r in X["fence"]:
    cmd += ["-stroke", "#c0c0c0", "-draw", "polyline " + " ".join(px(p) for p in r)]
for p in L["parking"]:
    x, y = (p[0] - e0) / m, (n1 - p[1]) / m
    cmd += ["-stroke", "red", "-draw", f"rectangle {x-3:.1f},{y-3:.1f} {x+3:.1f},{y+3:.1f}"]
if len(sys.argv) > 8:
    for i, r in enumerate(json.load(open(sys.argv[8]))):
        if "e" not in r: continue
        x, y = (r["e"] - e0) / m, (n1 - r["n"]) / m
        col = {"shelter": "magenta", "hangar": "orange", "building": "white", "tower": "blue"}.get(r["kind"], "red")
        rad = 2 if r["kind"] == "building" else 5
        cmd += ["-stroke", col, "-draw", f"circle {x:.0f},{y:.0f} {x+rad:.0f},{y:.0f}"]
        if r["kind"] != "building":
            a = math.radians(r["heading"]); cmd += ["-draw", f"line {x:.0f},{y:.0f} {x+12*math.sin(a):.0f},{y-12*math.cos(a):.0f}"]
        if len(sys.argv) > 9:
            cmd += ["-stroke", "none", "-fill", col, "-pointsize", "10", "-draw", f"text {x+6:.0f},{y-4:.0f} '{r.get('ref', i)}'", "-fill", "none"]
if os.environ.get("GRID"):
    cmd += ["-stroke", "#ffffff50", "-strokewidth", "1"]
    for E in range(math.ceil(e0 / 100) * 100, int(e1), 100):
        cmd += ["-draw", f"line {(E - e0) / m:.0f},0 {(E - e0) / m:.0f},{H}"]
    for N in range(math.ceil(n0 / 100) * 100, int(n1), 100):
        cmd += ["-draw", f"line 0,{(n1 - N) / m:.0f} {W},{(n1 - N) / m:.0f}"]
    cmd += ["-stroke", "none", "-fill", "yellow", "-pointsize", "10"]
    for E in range(math.ceil(e0 / 100) * 100, int(e1), 100):
        for N in range(math.ceil(n0 / 100) * 100, int(n1), 100):
            cmd += ["-draw", f"text {(E - e0) / m + 2:.0f},{(n1 - N) / m - 2:.0f} '{E % 10000 // 100},{N % 10000 // 100}'"]
# 500 m labels
cmd += ["-stroke", "none", "-fill", "white", "-pointsize", "11"]
for E in range(math.ceil(e0 / 500) * 500, int(e1), 500):
    for N in range(math.ceil(n0 / 500) * 500, int(n1), 500):
        cmd += ["-draw", f"text {(E - e0) / m:.0f},{(n1 - N) / m:.0f} '+{E % 10000},{N % 10000}'"]
cmd.append(out)
subprocess.run(cmd, check=True)
