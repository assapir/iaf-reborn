# The S-300PMU-2's radars as our own low-poly models (docs/ai.md §15.4): the 64N6E2 of the 83M6E2 network on its
# MAZ-7910 tractor and semi-trailer, the 96L6E on its MZKT-7930 and the 30N6E2 on its MAZ-7910. Boxes and prisms in
# plain colours, true size where a source gives it, else read off the reference photographs (inferred; the figures and
# photos in docs/ai.md).
# Nose along -Z (glTF), on the ground at the middle of its footprint. Each antenna (the array, its IFF strip, the
# pedestal above the turntable) is the node `antenna`, its origin on the turning axis: air_defence.gd turns it about
# up (a search radar's while it radiates, the track radar's onto its track). Run once by hand, then committed:
#
#   blender -b --factory-startup -P tools/enemy_models/radars.py -- shared/extra/models
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

# The paint (sRGB): the olive of the other enemy models (the S-300 launcher's and the 30N6E's textures), the 64N6E2's
# array faces a darker olive grey; roughness.
PAINT = {
    "olive": ((0.36, 0.38, 0.26), 0.8),
    "array": ((0.30, 0.32, 0.24), 0.7),
    "dark": ((0.12, 0.12, 0.11), 0.9),
    "tyre": ((0.06, 0.06, 0.055), 0.95),
    "glass": ((0.10, 0.13, 0.15), 0.2),
    "steel": ((0.30, 0.31, 0.30), 0.5),
    "lamp": ((0.80, 0.80, 0.72), 0.3),
}

# How deep the tyres stand in the ground (m, inferred).
SINK = 0.08


def lin(c):
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        rgb, rough = PAINT[name]
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*lin(rgb), 1.0)
        bsdf.inputs["Roughness"].default_value = rough
    return m


