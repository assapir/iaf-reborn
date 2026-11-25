# The Eitam (the IAF's Gulfstream G550 CAEW) as our own low-poly model (docs/ai.md §24.3): lofted sections in plain
# colours, true size where Wikipedia gives it (length 29.39 m, span 28.50 m), the rest read off public photographs of
# the CAEW (inferred): the G550's swept wing with winglets, its T-tail and two rear-mounted engines, and the CAEW's
# longer nose radome, the tail radome behind the fin and the long side fairings (the L-band arrays) under the cabin
# windows. Light grey as the IAF's Eitam; no markings. Nose along -Z (glTF), the origin at the middle of its length on
# the fuselage's axis; it is drawn in the air only (no gear). Run once by hand, then committed:
#
#   blender -b --factory-startup -P tools/eitam/eitam.py -- shared/extra/models
import math
import os
import sys

import bpy
import bmesh

LENGTH = 29.39
SPAN = 28.50
# sRGB, roughness.
PAINT = {
    "grey": ((0.72, 0.74, 0.76), 0.55),
    "radome": ((0.60, 0.62, 0.65), 0.6),
    "dark": ((0.07, 0.08, 0.09), 0.4),
    "metal": ((0.45, 0.46, 0.47), 0.35),
}


def lin(c):
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def material(name):
    m = bpy.data.materials.new(name)
    rgb, rough = PAINT[name]
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*lin(rgb), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


