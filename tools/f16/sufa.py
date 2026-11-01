# The F-16I Sufa layer over the F-16 base (base.py; f16i.glb, docs/f16i.md §8): FlightGear's conformal fuel tanks
# and P&W F100 nozzle, the F-16I's spine vents, our nose and tail fairings (nose_fairings), and the paint and markings
# of F-16I 846 of 201 Squadron: its camouflage, colours, fin art and number (livery).
import math
import os

import bmesh
import bpy
import kit
import numpy as np
from mathutils import Matrix, Vector

import base
from base import (CAMO, FG_PAINT, FG_RADOME, FIN_DROP, FS, RADOME, bounds, camo_weights, fg, recolour,
                  rotate_about, skin_bvh, spine_top, texels, transform, window)

# The F-16I's spine (photos of 890 and 827, SOURCES.md) has the F-16D's outline but two taller grilled vents 0.4 to
# 0.55 m ahead of the fin's root (base.SP_Y_FIN), and on each side of the tail box under the fin a round blister and
# an oblong fairing (SUFA_TAIL_FAIRINGS: y, below the top, size across / along / up, in m).
SPINE_VENTS = ([(-3.30, 0.12), (-3.46, 0.12)], 0.25, 0.20)
SUFA_TAIL_FAIRINGS = [(-4.48, 0.19, (0.06, 0.20, 0.22)), (-4.18, 0.33, (0.05, 0.24, 0.15))]


def nozzle():
    return pw_nozzle()


def fg_parts(body):
    # loads_models-inner.xml's CFTTanks, at FlightGear's origin; stretched for two seats with the skin under it.
    body["CFT"] = kit.join(list(kit.import_ac(os.path.join(base.M, "Armament/External-stores/Fueltanks/CFT.ac"),
                                              prefix="cft_").values()), "CFT")


def own_parts(body):
    body["SufaAntennas"] = nose_fairings(body)


# The P&W nozzle's plates at rest (nozzle-section.xml's rotations at property 0, by the right-hand rule here): the
# petals converge to the exit.
PW_REST_DEG = 5.0


def pw_nozzle():
    """F-16.xml's PW_nozzle (nozzle.xml): 16 nozzle-section.ac sections, 22.5° apart round the engine axis, 4.617 m
    aft, each section's plates at their rest angle. nozzle.xml's far-distance cone (nozzle.ac) is left out."""
    rest = {"us1": ((0, 0, 0.49), (0, -1, 0)), "ls1": ((0, 0, 0.45), (0, -1, 0)),
            "ls2": ((0, -0.115, 0.435), (0, -0.948683, -0.316228))}
    out = {}
    for k in range(16):
        sec = kit.import_ac(os.path.join(base.M, "nozzle-section.ac"), prefix="noz%d_" % k)
        for name, (c, ax) in rest.items():
            rotate_about([sec[name]], fg(c), fg(ax), math.radians(PW_REST_DEG))
        transform(sec.values(), Matrix.Translation(fg((4.617, 0, 0))) @
                  Matrix.Rotation(math.radians(22.5 * k), 4, fg((1, 0, 0))))
        out.update({"noz%d_%s" % (k, n): o for n, o in sec.items()})
    return out


# The Sufa's nose fairings (docs/f16i.md §8 "Antennas"; photos in SOURCES.md): a row of AIFF interrogator antennas
# ("bird slicers") across the nose ahead of the windscreen, in an arc that follows the windscreen's foot, and a sensor
# blister low on each side of the nose with a dark window facing forward. Sizes (across, along, height in m) and
# places from the photos (inferred).
AIFF_X = (-0.24, -0.12, 0.0, 0.12, 0.24)  # across the nose
AIFF_AHEAD, AIFF_ARC, AIFF_SIZE = 0.26, 0.9, (0.034, 0.085, 0.03)  # ahead of the windscreen's foot; aft = ARC * x²
BLISTER_AHEAD, BLISTER_DROP, BLISTER_SIZE = 0.05, 0.36, (0.07, 0.17, 0.085)  # below the nose's top; out, along, up


