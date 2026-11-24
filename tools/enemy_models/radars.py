# The S-300PMU-2's radars as our own low-poly models (docs/ai.md §15.4) on the MAZ-543 chassis of a Sketchfab model:
# the 64N6E2 of the 83M6E2 network on its tractor and semi-trailer, the 96L6E and the 30N6E2. The radars are boxes and
# prisms in plain colours, true size where a source gives it, else read off the reference photographs (inferred; the
# figures and photos in docs/ai.md).
# Nose along -Z (glTF), on the ground at the middle of its footprint. Each antenna (the array, its IFF strip, the
# pedestal above the turntable) is the node `antenna`, its origin on the turning axis: air_defence.gd turns it about
# up (a search radar's while it radiates, the track radar's onto its track). Run once by hand, then committed:
#
#   blender -b --factory-startup -P tools/enemy_models/radars.py -- assets/source/enemy_models shared/extra/models
import math
import os
import shutil
import sys
import tempfile
import zipfile

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert import clean_images  # noqa: E402

# The chassis: "MAZ-543 Uragan 9P117" (Sketchfab, CC BY 4.0; docs/credits.md), the user's own download of 24 Nov 2026,
# with its R-17 missile, erector and launcher gear cut off; scaled to the MAZ-543's 11.66 m (ru.wikipedia).
MAZ = "maz-543_uragan_9p117.zip"
MAZ_LENGTH = 11.66
# The top of the chassis' side lockers (m above the ground), where the radar's decks sit.
DECK = 2.6

# The paint (sRGB): the olive of the other enemy models (the S-300 launcher's and the 30N6E's textures), the 64N6E2's
# array faces a darker olive grey; roughness.
PAINT = {
    "olive": ((0.36, 0.38, 0.26), 0.8),
    "array": ((0.30, 0.32, 0.24), 0.7),
    "dark": ((0.12, 0.12, 0.11), 0.9),
    "tyre": ((0.06, 0.06, 0.055), 0.95),
    "steel": ((0.30, 0.31, 0.30), 0.5),
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
        me.uv_layers.new(name="UVMap")  # the chassis' map, joined by name (join)
        self.bm.free()
        for m in self.mats:
            me.materials.append(material(m))
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        if parent is not None:
            o.parent = parent
        o.location = at
        return o


def _maz_launcher(mat, mn, mx):
    """A loose part of the 9P117 that belongs to the launcher, by its bounds in the source's frame (nose along -y,
    metres; the cab ends at y = -2.84, the body's top is at z = 1.72): the missile and its cradle (above the body
    behind the cab), the erector (its own texture behind the cab), the blast deflector and the rear jacks (behind the
    last axle), the missile's trough between the side lockers. The wheels stay."""
    c = (mn + mx) / 2
    if mat == "wheel_lf.0":
        return False
    if c.y > 7.3:
        return True
    if mat == "chassis.0" and c.y > -1.25:
        return True
    if mat == "chassis.1" and mn.z > 1.5 and c.y > -4.0 and abs(c.x) < 0.8:
        return True
    if mat == "chassis.2" and abs(c.x) < 0.6 and mn.z > 1.1 and -2.9 < c.y < 0.6:
        return True
    return c.y > -3.0 and mn.z > 1.72


def _olive(im):
    """The 9P117's three-tone camouflage repainted the olive of the other S-300 parts: each painted pixel the olive at
    its own brightness squeezed to 0.97..1.03 (the panel lines, rivets and stains kept, the camouflage's patches almost
    gone); the near-black parts (windows, grilles, gaps) kept."""
    w, h = im.size
    px = np.empty(w * h * 4, dtype=np.float32)
    im.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    lum = px[:, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)  # the stored sRGB values
    paint = np.array(PAINT["olive"][0], dtype=np.float32)
    tone = 0.97 + 0.06 * np.clip((lum - 0.2) / 0.45, 0.0, 1.0)
    keep = np.clip((lum - 0.1) / 0.06, 0.0, 1.0)[:, None]
    px[:, :3] = px[:, :3] * (1 - keep) + (paint * tone[:, None]) * keep
    im.pixels.foreach_set(px.ravel())
    im.update()


def maz_chassis(src_dir, front_y):
    """The MAZ-543 chassis (the cabs, wheels, frame and side lockers), its nose along +y at `front_y`, on the ground."""
    tmp = tempfile.mkdtemp()
    with zipfile.ZipFile(os.path.join(src_dir, MAZ)) as z:
        z.extractall(tmp)
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(tmp, "scene.gltf"))
    for im in bpy.data.images:
        im.pack()
    shutil.rmtree(tmp)
    new = [o for o in bpy.context.scene.objects if o not in before]
    objs = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    for o in objs:
        uv = o.data.uv_layers
        while len(uv) > 1:
            uv.remove(uv[-1])
        uv[0].name = "UVMap"
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="LOOSE")
        bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.data.materials
             and o.data.materials[0].name in ("chassis.0", "chassis.1", "chassis.2", "wheel_lf.0")]
    for o in list(parts):
        ws = [Vector(c) for c in o.bound_box]
        mn = Vector([min(w[i] for w in ws) for i in range(3)])
        mx = Vector([max(w[i] for w in ws) for i in range(3)])
        if _maz_launcher(o.data.materials[0].name, mn, mx):
            parts.remove(o)
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    m = o.modifiers.new("planar", "DECIMATE")
    m.decimate_type = "DISSOLVE"
    m.angle_limit = math.radians(0.5)
    m.delimit = {"UV", "MATERIAL", "SHARP"}
    bpy.ops.object.convert(target="MESH")
    vs = [v.co for v in o.data.vertices]
    mn = Vector([min(v[i] for v in vs) for i in range(3)])
    mx = Vector([max(v[i] for v in vs) for i in range(3)])
    k = MAZ_LENGTH / (mx.y - mn.y)
    # Nose to +y, the length to MAZ_LENGTH, the middle across on x = 0, the tyres' bottom on z = 0, the nose at front_y.
    o.data.transform(
        Matrix.Translation((0, front_y, 0))
        @ Matrix.Rotation(math.pi, 4, "Z")
        @ Matrix.Scale(k, 4)
        @ Matrix.Translation((-(mn.x + mx.x) / 2, -mn.y, -mn.z))
    )
    # Matt paint like the radar's own parts; the texture read through the one UV map.
    for mat in o.data.materials:
        for n in mat.node_tree.nodes:
            if n.type == "UVMAP":
                n.uv_map = "UVMap"
            elif n.type == "BSDF_PRINCIPLED":
                n.inputs["Roughness"].default_value = 0.8
                n.inputs["Metallic"].default_value = 0.0
            elif n.type == "TEX_IMAGE" and n.image.name.startswith("chassis") and not n.image.get("olive"):
                _olive(n.image)
                n.image["olive"] = True
    return o


