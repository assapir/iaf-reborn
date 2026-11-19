"""Survey crops: Sentinel-2 (10 m) upsampled, OSM layers drawn over. usage: survey.py OUT E0 N0 E1 N1 M_PER_PX [grid]"""
import subprocess
import sys

import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo import layers, extra  # noqa: E402

D = __import__("os").environ["D"]  # the survey's work folder
out, e0, n0, e1, n1, m = sys.argv[1], *map(float, sys.argv[2:7])
grid = len(sys.argv) > 7
# s2_rgb.png: 10 m px, top-left 655500, 3408500
x0, y0 = (e0 - 655500) / 10, (3408500 - n1) / 10
w, h = (e1 - e0) / 10, (n1 - n0) / 10
W, H = round((e1 - e0) / m), round((n1 - n0) / m)
L = layers()


def px(p):
    return f"{(p[0] - e0) / m:.1f},{(n1 - p[1]) / m:.1f}"


cmd = ["magick", f"{D}/s2_rgb.png", "-crop", f"{w:.0f}x{h:.0f}+{x0:.0f}+{y0:.0f}", "+repage", "-filter", "Lanczos",
       "-resize", f"{W}x{H}!", "-level", "5%,95%", "-fill", "none", "-strokewidth", "1"]
style = {"runway": "red", "taxiway": "cyan", "apron": "yellow", "hangar": "magenta", "boundary": "white"}
for k, col in style.items():
    for line in L[k]:
        cmd += ["-stroke", col, "-draw", "polyline " + " ".join(px(p) for p in line)]
for p in L["helipad"]:
    x, y = (p[0] - e0) / m, (n1 - p[1]) / m
    cmd += ["-stroke", "lime", "-draw", f"circle {x:.1f},{y:.1f} {x + 4:.1f},{y:.1f}"]
for p in L["parking"]:
    x, y = (p[0] - e0) / m, (n1 - p[1]) / m
    cmd += ["-stroke", "red", "-draw", f"rectangle {x - 3:.1f},{y - 3:.1f} {x + 3:.1f},{y + 3:.1f}"]
X = extra()
for r in X["road"]:
    cmd += ["-stroke", "#a0a0a0", "-draw", "polyline " + " ".join(px(p) for p in r)]
for _, r in X["building"]:
    cmd += ["-stroke", "orange", "-draw", "polyline " + " ".join(px(p) for p in r)]
for r in X["pv"] + X["helipad_area"]:
    cmd += ["-stroke", "blue", "-draw", "polyline " + " ".join(px(p) for p in r)]
for p in X["gate"]:
    x, y = (p[0] - e0) / m, (n1 - p[1]) / m
    cmd += ["-stroke", "white", "-draw", f"line {x-5:.1f},{y:.1f} {x+5:.1f},{y:.1f}"]
if grid:  # 100 m grid with labels every 500 m
    cmd += ["-stroke", "#ffffff40"]
    import math
    for E in range(math.ceil(e0 / 100) * 100, int(e1), 100):
        cmd += ["-draw", f"line {(E - e0) / m:.1f},0 {(E - e0) / m:.1f},{H}"]
    for N in range(math.ceil(n0 / 100) * 100, int(n1), 100):
        cmd += ["-draw", f"line 0,{(n1 - N) / m:.1f} {W},{(n1 - N) / m:.1f}"]
    cmd += ["-stroke", "none", "-fill", "white", "-pointsize", "11"]
    for E in range(math.ceil(e0 / 100) * 100, int(e1), 100):
        for N in range(math.ceil(n0 / 100) * 100, int(n1), 100):
            if E % 500 == 0 and N % 500 == 0:
                cmd += ["-draw", f"text {(E - e0) / m + 2:.1f},{(n1 - N) / m - 2:.1f} '{E % 10000},{N % 10000}'"]
cmd.append(out)
subprocess.run(cmd, check=True)