def nose_fairings(body):
    """The fairings as one mesh in the airframe's paint: each takes the livery of the skin it sits on."""
    from mathutils.geometry import barycentric_transform
    skin = [o for o in body.values() if any(m and m.name.startswith("ac_f16.png") for m in o.data.materials)]
    paint = next(m for o in skin for m in o.data.materials if m and m.name.startswith("ac_f16.png")
                 and m.use_backface_culling)
    window = kit.material("sensor_window", (0.04, 0.05, 0.06), roughness=0.08)
    bvh, tris, uvs = skin_bvh(skin)
    y0 = bounds([body["CanopyForwardOutside"]])[1].y  # the windscreen's foot (the nose is +y)

    def cast(origin, direction):
        loc, n, i, _ = bvh.ray_cast(Vector(origin), Vector(direction))
        assert loc is not None, origin
        return loc, n, barycentric_transform(loc, *tris[i], *uvs[i]).to_2d()

    objs = []

    def dome(name, loc, n, uv, size, front_window=False):
        """A half-buried ellipsoid on the skin: `size` across, along (fore-aft) and out of the skin."""
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(name, me)
        kit.scene().collection.objects.link(o)
        me.materials.append(paint)
        me.materials.append(window)
        uvl = me.uv_layers.new(name="UVMap").data
        for p in me.polygons:  # local frame: x across, y along, z out
            front = front_window and p.normal.y > 0.55 and p.center.z > 0.15
            p.material_index = 1 if front else 0
            p.use_smooth = True
            for j in p.loop_indices:
                c = me.vertices[me.loops[j].vertex_index].co
                uvl[j].uv = (uv.x + c.x * 0.002, uv.y + c.y * 0.002)
        n = n.normalized()
        f = (Vector((0, 1, 0)) - n * n.y).normalized()
        s = f.cross(n)
        m = Matrix.Identity(4)
        for k, (ax, size_k) in enumerate(zip((s, f, n), size)):
            m.col[k] = (*(ax * size_k), 0)
        m.col[3] = (*loc, 1)
        me.transform(m)
        objs.append(o)

    for i, x in enumerate(AIFF_X):
        loc, n, uv = cast((x, y0 + AIFF_AHEAD - AIFF_ARC * x * x, 5.0), (0, 0, -1))
        dome("aiff%d" % i, loc, n, uv, AIFF_SIZE)
    yb = y0 + BLISTER_AHEAD
    top = cast((0, yb, 5.0), (0, 0, -1))[0].z
    for side in (-1, 1):
        loc, n, uv = cast((side * 3.0, yb, top - BLISTER_DROP), (-side, 0, 0))
        dome("blister%d" % side, loc, n, uv, BLISTER_SIZE, front_window=True)
    for k, (y, below, size) in enumerate(SUFA_TAIL_FAIRINGS):  # on the tail box's sides, under the fin
        for side in (-1, 1):
            loc, n, uv = cast((side * 3.0, y, spine_top(y) - below), (-side, 0, 0))
            dome("tail%d%d" % (k, side), loc, n, uv, size)
    print("nose fairings: windscreen foot y %.2f, nose top z %.2f, blisters at %s" % (y0, top, tuple(
        round(c, 2) for c in loc)))
    return kit.join(objs, "SufaAntennas")


# The Sufa's paint as F-16I 846 wears it (docs/f16i.md §8.1), measured in its photographs (SOURCES.md): lighter and
# warmer than the chips, the green a pale sage. Albedo, set against our renders beside the photos.
SUFA_PAINT = {"30219": (0.76, 0.56, 0.37), "33531": (0.88, 0.79, 0.64), "34424": (0.74, 0.78, 0.61),
              "36375": FS["36375"], "36270": FS["36270"]}