def engine_cover(body, front_y):
    """The engine compartment's cover behind the cabs, where the 9P117 had the missile's trough (cut off)."""
    body.box((0, front_y - 3.9, DECK - 0.5), (1.6, 3.1, 1.0), "olive")


def join(body, chassis):
    """The chassis joined into the body's mesh (its materials and textures kept)."""
    bpy.ops.object.select_all(action="DESELECT")
    chassis.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()


def big_bird():
    """The 64N6E2: the MAZ-543 chassis as the tractor (the real one a MAZ-7910) and the semi-trailer (13.2 m,
    inferred) with the radar's cabin, the two-faced array on its turntable over the gooseneck: 6.0 m wide, 4.0 m high,
    its top 9.5 m up (inferred from the photographs, raised by the chassis' lockers)."""
    body = Part()
    # The tractor (the MAZ-543 chassis): front at y = 10.7. The semi-trailer: the gooseneck over the tractor's rear,
    # on its lockers, the low deck behind.
    body.box((0, 0.6, DECK + 0.25), (2.9, 4.6, 0.5), "olive")  # gooseneck deck
    body.box((0, -5.55, 1.25), (3.0, 9.5, 0.5), "olive")  # deck
    body.box((0, -4.0, 2.55), (3.0, 3.6, 2.1), "olive")  # generator housing
    body.box((0, -8.05, 2.75), (3.05, 4.4, 2.5), "olive")  # the radar's equipment cabin
    for x in (-1.53, 1.53):
        body.box((x, -8.05, 3.0), (0.02, 0.9, 1.4), "dark")  # cabin doors
    body.axles((-7.0, -8.3, -9.6), 2.45, 0.6, 0.5)
    body.box((0, 0.6, DECK + 0.65), (2.2, 2.2, 0.3), "steel")  # turntable base
    engine_cover(body, 10.7)
    o = body.obj("radar_64n6e2")
    join(o, maz_chassis(src_dir, 10.7))
    # The antenna, its axis at y = 0.6 on the turntable (DECK + 0.8 m up).
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
    ant.obj("antenna", o, (0, 0.6, DECK + 0.8))
    return o


