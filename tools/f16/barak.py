# The F-16D Barak layer over the F-16 base (base.py; f16d.glb, docs/aircraft-models.md §1): the Block 40's GE F110
# nozzle, the F-16D's three spine vents and FlightGear's IAF livery in the Barak's colours (livery).
import os

import bpy
import kit
import numpy as np
from mathutils import Matrix

import base
from base import CAMO, DIGITS, FG_PAINT, FG_RADOME, FS, RADOME, camo_weights, fg, recolour, skin_bvh, texels, window

# The vents on each side of the dorsal spine ahead of the fin (centre y, width; below the spine's top; height; m).
SPINE_VENTS = ([(-2.80, 0.12), (-3.03, 0.12), (-3.26, 0.12)], 0.18, 0.14)
MATTE = 0.0  # added to the paint's roughness
NUMBER_LUM = 0.25  # the livery's black number: darker than any paint and panel line


def nozzle():
    # F-16.xml's GE_nozzle: its file's own offset taken out (translate -7.74, -1.4827, 1.25336), scaled 0.82 across,
    # then placed 4.61285 m aft, onto the fuselage's nozzle ring.
    noz_m = Matrix.Translation((0, -4.61285, 0)) @ Matrix.Diagonal((0.82, 1.0, 0.82, 1.0)) @ \
        Matrix.Translation(fg((-7.74, -1.4827, 1.25336)))
    noz = kit.import_ac(os.path.join(base.M, "nozzle-GE.ac"), matrix=noz_m, prefix="noz_")
    bpy.data.objects.remove(noz.pop("InNozzleROpen"))
    return noz


def fg_parts(body):
    pass


def own_parts(body):
    pass


# The Barak's camouflage (sRGB 0..1), set against photographs of IAF F-16Ds (SOURCES.md): 027 in sun, 601 under
# cloud. Each tone over the sand in the same light: tan (0.87, 0.70, 0.50) and (0.76, 0.70, 0.66), green (0.93,
# 1.00, 0.98) and (0.87, 0.94, 0.92); the sand itself (1, 0.905, 0.795) in both. The sand is as bright as
# FlightGear's; the tan and green are set so that on screen (the game's tone curve darkens the middle tones: an
# albedo 0.82 of the sand's showed as 0.61) they stand to the sand as in the photos' mean: tan (0.82, 0.70, 0.58),
# green (0.90, 0.97, 0.95). The faded, warm FS 30219 tan, 33531 sand and 34424 grey-green of the jets in service.
BARAK = {"30219": (0.78, 0.64, 0.45), "33531": (0.85, 0.77, 0.675), "34424": (0.80, 0.76, 0.65),
         "36375": FS["36375"]}
BARAK_Z_CAMO = 0.15  # m (our frame): the strakes' height, where the camouflage meets the grey on the sides


def livery(albedo, skin):
    """FlightGear's IAF livery in the Barak's colours (BARAK), its own pattern kept: its brown, sand and pale green
    (which reads light blue) recoloured on the faces looking up or sideways, its grey to FS 36375 below, the radome
    to FS 36270, the stabilators' tops camouflaged."""
    _, tris, uvs = skin_bvh(skin)
    pos, nz = texels(albedo, tris, uvs)
    # Its pale green is nearly its grey: on the skin above the strakes (BARAK_Z_CAMO; camouflaged on the jets down
    # to there, 601) and on faces looking up both become the green; lower on the sides each the nearest;
    # underneath the grey.
    high = (nz > 0.05) | ((nz > -0.35) & (pos[..., 2] > BARAK_Z_CAMO))
    up = [(c, BARAK["34424" if f == "36375" else f]) for c, f in FG_PAINT]
    recolour(albedo, up, 0.16, high)
    recolour(albedo, [(c, BARAK[f]) for c, f in FG_PAINT], 0.16, (nz > -0.35) & ~high)
    recolour(albedo, [(c, BARAK[f]) for c, f in FG_PAINT[3:]], 0.16, nz <= -0.35)  # underneath: grey only
    # The stabilators' tops, grey in the livery, camouflaged as on the jets (027): our pattern (camo_weights) in the
    # Barak's colours over the livery's panel lines.
    stab = [o for o in skin if o.name in ("ElevaL", "ElevaR")]
    _, st, su = skin_bvh(stab)
    up = [i for i, t in enumerate(st) if (t[1] - t[0]).cross(t[2] - t[0]).normalized().z > 0.3]
    spos, _ = texels(albedo, [st[i] for i in up], [su[i] for i in up])
    top = ~np.isnan(spos[..., 0])
    lum = albedo[..., :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    detail = np.clip(lum / np.maximum(window(window(lum, 5, np.maximum), 5, np.minimum), 1e-3), 0.55, 1.0)
    albedo[top, :3] = (camo_weights(spos[top]) @ np.array([BARAK[c] for c in CAMO], dtype=np.float32)) * \
        detail[top][:, None]
    print("barak: stabilator tops painted, texels", int(top.sum()), "objects", [o.name for o in stab])
    h, w = albedo.shape[:2]
    yy, xx = np.mgrid[h - 1:-1:-1, 0:w]
    for x0, y0, x1, y1 in RADOME:
        recolour(albedo, [(FG_RADOME, FS["36270"])], 0.12, (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1))
    erase_number(albedo, xx, yy, pos)
    return albedo


def erase_number(albedo, xx, yy, pos):
    """The livery's 547 on the fin (DIGITS) painted over: the game draws each jet's own number there (f16d.tail.json,
    docs/aircraft-models.md §1.6). Its dark strokes and the pixels round them are filled in from round them, each
    then the nearest of the Barak's camouflage colours."""
    box = np.zeros(albedo.shape[:2], dtype=bool)
    for x0, y0, x1, y1 in DIGITS:
        box |= (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
    lum = albedo[..., :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    hole = box & (window(np.where(lum < NUMBER_LUM, 1.0, 0.0), 5, np.maximum) > 0)
    for x0, y0, x1, y1 in DIGITS:  # where the number was, for its tail file's mark (world, m)
        b = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1) & hole
        print("barak: the livery's number", (x0, y0), "from", np.nanmin(pos[b], axis=0), "to",
              np.nanmax(pos[b], axis=0))
    done = ~hole
    while not done.all():
        p = np.pad(np.where(done[..., None], albedo[..., :3], 0), ((1, 1), (1, 1), (0, 0)))
        c = np.pad(done.astype(np.float32), 1)
        n = c[:-2, 1:-1] + c[2:, 1:-1] + c[1:-1, :-2] + c[1:-1, 2:]
        s = p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
        grow = ~done & (n > 0)
        albedo[grow, :3] = s[grow] / n[grow][:, None]
        done |= grow
    camo = np.array([BARAK[c] for c in CAMO], dtype=np.float32)
    albedo[hole, :3] = camo[np.linalg.norm(albedo[hole, None, :3] - camo[None], axis=2).argmin(axis=1)]
    print("barak: the livery's number painted over, texels", int(hole.sum()))