class Part:
    """One mesh in Blender's frame (x right, y forward, z up), metres."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def _mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def loft(self, rings, mat, cap=True):
        """Rings of the same number of points joined in order; the ends closed (a point ring needs no cap)."""
        vs = [[self.bm.verts.new(p) for p in r] for r in rings]
        k = self._mat(mat)
        n = len(rings[0])
        for a, b in zip(vs, vs[1:]):
            for i in range(n):
                f = self.bm.faces.new([a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]])
                f.material_index = k
        if cap:
            for r in (vs[0], vs[-1]):
                if len({tuple(v.co) for v in r}) > 2:
                    self.bm.faces.new(r).material_index = k

    def obj(self, name):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-4)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(material(m))
        for p in me.polygons:
            p.use_smooth = True
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        return o


N = 16


def ellipse(y, rx, rz, cx=0.0, cz=0.0, n=N):
    return [(cx + rx * math.cos(2 * math.pi * i / n), y, cz + rz * math.sin(2 * math.pi * i / n)) for i in range(n)]


def foil(x, y_le, chord, thick, z, n=8):
    """A wing section at span station x: a lens from its leading edge (y_le, the front) back over `chord`."""
    pts = []
    for i in range(n):
        t = i / (n - 1)
        pts.append((x, y_le - t * chord, z + thick * 0.5 * math.sin(math.pi * t)))
    for i in range(n - 2, 0, -1):
        t = i / (n - 1)
        pts.append((x, y_le - t * chord, z - thick * 0.3 * math.sin(math.pi * t)))
    return pts


def fin(z, y_le, chord, thick, x=0.0, n=8):
    """A vertical section at height z (the fin's), from its leading edge back."""
    pts = []
    for i in range(n):
        t = i / (n - 1)
        pts.append((x + thick * 0.5 * math.sin(math.pi * t), y_le - t * chord, z))
    for i in range(n - 2, 0, -1):
        t = i / (n - 1)
        pts.append((x - thick * 0.5 * math.sin(math.pi * t), y_le - t * chord, z))
    return pts


def build():
    half = LENGTH / 2
    body = Part()
    # The fuselage from the nose radome's tip back to the tail radome's: (y, half width, half height, centre z).
    stations = [
        (half, 0.0, 0.0, -0.15),
        (half - 0.5, 0.55, 0.5, -0.12),
        (half - 1.4, 0.95, 0.9, -0.05),
        (half - 2.6, 1.2, 1.15, 0.0),
        (half - 4.5, 1.25, 1.25, 0.05),
        (-half + 6.5, 1.25, 1.25, 0.05),
        (-half + 4.0, 0.95, 1.0, 0.25),
        (-half + 2.0, 0.6, 0.65, 0.4),
        (-half + 0.6, 0.35, 0.35, 0.45),
        (-half, 0.0, 0.0, 0.45),
    ]
    rings = [ellipse(y, rx, rz, cz=cz) if rx > 0 else [(0, y, cz)] * N for y, rx, rz, cz in stations]
    body.loft(rings[:3], "radome", cap=False)  # the nose radome
    body.loft(rings[2:8], "grey", cap=False)
    body.loft(rings[7:], "radome", cap=False)  # the tail radome
    # The cockpit windows: a dark band over the nose.
    win = [ellipse(half - 2.0 - d, 1.08 + 0.1 * d, 1.08 + 0.1 * d, cz=0.0)[1:8] for d in (0.0, 0.9)]
    body.loft([[(x * 1.01, y, z * 1.01 + 0.02) for x, y, z in r] for r in win], "dark", cap=False)
    # The side fairings (the arrays): long flat bulges low on each side, from behind the cockpit to the wing root.
    for s in (-1, 1):
        rings = []
        for y, w in [(half - 4.0, 0.0), (half - 5.0, 0.32), (1.0, 0.32), (-0.5, 0.0)]:
            rings.append([(s * (1.2 + w * math.cos(a)), y, -0.2 + 0.9 * math.sin(a)) for a in
                          (-math.pi / 2, -math.pi / 4, 0.0, math.pi / 4, math.pi / 2)])
        body.loft(rings, "radome")
    # The wing: low, swept 27° (inferred), its root at the fuselage's side, the winglets canted out.
    sweep = math.tan(math.radians(27))
    root_le, root_c, tip_c = 1.2, 5.6, 1.5
    for s in (-1, 1):
        tip_x = SPAN / 2 - 0.3
        secs = [foil(s * 1.0, root_le, root_c, 0.7, -0.75), foil(s * tip_x, root_le - sweep * (tip_x - 1.0), tip_c, 0.18,
                                                               -0.75 + 0.06 * tip_x)]
        body.loft(secs, "grey")
        # The winglet.
        tz = -0.75 + 0.06 * tip_x
        wl = [fin(tz, root_le - sweep * (tip_x - 1.0), tip_c, 0.16, x=s * tip_x),
              fin(tz + 2.1, root_le - sweep * (tip_x - 1.0) - 1.1, 0.7, 0.08, x=s * (tip_x + 0.3))]
        body.loft(wl, "grey")
        # The engine on the rear fuselage: a nacelle and its pylon.
        cx, cz = s * 2.25, 0.75
        nac = [ellipse(y, r, r, cx=cx, cz=cz) for y, r in [(-6.0, 0.62), (-6.6, 0.72), (-9.5, 0.68), (-11.0, 0.45)]]
        body.loft(nac, "grey")
        body.loft([ellipse(-6.02, 0.5, 0.5, cx=cx, cz=cz), ellipse(-6.3, 0.5, 0.5, cx=cx, cz=cz)], "dark")
        body.loft([fin(cz, -7.5, 2.5, 0.25, x=s * 1.4), fin(cz, -7.5, 2.5, 0.25, x=s * 1.75)], "grey")
    # The T-tail: the fin from the rear fuselage up, swept, the stabiliser on top.
    fin_root, fin_top = 0.9, 5.4
    body.loft([fin(fin_root, -9.2, 4.6, 0.45), fin(fin_top, -11.6, 2.6, 0.22)], "grey")
    for s in (-1, 1):
        body.loft([foil(s * 0.1, -11.4, 2.9, 0.25, fin_top), foil(s * 5.0, -13.2, 1.3, 0.12, fin_top + 0.3)], "grey")
    return body.obj("eitam")


def export(out_root):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    o = build()
    out = os.path.join(out_root, "eitam")
    os.makedirs(out, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out, "eitam.glb"),
        export_format="GLB",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print("MODEL eitam tris", tris, "span %.2f length %.2f" % (max(xs) - min(xs), max(ys) - min(ys)))


export(sys.argv[sys.argv.index("--") + 1])
