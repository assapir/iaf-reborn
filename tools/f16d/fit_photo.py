#!/usr/bin/env python3
# The camera of a seat-level F-16 cockpit photo fitted to the 3D cockpit (modern-iaf/docs/cockpit.md "The MFDs from the
# seat"): the photo's landmarks (PHOTO, px) against the same points of f16.glb as modern-iaf/tests/_mfd_osb_shot.gd
# prints them (OSB / NODE lines, the model's frame: x right, y up, z aft, m). Solves the camera's place, yaw, pitch,
# roll and vertical field of view on the FIT points (least squares, the principal point at the photo's centre), then
# prints each point's residual (px), the CHECK points' too, and the SHOT_CAM line for the helper's fit render.
#   python3 -I tools/f16d/fit_photo.py <the helper's output> [jet]
import sys

import numpy as np

# Wikimedia Commons File:F-16C_cockpit_m02006112700032.jpg (US Air Force, public domain), 360 x 342 px: the F-16C's
# front cockpit from about the seat's eye. Each point's centre read at 8x zoom (a button's lit face, ±0.5 px).
SIZE = (360, 342)
PHOTO = {
    # the MFDs' push buttons (the brightness peaks along each row and column): top row T1..T5, bottom B1..B5, the
    # outboard column (left MFD L, right MFD R) 1..5; the inboard columns stand against the ICP's lit edge, left out
    **{"MFD_L_T%d" % (i + 1): (x, 147.3) for i, x in enumerate((105.7, 111.8, 117.7, 123.8, 129.8))},
    **{"MFD_L_B%d" % (i + 1): (x, 191.5) for i, x in enumerate((107.6, 113.5, 119.5, 125.2, 131.0))},
    **{"MFD_L_L%d" % (i + 1): (96.5, y) for i, y in enumerate((159.0, 164.5, 170.0, 175.0, 180.5))},
    **{"MFD_R_T%d" % (i + 1): (x, 147.3) for i, x in enumerate((228.5, 234.8, 240.8, 246.5, 252.5))},
    **{"MFD_R_B%d" % (i + 1): (x, 191.5) for i, x in enumerate((227.3, 233.0, 239.0, 245.0, 251.0))},
    **{"MFD_R_R%d" % (i + 1): (262.0, y) for i, y in enumerate((159.5, 164.5, 170.0, 175.5, 180.5))},
    # the ICP's six round buttons, left to right
    "com1": (154.4, 114.4), "com2": (164.4, 114.4), "ICP_iff": (175.0, 114.4), "list": (185.6, 114.4),
    "a-a": (195.6, 114.4), "a-g": (205.6, 114.4),
    # the dials' hubs under the ICP (the ASI's and the altimeter's needles, the ADI's ball) and the DED's centre
    "anim089@pivot": (163.5, 190.0), "anim202@pivot": (195.0, 190.0), "anim096@pivot": (180.0, 222.5),
    "DED_screen": (245.0, 117.0),
}
# The groups the residuals are given by.
GROUPS = {"MFDs": "MFD_", "ICP": ("com", "ICP_", "list", "a-"), "dials": "anim", "DED": "DED"}


def read(path, jet):
    pts, eye = {}, None
    for line in open(path):
        w = line.split()
        if len(w) < 5 or w[1] != jet:
            continue
        if w[0] == "EYE":
            eye = np.array([float(x) for x in w[2:5]])
        elif w[0] in ("OSB", "NODE", "PIVOT"):
            pts[w[2] + ("@pivot" if w[0] == "PIVOT" else "")] = np.array([float(x) for x in w[3:6]])
    return pts, eye


def rot(yaw, pitch, roll):
    """Godot's Basis.from_euler((pitch, -yaw, roll), YXZ): Ry · Rx · Rz."""
    cy, sy = np.cos(-yaw), np.sin(-yaw)
    cx, sx = np.cos(pitch), np.sin(pitch)
    cz, sz = np.cos(roll), np.sin(roll)
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return ry @ rx @ rz


def project(p, P):
    c, (yaw, pitch, roll, fov) = p[:3], p[3:]
    q = (P - c) @ rot(yaw, pitch, roll)  # each row R^T (P - c)
    f = SIZE[1] / 2 / np.tan(fov / 2)
    return np.stack([SIZE[0] / 2 + f * q[:, 0] / -q[:, 2], SIZE[1] / 2 - f * q[:, 1] / -q[:, 2]], 1)


def solve(P, uv, p):
    """Levenberg-Marquardt: a step kept only when it lowers the squared residual."""
    cost = lambda q: ((project(q, P) - uv) ** 2).sum()  # noqa: E731
    lam = 1e-2
    for _ in range(500):
        r = (project(p, P) - uv).ravel()
        J = np.empty((r.size, p.size))
        for k in range(p.size):
            d = np.zeros(p.size)
            d[k] = 1e-6
            J[:, k] = ((project(p + d, P) - uv).ravel() - r) / 1e-6
        A = J.T @ J
        step = np.linalg.solve(A + lam * np.diag(np.diag(A)), -J.T @ r)
        if cost(p + step) < cost(p):
            p, lam = p + step, lam / 3
            if np.abs(step).max() < 1e-10:
                break
        else:
            lam *= 4
    return p


def main():
    jet = sys.argv[2] if len(sys.argv) > 2 else "f16i"
    pts, eye = read(sys.argv[1], jet)
    names = [k for k in PHOTO if k in pts]
    P = np.array([pts[k] for k in names])
    uv = np.array([PHOTO[k] for k in names])
    p = solve(P, uv, np.array([*eye, 0.0, np.radians(-25), 0.0, np.radians(60)]))
    d = project(p, P) - uv
    res = np.linalg.norm(d, axis=1)
    print("camera %s: %.3f %.3f %.3f m, yaw %.2f pitch %.2f roll %.2f deg, vfov %.1f deg; off the seat's eye %s m" % (
        jet, *p[:3], *np.degrees(p[3:]), np.round(p[:3] - eye, 3)))
    for k, e, dd in zip(names, res, d):
        print("  %-14s %5.2f px (%+.1f %+.1f)" % (k, e, *dd))
    for g, pre in GROUPS.items():
        m = np.array([k.startswith(pre) for k in names])
        if m.any():
            print("  %-6s rms %.2f px, mean %+.1f %+.1f px" % (g, np.sqrt((res[m] ** 2).mean()), *d[m].mean(0)))
    print("  all    rms %.2f px, max %.2f px (the photo %d px wide)" % (np.sqrt((res ** 2).mean()), res.max(), SIZE[0]))
    print("SHOT_CAM=\"%.4f %.4f %.4f %.3f %.3f %.3f %.3f\"" % (*p[:3], *np.degrees(p[3:])))


main()
