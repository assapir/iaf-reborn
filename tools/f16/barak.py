# The F-16D Barak layer over the F-16 base (base.py; f16d.glb, docs/aircraft-models.md §1): the Block 40's GE F110
# nozzle, the F-16D's three spine vents and FlightGear's IAF livery in the Barak's colours (livery), its fin
# repainted as F-16D 034 of 109 Squadron wears it (fin); the game draws each jet's squadron art and number.
import os

import bpy
import kit
import numpy as np
from mathutils import Matrix

import base
from base import (CAMO, FG_PAINT, FG_RADOME, FS, RADOME, camo_weights, fg, inside, is_fin, old_fin_marks, recolour,
                  skin_bvh, texels, window)

# The vents on each side of the dorsal spine ahead of the fin (centre y, width; below the spine's top; height; m).
SPINE_VENTS = ([(-2.80, 0.12), (-3.03, 0.12), (-3.26, 0.12)], 0.18, 0.14)
MATTE = 0.0  # added to the paint's roughness


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
# The fin (and rudder) as F-16D 034 of 109 Squadron wears it (Wikimedia Commons, F-16D--Our-IDF-2018-IZE-239.jpg,
# its left side; 027's right side the same: RamatDavid 020517 Barak 02.jpg), measured on the photo laid onto our fin
# (y forward, z up, m; docs/aircraft-models.md §1.6): tan, grey-green over the top from about 2.8 m up at the leading
# edge, dipping under the badge's aft half to 2.45 m at the trailing edge, and a sand dome on the root's aft half.
# The squadron's art and the number are the game's (f16d.tail.json), so each jet shows its own squadron's.
BARAK_FIN_BASE = "30219"
# The livery's skull (101 Squadron's art, in its camouflage colours) reaches past base.BADGES' circle: painted over
# whole on each side (circles x, y, r in the 2048 px livery from the top left), with no line detail kept from it.
SKULL = [(1800, 175, 95), (1800, 585, 95)]
BARAK_FIN = [
    ("34424", [(-5.2, 3.4), (-5.53, 2.83), (-5.9, 2.78), (-6.1, 2.68), (-6.3, 2.62), (-6.6, 2.55), (-6.9, 2.45),
               (-7.2, 2.4), (-7.2, 3.4)]),
    ("33531", [(-4.98, 0.6), (-5.0, 0.95), (-5.1, 1.08), (-5.3, 1.16), (-5.55, 1.19), (-5.8, 1.15), (-6.0, 1.06),
               (-6.15, 0.95), (-6.3, 0.6)]),
]


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
    fin(albedo, skin)
    return albedo


def fin(albedo, skin):
    """The fin and rudder repainted (BARAK_FIN over BARAK_FIN_BASE), over the livery's panel lines: the livery's 101
    Squadron art and number go (base.old_fin_marks; their texels outside the fin's faces filled in from round
    them)."""
    bpy.context.view_layer.update()  # the rudder where the rig put it
    _, tris, uvs = skin_bvh(skin)
    k = [i for i, t in enumerate(tris) if is_fin(t)]
    fpos, _ = texels(albedo, [tris[i] for i in k], [uvs[i] for i in k])
    on_fin = ~np.isnan(fpos[..., 0])
    yz = fpos[on_fin][:, 1:]
    lum = albedo[..., :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    hole = old_fin_marks(lum.shape)
    h, w = lum.shape
    yy, xx = np.mgrid[h - 1:-1:-1, 0:w]
    for cx, cy, r in SKULL:
        hole |= np.hypot(xx - cx, yy - cy) <= r
    detail = np.where(hole, 1.0, np.clip(lum / np.maximum(window(window(lum, 5, np.maximum), 5, np.minimum), 1e-3),
                                         0.55, 1.0))[on_fin]
    col = np.tile(np.array(BARAK[BARAK_FIN_BASE], dtype=np.float32), (len(yz), 1))
    for c, poly in BARAK_FIN:
        col[inside(yz, poly)] = BARAK[c]
    albedo[on_fin, :3] = col * detail[:, None]
    done = ~hole | on_fin
    while not done.all():
        p = np.pad(np.where(done[..., None], albedo[..., :3], 0), ((1, 1), (1, 1), (0, 0)))
        c = np.pad(done.astype(np.float32), 1)
        n = c[:-2, 1:-1] + c[2:, 1:-1] + c[1:-1, :-2] + c[1:-1, 2:]
        s = p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
        grow = ~done & (n > 0)
        albedo[grow, :3] = s[grow] / n[grow][:, None]
        done |= grow
    print("barak: the fin repainted, texels", int(on_fin.sum()), "old markings filled", int((hole & ~on_fin).sum()))
