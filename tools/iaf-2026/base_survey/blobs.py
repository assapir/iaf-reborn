"""Bright compact objects in Sentinel-2 (10 m) inside Ramon's outline: centroid (UTM), area, long axis, elongation."""
import json
import os
import subprocess
import sys

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo import layers  # noqa: E402

D = os.environ["D"]  # the survey's work folder
subprocess.run(["gdal_translate", "-q", "-of", "ENVI", "-ot", "Float32", f"{D}/s2_10m.tif", f"{D}/s2.bin"], check=True)
a = np.fromfile(f"{D}/s2.bin", dtype=np.float32).reshape(800, 700, 4).transpose(2, 0, 1)
br = a[:3].mean(0)
bg = ndimage.median_filter(br, size=9)
diff = br - bg
L = layers()
# inside the outline (point in polygon on pixel centres)
from matplotlib.path import Path  # noqa: E402

ring = np.array(L["boundary"][0])
ys, xs = np.mgrid[0:800, 0:700]
E, N = 655505 + xs * 10, 3408495 - ys * 10
inside = Path(ring).contains_points(np.c_[E.ravel(), N.ravel()]).reshape(800, 700)
thr = float(sys.argv[1]) if len(sys.argv) > 1 else 700
mask = (diff > thr) & inside
lab, n = ndimage.label(mask)
out = []
for i in range(1, n + 1):
    yy, xx = np.nonzero(lab == i)
    if len(yy) > 60:
        continue
    w = diff[yy, xx]
    cx, cy = (xx * w).sum() / w.sum(), (yy * w).sum() / w.sum()
    if len(yy) >= 2:
        c = np.cov(np.vstack([xx, -yy]))
        ev, evec = np.linalg.eigh(c)
        ang = (np.degrees(np.arctan2(evec[0, 1], evec[1, 1]))) % 180  # long axis, from north clockwise
        el = float(np.sqrt(ev[1] / max(ev[0], 1e-3)))
    else:
        ang, el = 0.0, 1.0
    out.append({"e": round(655505 + cx * 10, 1), "n": round(3408495 - cy * 10, 1), "px": int(len(yy)),
                "peak": int(w.max()), "axis": round(float(ang)), "elong": round(el, 2)})
json.dump(out, open(f"{D}/blobs.json", "w"), indent=0)
print(n, len(out))