def cheese_board():
    """The 96L6E on the MAZ-543 chassis (the real one an MZKT-7930): the antenna on its post, the rear cabin with the
    levelling jacks; the array 3.4 m × 4.0 m leaned back 10°, the lattice IFF array under it, its top 8.75 m up
    (inferred from the photographs, raised by the chassis' lockers)."""
    body = Part()
    body.box((0, 0.6, DECK + 0.15), (2.4, 2.0, 0.3), "olive")  # deck under the antenna
    body.box((0, -3.4, 2.6), (3.05, 4.6, 2.3), "olive")  # rear cabin
    for x in (-1.53, 1.53):
        body.box((x, -2.8, 2.7), (0.02, 0.9, 1.5), "dark")
    for x in (-1.3, 1.3):
        body.box((x, -5.9, 0.6), (0.18, 0.18, 1.2), "steel")  # jacks
    body.box((0, 0.6, DECK + 0.4), (1.6, 1.6, 0.2), "steel")  # turntable base
    engine_cover(body, 5.83)
    o = body.obj("radar_96l6e")
    join(o, maz_chassis(src_dir, 5.83))
    # The antenna, its axis at y = 0.6 on the turntable (DECK + 0.5 m up).
    ant = Part()
    ant.box((0, 0, 0.4), (1.1, 1.0, 0.8), "olive")  # post
    for x in (-1.6, -1.2, -0.8, -0.4, 0, 0.4, 0.8, 1.2, 1.6):
        ant.box((x, 0, 1.25), (0.06, 0.06, 0.9), "steel")  # the IFF lattice
    for z in (0.85, 1.25, 1.65):
        ant.box((0, 0, z), (3.3, 0.06, 0.06), "steel")
    prof = [(-1.7, 1.75), (1.7, 1.75), (1.7, 5.75), (-1.7, 5.75)]
    ant.prism(prof, -0.15, 0.2, "olive", tilt=10, pivot=(0, 0, 1.75))
    ant.box((0, -0.35, 2.2), (0.5, 0.5, 0.8), "olive", tilt=10)  # the drive housing on its back
    ant.obj("antenna", o, (0, 0.6, DECK + 0.5))
    return o


def tomb_stone():
    """The 30N6E2 on the MAZ-543 chassis (the real one a MAZ-7910): the antenna's turntable amidships and the control
    cabin behind it; the flat array 3.5 m × 3.8 m leaned back 20°, its bottom clear of the cabin, its top 8.25 m up,
    with the mast beside it (inferred from the photographs, raised by the chassis' lockers)."""
    body = Part()
    body.box((0, 0.6, DECK + 0.15), (2.4, 2.0, 0.3), "olive")  # deck under the turntable
    body.box((0, -3.4, 2.6), (3.05, 4.6, 2.3), "olive")  # control cabin
    for x in (-1.53, 1.53):
        body.box((x, -3.0, 2.7), (0.02, 0.9, 1.4), "dark")
    body.box((0, 0.6, DECK + 0.4), (1.8, 1.8, 0.2), "steel")  # turntable base
    engine_cover(body, 5.83)
    o = body.obj("radar_30n6e2")
    join(o, maz_chassis(src_dir, 5.83))
    # The antenna, its axis at y = 0.6 on the turntable (DECK + 0.5 m up): the post, the array facing forward at rest.
    ant = Part()
    ant.box((0, 0, 0.8), (1.2, 1.2, 1.6), "olive")  # post
    prof = [(-1.75, 1.65), (1.75, 1.65), (1.75, 4.85), (1.25, 5.45), (-1.25, 5.45), (-1.75, 4.85)]
    ant.prism(prof, -0.2, 0.2, "olive", tilt=20, pivot=(0, 0, 1.65))
    ant.box((0, -0.45, 2.3), (0.6, 0.5, 1.2), "olive", tilt=20)  # the drive housing on its back
    ant.box((1.0, -0.3, 3.3), (0.14, 0.14, 5.4), "steel")  # the mast beside it, its foot clear of the engine
    ant.obj("antenna", o, (0, 0.6, DECK + 0.5))
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
        export_image_format="JPEG",
        export_jpeg_quality=85,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    clean_images(os.path.join(out, mid + ".glb"))
    with zipfile.ZipFile(os.path.join(src_dir, MAZ)) as z:
        with open(os.path.join(out, "license.txt"), "wb") as f:
            f.write(z.read("license.txt"))
    tris = sum(len(p.vertices) - 2 for c in [o, *o.children] for p in c.data.polygons)
    print("MODEL", mid, "tris", tris)


args = sys.argv[sys.argv.index("--") + 1:]
src_dir = args[0]
export(big_bird, "radar_64n6e2", args[1])
export(cheese_board, "radar_96l6e", args[1])
export(tomb_stone, "radar_30n6e2", args[1])