class Part:
    """One node's mesh: boxes, prisms and wheels in Blender's frame (x right, y forward, z up), metres."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def _mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def _faces(self, verts, faces, mat):
        vs = [self.bm.verts.new(v) for v in verts]
        for f in faces:
            self.bm.faces.new([vs[i] for i in f]).material_index = self._mat(mat)

    def box(self, centre, size, mat, tilt=0.0):
        """A box; `tilt` leans it back about x (degrees, the top towards -y) around its centre."""
        c, h = Vector(centre), Vector(size) / 2
        r = Matrix.Rotation(math.radians(tilt), 3, "X")
        verts = [c + r @ Vector((sx * h.x, sy * h.y, sz * h.z)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        self._faces(verts, faces, mat)

    def prism(self, profile, a0, a1, mat, axis="y", tilt=0.0, pivot=(0, 0, 0)):
        """The profile extruded from a0 to a1 along `axis`: [(x, z)] along y, [(y, z)] along x; leaned back by
        `tilt` (degrees about x, the top towards -y) around `pivot`."""
        r = Matrix.Rotation(math.radians(tilt), 3, "X")
        p = Vector(pivot)
        n = len(profile)
        if axis == "y":
            pts = [Vector((u, a, v)) for a in (a0, a1) for u, v in profile]
        else:
            pts = [Vector((a, u, v)) for a in (a0, a1) for u, v in profile]
        verts = [p + r @ (q - p) for q in pts]
        faces = [tuple(range(n)), tuple(range(n, 2 * n))]
        faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
        self._faces(verts, faces, mat)

    def wheel(self, x, y, r, w, sides=16):
        """A wheel at (x, y) on the ground, its axle along x: the tyre (a flat side down, on the ground) and the hub on
        its outer side."""
        k = r / math.cos(math.pi / sides)  # the corners' radius that puts the flat sides at r
        angles = [math.pi * (2 * i + 1) / sides for i in range(sides)]
        ring = [(k * math.cos(a), k * math.sin(a)) for a in angles]
        self.prism([(y + u, r + v) for u, v in ring], x - w / 2, x + w / 2, "tyre", axis="x")
        out = x + math.copysign(w / 2, x)
        hub = [(y + 0.45 * u, r + 0.45 * v) for u, v in ring]
        self.prism(hub, out - 0.02, out + math.copysign(0.03, x), "steel", axis="x")

    def axles(self, ys, track, r, w):
        for y in ys:
            for x in (-track / 2, track / 2):
                self.wheel(x, y, r, w)

    def obj(self, name, parent=None, at=(0, 0, 0)):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(material(m))
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        if parent is not None:
            o.parent = parent
        o.location = at
        return o


def cab(p, x, y0, y1, w, z0, z1, rake=0.35):
    """A cab from y0 (rear) to y1 (front), its windscreen raked back by `rake` m at the top, with the glass."""
    prof = [(y0, z0), (y1, z0), (y1, z0 + 0.55 * (z1 - z0)), (y1 - rake, z1), (y0, z1)]
    p.prism(prof, x - w / 2, x + w / 2, "olive", axis="x")
    # The windscreen on the raked part, the side windows level with it.
    zb, h = z0 + 0.55 * (z1 - z0), 0.45 * (z1 - z0)
    lean = math.degrees(math.atan2(rake, h))
    p.box((x, y1 - rake / 2 + 0.03, zb + h / 2), (w - 0.2, 0.04, 0.8 * math.hypot(rake, h)), "glass", tilt=lean)
    for side in (-1, 1):
        p.box((x + side * (w / 2 + 0.01), (y0 + y1) / 2 + 0.2, zb + h / 2), (0.03, 0.8, 0.6 * h), "glass")


def big_bird():
    """The 64N6E2: the MAZ-7910 8×8 tractor (the MAZ-543's 11.66 m × 3.05 m, its split cabs either side of the
    engine) and the semi-trailer (13.2 m, inferred) with the radar's cabin, the two-faced array on its turntable over
    the gooseneck: 6.0 m wide, 4.0 m high, its top 8.6 m up (inferred from the photographs)."""
    body = Part()
    # The tractor: front at y = 10.7, 11.66 m long.
    body.box((0, 4.9, 1.15), (2.6, 11.4, 0.6), "dark")  # frame
    body.box((0, 10.55, 0.95), (3.05, 0.3, 0.45), "dark")  # bumper
    body.box((0, 9.4, 1.75), (1.05, 2.2, 1.5), "olive")  # engine hood between the cabs
    body.box((0, 10.45, 1.75), (0.9, 0.08, 1.1), "dark")  # grille
    for x in (-1.0, 1.0):
        cab(body, x, 7.9, 10.5, 1.05, 1.0, 2.95)
        body.box((x * 1.32, 10.52, 1.65), (0.25, 0.04, 0.25), "lamp")
    body.box((0, 6.6, 1.95), (2.9, 2.6, 1.6), "olive")  # engine / cooling compartment behind the cabs
    for x in (-1.25, 1.25):
        body.box((x, 4.9, 1.55), (0.55, 10.8, 0.12), "olive")  # mudguards over the wheels
    body.axles((7.2, 5.0, 1.7, -0.5), 2.45, 0.78, 0.6)
    # The semi-trailer: the gooseneck over the tractor's rear, the low deck behind.
    body.box((0, 0.6, 1.95), (2.9, 4.6, 0.5), "olive")  # gooseneck deck
    body.box((0, -5.55, 1.25), (3.0, 9.5, 0.5), "olive")  # deck
    body.box((0, -4.0, 2.55), (3.0, 3.6, 2.1), "olive")  # generator housing
    body.box((0, -8.05, 2.75), (3.05, 4.4, 2.5), "olive")  # the radar's equipment cabin
    for x in (-1.53, 1.53):
        body.box((x, -8.05, 3.0), (0.02, 0.9, 1.4), "dark")  # cabin doors
    body.axles((-7.0, -8.3, -9.6), 2.45, 0.6, 0.5)
    body.box((0, 0.6, 2.35), (2.2, 2.2, 0.3), "steel")  # turntable base
    o = body.obj("radar_64n6e2")
    # The antenna, its axis at y = 0.6 on the turntable (2.5 m up).
    ant = Part()
    ant.box((0, 0, 0.55), (1.6, 1.4, 1.1), "olive")  # pedestal
    ant.box((0, 0, 1.6), (4.4, 0.6, 0.9), "array")  # IFF strip
    prof = [(-2.8, 2.1), (-3.0, 2.3), (-3.0, 5.4), (-2.4, 6.1), (2.4, 6.1), (3.0, 5.4), (3.0, 2.3), (2.8, 2.1)]
    ant.prism(prof, -0.5, 0.5, "array")
    ant.box((0, 0, 4.1), (0.25, 1.06, 4.0), "olive")  # the spine between the faces
    for z in (2.15, 5.35):
        ant.box((0, 0, z), (6.06, 1.06, 0.12), "olive")  # frame bars
    ant.box((0, 0, 6.35), (9.0, 0.22, 0.22), "steel")  # the boom over the array
    ant.box((0, 0, 6.2), (0.4, 0.4, 0.3), "steel")
    for x in (-4.5, 4.5):
        ant.box((x, 0, 6.35), (0.3, 0.3, 0.3), "dark")
    ant.obj("antenna", o, (0, 0.6, 2.5))
    return o


def cheese_board():
    """The 96L6E on the MZKT-7930 8×8 (12.7 m × 3.0 m, the cab 3.29 m high): the cab, the equipment box behind it,
    the antenna on its post, the rear cabin with the levelling jacks; the array 3.4 m × 4.0 m leaned back 10°, the
    lattice IFF array under it, its top 8.0 m up (inferred from the photographs)."""
    body = Part()
    body.box((0, 0, 1.1), (2.6, 12.4, 0.5), "dark")  # frame
    body.box((0, 6.2, 0.9), (2.9, 0.3, 0.4), "dark")  # bumper
    cab(body, 0, 3.7, 6.35, 3.0, 1.1, 3.29, rake=0.5)
    for x in (-1.2, 1.2):
        body.box((x, 6.36, 1.4), (0.3, 0.04, 0.2), "lamp")
    body.box((0, 2.6, 2.1), (2.9, 2.0, 1.8), "olive")  # equipment box behind the cab
    body.box((0, 0.6, 1.75), (2.9, 2.0, 0.8), "olive")  # deck under the antenna
    body.box((0, -3.8, 2.5), (3.0, 5.0, 2.3), "olive")  # rear cabin
    for x in (-1.51, 1.51):
        body.box((x, -3.0, 2.6), (0.02, 0.9, 1.5), "dark")
    for x in (-1.3, 1.3):
        body.box((x, -6.1, 0.6), (0.18, 0.18, 1.2), "steel")  # jacks
        body.box((x, -0.1, 1.45), (0.5, 12.0, 0.1), "olive")  # mudguards
    body.axles((4.6, 2.6, -2.6, -4.4), 2.3, 0.7, 0.55)
    body.box((0, 0.6, 2.25), (1.6, 1.6, 0.2), "steel")  # turntable base
    o = body.obj("radar_96l6e")
    # The antenna, its axis at y = 0.6 on the turntable (2.35 m up).
    ant = Part()
    ant.box((0, 0, 0.4), (1.1, 1.0, 0.8), "olive")  # post
    for x in (-1.6, -1.2, -0.8, -0.4, 0, 0.4, 0.8, 1.2, 1.6):
        ant.box((x, 0, 1.25), (0.06, 0.06, 0.9), "steel")  # the IFF lattice
    for z in (0.85, 1.25, 1.65):
        ant.box((0, 0, z), (3.3, 0.06, 0.06), "steel")
    prof = [(-1.7, 1.75), (1.7, 1.75), (1.7, 5.75), (-1.7, 5.75)]
    ant.prism(prof, -0.15, 0.2, "olive", tilt=10, pivot=(0, 0, 1.75))
    ant.box((0, -0.35, 2.2), (0.5, 0.5, 0.8), "olive", tilt=10)  # the drive housing on its back
    ant.obj("antenna", o, (0, 0.6, 2.35))
    return o


def tomb_stone():
    """The 30N6E2 on its MAZ-7910 8×8 (the MAZ-543's 11.66 m × 3.05 m): the driver's cab on the left, an equipment box
    on the right, the engine compartment behind them, the antenna's turntable amidships and the control cabin behind
    it; the flat array 3.5 m × 3.8 m leaned back 20°, its bottom clear of the cabin, its top 7.4 m up, with the mast
    beside it (inferred from the photographs)."""
    body = Part()
    body.box((0, 0, 1.15), (2.6, 11.4, 0.6), "dark")  # frame
    body.box((0, 5.7, 0.95), (3.05, 0.3, 0.45), "dark")  # bumper
    cab(body, -0.9, 3.4, 5.7, 1.25, 1.0, 3.0)
    body.prism([(3.4, 1.0), (5.7, 1.0), (5.7, 2.1), (5.2, 2.7), (3.4, 2.7)], 0.3, 1.52, "olive", axis="x")  # box
    body.box((-0.05, 5.6, 1.85), (0.75, 0.08, 1.0), "dark")  # grille
    for x in (-1.3, 1.3):
        body.box((x, 5.72, 1.6), (0.25, 0.04, 0.25), "lamp")
    body.box((0, 2.5, 1.95), (2.9, 1.8, 1.5), "olive")  # engine compartment
    body.box((0, 0.6, 1.75), (2.4, 2.0, 0.6), "olive")  # deck under the turntable
    body.box((0, -3.4, 2.6), (3.05, 4.8, 2.2), "olive")  # control cabin
    for x in (-1.53, 1.53):
        body.box((x, -3.0, 2.7), (0.02, 0.9, 1.4), "dark")
        body.box((x * 0.82, 0.0, 1.55), (0.55, 10.8, 0.12), "olive")  # mudguards
    body.axles((3.4, 1.2, -2.1, -4.3), 2.45, 0.78, 0.6)
    body.box((0, 0.6, 2.15), (1.8, 1.8, 0.2), "steel")  # turntable base
    o = body.obj("radar_30n6e2")
    # The antenna, its axis at y = 0.6 on the turntable (2.25 m up): the post, the array facing forward at rest.
    ant = Part()
    ant.box((0, 0, 0.8), (1.2, 1.2, 1.6), "olive")  # post
    prof = [(-1.75, 1.65), (1.75, 1.65), (1.75, 4.85), (1.25, 5.45), (-1.25, 5.45), (-1.75, 4.85)]
    ant.prism(prof, -0.2, 0.2, "olive", tilt=20, pivot=(0, 0, 1.65))
    ant.box((0, -0.45, 2.3), (0.6, 0.5, 1.2), "olive", tilt=20)  # the drive housing on its back
    ant.box((1.0, -0.3, 3.3), (0.14, 0.14, 5.4), "steel")  # the mast beside it, its foot clear of the engine
    ant.obj("antenna", o, (0, 0.6, 2.25))
    return o


def export(build, mid, out_root):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    o = build()
    # The middle of the footprint on the origin; the tyres SINK m into the ground, so they meet the drawn terrain
    # (its triangles lie a little off the ground height at a point).
    ys = [v.co.y for v in o.data.vertices]
    y_mid = (min(ys) + max(ys)) / 2
    o.data.transform(Matrix.Translation((0, -y_mid, -SINK)))
    for c in o.children:
        c.location.y -= y_mid
        c.location.z -= SINK
    out = os.path.join(out_root, mid)
    os.makedirs(out, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out, mid + ".glb"),
        export_format="GLB",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    tris = sum(len(p.vertices) - 2 for c in [o, *o.children] for p in c.data.polygons)
    print("MODEL", mid, "tris", tris)


args = sys.argv[sys.argv.index("--") + 1:]
export(big_bird, "radar_64n6e2", args[0])
export(cheese_board, "radar_96l6e", args[0])
export(tomb_stone, "radar_30n6e2", args[0])