# Added to the paint's roughness: 846's paint is flat (the base gloss let the sky tint its tan violet in the game).
MATTE = 0.25
# The CFTs' own UV island in the livery (u0, v0, u1, v1; unpainted in FlightGear's livery): painted with the pattern.
CFT_UV = (0.19, 0.205, 0.535, 0.40)
# On the fin, 101 Squadron's markings to paint over (places in the 2048 px livery, pixels from the top left): its
# badge and the red disc above it (circles x, y, r) and the red and white stripes (boxes), on each side; and the tail
# number "547" (boxes).
BADGES = [(1800, 190, 70), (1820, 115, 26), (1800, 570, 70), (1820, 655, 26)]
STRIPES = [(1850, 30, 1960, 190), (1850, 585, 1960, 745)]
DIGITS = [(1640, 245, 1757, 312), (1640, 468, 1759, 537)]
# F-16I 846 of 201 Squadron ("The One", Ramon), as its photographs of January 2025 show its right side (SOURCES.md;
# docs/f16i.md §8.1). Traced by hand onto our model's side view (y forward, z up, m), the photos fitted to it by the
# radome's tip and the fin's leading edge (inferred, about 0.1 m). The left side is the mirror image (no photo).
# Its camouflage on the fuselage, the CFTs, the spine and the tail box, seen from the side: sand, with these tan and
# green blotches; each point within SUFA_BODY_X of the centre line takes the colour of the blotch it lies in, seen
# from the side (on the top the side's bands run across). The wings and stabilators: our pattern (camo_weights).
SUFA_BODY_X = 1.0
SUFA_BLOTCHES = [
    ("30219", [(-7.4, 1.4), (-5.2, 1.4), (-5.05, 0.55), (-4.6, 0.38), (-5.0, 0.3), (-4.0, 0.25), (-3.55, 0.18),
               (-3.5, -0.5), (-7.4, -0.5)]),  # the tail box's end and the fuselage round the nozzle
    ("34424", [(-3.6, 0.12), (-3.0, 0.35), (-2.6, 0.52), (-2.6, 1.4), (-2.1, 1.4), (-2.1, 0.6), (-1.15, 0.62),
               (-1.15, -0.5), (-3.5, -0.5)]),  # along the CFTs' rear, a band over the spine
    ("30219", [(-2.1, 1.4), (-1.0, 1.4), (-1.0, 0.75), (-0.62, 0.7), (-0.55, 0.1), (-0.6, -0.5), (-1.15, -0.5),
               (-1.15, 0.62), (-2.1, 0.6)]),
    ("30219", [(0.28, -0.5), (0.8, -0.5), (0.78, 0.72), (1.15, 0.75), (1.2, 1.4), (-0.35, 1.4), (-0.35, 0.75),
               (0.28, 0.72)]),  # across the CFTs and the spine behind the canopy
    ("34424", [(1.0, -0.5), (1.0, 0.62), (2.3, 0.6), (2.55, 0.35), (2.3, 0.1), (1.6, -0.5)]),  # the CFTs' noses
    ("30219", [(2.6, 0.7), (3.95, 0.7), (4.1, 0.1), (3.9, -0.5), (3.1, -0.5), (3.05, 0.05), (2.7, 0.35)]),  # cockpit
    ("30219", [(4.75, -0.5), (4.75, 0.7), (5.05, 0.7), (5.05, -0.5)]),  # behind the radome
]
# Its fin (y, z on the fin, m): tan, with the squadron's art (our drawing of it: a sand band down the fin, a blue and
# an orange swoosh, a short blue stroke, a dark swift and the round badge) and the number 846. A dark line runs
# 0.4 m inside the leading edge (a panel edge; inferred).
SUFA_FIN_BASE = "30219"
SUFA_FIN_LINE = ([(-6.11, 3.19), (-4.28, 0.86)], 0.026, (0.30, 0.27, 0.25))  # ends, width, colour
SUFA_FIN_BAND = [(-6.33, 2.69), (-6.29, 2.76), (-6.11, 2.89), (-6.08, 3.16), (-5.92, 3.2), (-5.76, 2.69),
                 (-5.71, 2.42), (-5.62, 2.03), (-5.58, 1.78), (-5.61, 1.39), (-5.6, 1.11), (-5.58, 0.83),
                 (-5.53, 0.6), (-6.04, 0.6), (-5.92, 0.83), (-5.94, 1.39), (-6.03, 1.78), (-6.11, 2.08), (-6.15, 2.33),
                 (-6.1, 2.39), (-6.28, 2.42), (-6.33, 2.5)]
BLUE, ORANGE, INK = (0.16, 0.42, 0.62), (0.90, 0.58, 0.22), (0.07, 0.07, 0.08)
# Swooshes: centre lines (y, z) and their widths (m) at each point.
SUFA_SWOOSHES = [
    (BLUE, [(-6.39, 2.42), (-6.19, 2.31), (-6.03, 2.19), (-5.86, 2.06), (-5.72, 1.89), (-5.58, 1.69), (-5.47, 1.5),
            (-5.43, 1.33), (-5.46, 1.22), (-5.53, 1.17), (-5.6, 1.18)],
     [0.022, 0.05, 0.072, 0.083, 0.092, 0.1, 0.106, 0.106, 0.094, 0.078, 0.05]),
    (ORANGE, [(-6.12, 2.35), (-5.94, 2.22), (-5.75, 2.08), (-5.58, 1.94), (-5.44, 1.78), (-5.33, 1.61), (-5.29, 1.44),
              (-5.32, 1.33), (-5.39, 1.26)], [0.022, 0.061, 0.078, 0.083, 0.083, 0.078, 0.067, 0.05, 0.022]),
    (BLUE, [(-6.25, 1.69), (-6.01, 1.42)], [0.028, 0.044]),
]
SUFA_SWIFT = [(-6.52, 2.64), (-6.24, 2.66), (-6.31, 2.61), (-6.35, 2.5), (-6.39, 2.6)]
SUFA_BADGE = ((-5.97, 2.61), 0.14)  # centre, radius: white rim, an orange sun over dark rings, a dark bird across
# The number: text, the middle of its foot (y, z), digit height, width, pitch and stroke (m).
SUFA_NUMBER = ("846", (-5.03, 0.89), 0.37, 0.19, 0.24, 0.05)
# The number again on each intake's side, dark blue, at (y, z) of its foot (on the sideways faces).
SUFA_INTAKE_NUMBER = ((1.05, -0.8), 0.2, 0.11, 0.135, 0.028)
INTAKE_BLUE = (0.17, 0.30, 0.55)


def is_fin(t):
    """A triangle of the fin or rudder: facing sideways, on the centre line, above the spine aft of the blade
    antenna."""
    n, c = (t[1] - t[0]).cross(t[2] - t[0]), (t[0] + t[1] + t[2]) / 3
    return n.length > 1e-12 and abs(n.x) > 0.8 * n.length and c.z > 1.2 - FIN_DROP and abs(c.x) < 0.1 and c.y < -3.7


def livery(albedo, skin):
    """FlightGear's IAF livery made F-16I 846's: the underside's grey and the radome recoloured to the FS colours;
    the upper surfaces (the CFTs too) repainted over the livery's panel lines, the fuselage with 846's blotches
    (SUFA_BLOTCHES), the wings with our pattern; on the fin, 101 Squadron's markings painted over, 846's tan, its
    squadron's art and its number."""
    h, w = albedo.shape[:2]
    src = albedo.copy()
    bpy.context.view_layer.update()  # the moving parts (rudder, flaperons, ...) where the rig put them
    _, tris, uvs = skin_bvh(skin)
    pos, nz = texels(albedo, tris, uvs)
    # The fin's texels are the fin's (other faces share some of them).
    fin = [i for i, t in enumerate(tris) if is_fin(t)]
    fpos, _ = texels(albedo, [tris[i] for i in fin], [uvs[i] for i in fin])
    on_fin = ~np.isnan(fpos[..., 0])
    pos[on_fin], nz[on_fin] = fpos[on_fin], 0.0
    recolour(albedo, [(c, SUFA_PAINT[f]) for c, f in FG_PAINT], 0.16, nz > -0.35)
    recolour(albedo, [(c, SUFA_PAINT[f]) for c, f in FG_PAINT[3:]], 0.16, nz <= -0.35)  # underneath: grey only
    yy, xx = np.mgrid[h - 1:-1:-1, 0:w]  # pixel coordinates from the top left, in Blender's row order
    for x0, y0, x1, y1 in RADOME:
        recolour(albedo, [(FG_RADOME, FS["36270"])], 0.12, (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1))
    lum = src[..., :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    # Where our camouflage goes: the livery's camouflage colours, the CFTs' island and the fin's old markings; on
    # faces looking up or sideways. Each texel keeps the livery's panel lines and rivets (its dark thin lines: the
    # ratio of its brightness to the local brightest, as panel_maps finds them).
    covered = ~np.isnan(pos[..., 0])
    d = np.stack([np.linalg.norm(src[..., :3] - np.array(c, dtype=np.float32), axis=2) for c, _ in FG_PAINT])
    camo_src = (d.argmin(axis=0) < 3) & (d.min(axis=0) < 0.16)
    u0, v0, u1, v1 = CFT_UV
    cft = (xx >= u0 * w) & (xx < u1 * w) & (h - 1 - yy >= v0 * h) & (h - 1 - yy < v1 * h)
    hole = np.zeros((h, w), dtype=bool)
    for cx, cy, r in BADGES:
        hole |= np.hypot(xx - cx, yy - cy) <= r
    for x0, y0, x1, y1 in STRIPES + DIGITS:
        hole |= (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
    want = camo_src | cft | hole
    paint = covered & want & (nz > -0.35)
    albedo[covered & cft & (nz <= -0.35), :3] = FS["36375"]
    closed = window(window(lum, 5, np.maximum), 5, np.minimum)
    detail = np.where(cft | hole, 1.0, np.clip(lum / np.maximum(closed, 1e-3), 0.55, 1.0))
    p = pos[paint]
    wts = camo_weights(p)
    body = np.abs(p[:, 0]) < SUFA_BODY_X
    wts[body] = side_weights(p[body][:, 1:])
    wts[on_fin[paint]] = np.eye(3, dtype=np.float32)[CAMO.index(SUFA_FIN_BASE)]
    albedo[paint, :3] = (wts @ np.array([SUFA_PAINT[c] for c in CAMO], dtype=np.float32)) * detail[paint][:, None]
    # The gutters round each UV island (no face of their own, read by mipmaps): the painted colour carried out.
    done = paint.copy()
    for it in range(80):  # the fin's old markings where no face of theirs is: filled in from round them
        p = np.pad(np.where(done[..., None], albedo[..., :3], 0), ((1, 1), (1, 1), (0, 0)))
        c = np.pad(done.astype(np.float32), 1)
        n = c[:-2, 1:-1] + c[2:, 1:-1] + c[1:-1, :-2] + c[1:-1, 2:]
        s = p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]
        grow = (~covered if it < 6 else hole) & want & ~done & (n > 0)
        albedo[grow, :3] = s[grow] / n[grow][:, None]
        done |= grow
    share = wts.sum(axis=0) / len(wts)
    # The fin's art, seen from either side in the fin's plane (y, z); the number reads front to back on the left side.
    fyz = fpos[on_fin][:, 1:]
    col = np.array(SUFA_PAINT[SUFA_FIN_BASE], dtype=np.float32) * detail[on_fin][:, None]
    sand = np.array(SUFA_PAINT["33531"])
    for k, (mask, colour) in enumerate(fin_art(fyz, np.sign(fpos[on_fin][:, 0]))):
        col[mask] = colour if k else col[mask] / np.array(SUFA_PAINT[SUFA_FIN_BASE]) * sand  # the band keeps the lines
    albedo[on_fin, :3] = col
    (ny, nz0), *size = SUFA_INTAKE_NUMBER
    side = covered & (np.abs(nz) < 0.5) & (np.abs(np.nan_to_num(pos[..., 0])) > 0.2) & ~on_fin
    q = pos[side]
    ink = text_ink(np.column_stack([(q[:, 1] - ny) * np.sign(q[:, 0]), q[:, 2] - nz0]), SUFA_NUMBER[0], *size)
    rows, cols = np.nonzero(side)
    albedo[rows[ink], cols[ink], :3] = INTAKE_BLUE
    print("Sufa livery: camouflage texels", int(paint.sum()), "shares", [round(float(x), 2) for x in share],
          "on the body", int(body.sum()), "fin texels", int(on_fin.sum()))
    return albedo


def inside(pts, poly):
    """Even-odd test of the points [n, 2] against the polygon [(y, z), ...]."""
    poly = np.array(poly, dtype=np.float32)
    out = np.zeros(len(pts), dtype=bool)
    for (y0, z0), (y1, z1) in zip(poly, np.roll(poly, -1, axis=0)):
        cross = (z0 > pts[:, 1]) != (z1 > pts[:, 1])
        with np.errstate(divide="ignore", invalid="ignore"):
            at = y0 + (pts[:, 1] - z0) * (y1 - y0) / (z1 - z0)
        out ^= cross & (pts[:, 0] < at)
    return out


def near_line(pts, line, widths):
    """The points [n, 2] within half the local width of the polyline (widths per point, m)."""
    line, widths = np.array(line, dtype=np.float32), np.array(widths, dtype=np.float32)
    out = np.zeros(len(pts), dtype=bool)
    for a, b, wa, wb in zip(line[:-1], line[1:], widths[:-1], widths[1:]):
        d = b - a
        t = np.clip(((pts - a) @ d) / max(float(d @ d), 1e-9), 0, 1)
        out |= np.linalg.norm(pts - (a + t[:, None] * d), axis=1) < (wa + (wb - wa) * t) / 2
    return out


def side_weights(yz):
    """SUFA_BLOTCHES at the points (y, z) [n, 2]: the weight of each colour of CAMO, sand where no blotch is; soft
    over about 2 cm (four samples)."""
    w = np.zeros((len(yz), 3), dtype=np.float32)
    for dy, dz in ((-0.01, -0.01), (0.01, -0.01), (-0.01, 0.01), (0.01, 0.01)):
        q = yz + np.array([dy, dz], dtype=np.float32)
        k = np.full(len(q), CAMO.index("33531"))
        for c, poly in SUFA_BLOTCHES:
            k[inside(q, poly)] = CAMO.index(c)
        w[np.arange(len(q)), k] += 0.25
    return w


def ellipse(cx, cy, rx, ry, a0=0.0, a1=360.0, n=40):
    t = np.radians(np.linspace(a0, a1, n))
    return list(zip(cx + rx * np.cos(t), cy + ry * np.sin(t)))


# Our digits for the tail number, as 846's (a plain rounded sans): centre lines in a unit box (0..1 across, 0..1 up).
GLYPHS = {
    "8": [ellipse(0.5, 0.77, 0.42, 0.23), ellipse(0.5, 0.27, 0.5, 0.27)],
    "4": [[(0.74, 0.0), (0.74, 1.0), (0.0, 0.3), (1.0, 0.3)]],
    "6": [ellipse(0.5, 0.3, 0.5, 0.3), [(0.0, 0.3), (0.03, 0.58), (0.14, 0.8), (0.35, 0.96), (0.62, 1.0), (0.9, 0.93)]],
}


def text_ink(uv, text, height, width, pitch, stroke):
    """The points uv [n, 2] (m, across and up from the middle of the text's foot) on the text's strokes."""
    out = np.zeros(len(uv), dtype=bool)
    for k, ch in enumerate(text):
        x0 = (k - (len(text) - 1) / 2) * pitch - width / 2 + stroke / 2
        for line in GLYPHS[ch]:
            pts = [(x0 + u * (width - stroke), stroke / 2 + v * (height - stroke)) for u, v in line]
            out |= near_line(uv, pts, [stroke] * len(pts))
    return out


def fin_art(yz, side):
    """The fin's art at the points (y, z) [n, 2] of either side (side: the sign of x): (mask, colour) in paint
    order; the first is the sand band."""
    (by, bz), br = SUFA_BADGE
    r = np.hypot(yz[:, 0] - by, yz[:, 1] - bz)
    text, (ny, nz), *size = SUFA_NUMBER
    uv = np.column_stack([(yz[:, 0] - ny) * side, yz[:, 1] - nz])  # across as the viewer reads it
    art = [(inside(yz, SUFA_FIN_BAND), None),
           (near_line(yz, SUFA_FIN_LINE[0], [SUFA_FIN_LINE[1]] * 2), SUFA_FIN_LINE[2])]
    art += [(near_line(yz, line, widths), colour) for colour, line, widths in SUFA_SWOOSHES]
    art += [(inside(yz, SUFA_SWIFT), INK), (r < br, (0.92, 0.91, 0.88))]
    for k in range(5):  # the badge's rings, below the sun
        art.append((r < br * (0.8 - 0.16 * k), INK if k % 2 == 0 else (0.92, 0.91, 0.88)))
    art.append(((r < br * 0.8) & (yz[:, 1] > bz + 0.1 * br), ORANGE))
    art.append((near_line(yz, [(by - 0.8 * br, bz + 0.5 * br), (by + 0.1 * br, bz + 0.2 * br),
                               (by + 0.75 * br, bz + 0.35 * br)], [0.025] * 3), INK))
    art.append((text_ink(uv, text, *size), INK))
    return art

