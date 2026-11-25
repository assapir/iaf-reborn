# The Eitam (the IAF's Gulfstream G550 CAEW) as our own low-poly model (docs/ai.md §24.3): lofted sections in plain
# colours, true size where Wikipedia gives it (length 29.39 m, span 28.50 m), the rest matched side by side to public
# photographs of the CAEW (Wikimedia Commons: 537 at Le Bourget 2008, 569 at Aero India 2009, 537 in flight 2015;
# inferred): the G550's swept wing with winglets, its T-tail with the satcom bullet on top, the two engines high on
# the rear fuselage; the CAEW's long drooped nose radome, the bulbous tail radome under the fin, the flat side cheeks
# of the L-band arrays from behind the cockpit to over the wing (no cabin windows) and the belly blister; the flight
# deck's six windows (two windshield panes, two side windows a side) in dark glass with thin frames. Its paint as
# in those photographs: white, the radomes a shade greyer, the blue cheatline from the cheek's lower aft corner up to
# the fin; the IAF roundel on the fin, the nacelles and the wings, the serial 537 on the fin, ISRAEL AIR FORCE on the
# cheeks (tools/eitam/markings.png, ours, drawn with ImageMagick). Nose along -Z (glTF), the origin at the middle of
# its length on the fuselage's axis; it is drawn in the air only (no gear). Run once by hand, then committed:
#
#   blender -b --factory-startup -P tools/eitam/eitam.py -- shared/extra/models
import math
import os
import sys

import bpy
import bmesh


LENGTH = 29.39
SPAN = 28.50
HERE = os.path.dirname(os.path.abspath(__file__))
# sRGB, roughness (the photographs' white, the radomes' slightly greyer composite, the cheatline's blue).
PAINT = {
    "white": ((0.92, 0.93, 0.94), 0.45),
    "radome": ((0.88, 0.89, 0.90), 0.55),
    "blue": ((0.11, 0.27, 0.63), 0.45),
    "dark": ((0.07, 0.08, 0.09), 0.3),
    "glass": ((0.02, 0.025, 0.03), 0.3),
    "frame": ((0.62, 0.64, 0.66), 0.4),
    "metal": ((0.40, 0.41, 0.42), 0.35),
    "decal": ((1.0, 1.0, 1.0), 0.45),
    "paint": ((1.0, 1.0, 1.0), 0.5),
}
# The skin's paints, drawn as one material ("paint") coloured per face corner: Godot stores each surface's positions
# relative to its own bounds (compressed glTF meshes), so two materials meeting on one edge would open a hairline
# crack between them (the radome's seam under the windshield, 25 Nov 2026).
SKIN = ("white", "radome")
# The markings' boxes in markings.png (1024 x 512 px): u0, v0 (top left), u1, v1.
ROUNDEL = (0, 0, 256, 256)
SERIAL = (290, 0, 680, 170)
TITLE = (10, 255, 930, 355)


def lin(c):
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def material(name):
    m = bpy.data.materials.new(name)
    rgb, rough = PAINT[name]
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*lin(rgb), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if name == "paint":
        col = nt.nodes.new("ShaderNodeVertexColor")
        col.layer_name = "paint"
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    if name == "decal":
        # The markings over the paint, cut out by their alpha (glTF MASK: the exporter reads the Round node).
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(HERE, "markings.png"))
        cut = nt.nodes.new("ShaderNodeMath")
        cut.operation = "ROUND"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
        nt.links.new(cut.outputs[0], bsdf.inputs["Alpha"])
    return m


class Part:
    """One mesh in Blender's frame (x right, y forward, z up), metres."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("uv")
        self.mats = []
        self.decals = []

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

    def strip(self, lower, upper, mat):
        """A band between two rows of points (a painted line just off the skin)."""
        k = self._mat(mat)
        lo = [self.bm.verts.new(p) for p in lower]
        up = [self.bm.verts.new(p) for p in upper]
        for i in range(len(lo) - 1):
            self.bm.faces.new([lo[i], lo[i + 1], up[i + 1], up[i]]).material_index = k

    def pane(self, s, quad, n=3, rim=0.045):
        """A window on side `s`: its corners (y, height) (lower aft, lower fore, upper fore, upper aft; a height of
        CENTRE is the crown's at that y) as a grid on the skin, the frame under the glass inset by `rim` m."""
        ya = [(y, ang_at(y, z)) for y, z in quad]
        c = [skin(s, y, a) for y, a in ya]
        span = (math.dist(c[0], c[1]) + math.dist(c[3], c[2])) / 2
        tall = (math.dist(c[0], c[3]) + math.dist(c[1], c[2])) / 2
        for mat, out, eu, ev in (("frame", 0.008, 0.0, 0.0), ("glass", 0.014, rim / span, rim / tall)):
            k = self._mat(mat)
            grid = []
            for j in range(n + 1):
                v = ev + (1 - 2 * ev) * j / n
                row = []
                for i in range(n + 1):
                    u = eu + (1 - 2 * eu) * i / n
                    y = (1 - v) * ((1 - u) * ya[0][0] + u * ya[1][0]) + v * ((1 - u) * ya[3][0] + u * ya[2][0])
                    a = (1 - v) * ((1 - u) * ya[0][1] + u * ya[1][1]) + v * ((1 - u) * ya[3][1] + u * ya[2][1])
                    row.append(self.bm.verts.new(skin(s, y, a, out)))
                grid.append(row)
            for j in range(n):
                for i in range(n):
                    f = self.bm.faces.new([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
                    f.material_index = k

    def decal(self, x, y, z, w, h, box, side):
        """A marking `w` x `h` m centred at (x, y, z) on a side wall (`side` +1 right, -1 left), read nose to tail on
        the left and tail to nose on the right, as painted; or on a wing (`side` +2 upper, -2 lower: x span, y
        chord)."""
        self.decals.append((x, y, z, w, h, box, side))

    def _add_decals(self):
        k = self._mat("decal")
        for x, y, z, w, h, (u0, v0, u1, v1), side in self.decals:
            if abs(side) == 1:
                # Corners seen from outside, counter-clockwise: the text runs aft on the left, forward on the right.
                a = side
                pts = [(x, y - a * w / 2, z - h / 2), (x, y + a * w / 2, z - h / 2), (x, y + a * w / 2, z + h / 2),
                       (x, y - a * w / 2, z + h / 2)]
            else:
                pts = [(x - w / 2, y - h / 2, z), (x + w / 2, y - h / 2, z), (x + w / 2, y + h / 2, z),
                       (x - w / 2, y + h / 2, z)]
                if side < 0:
                    pts = [pts[1], pts[0], pts[3], pts[2]]
            uvs = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
            f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
            f.material_index = k
            for loop, (u, v) in zip(f.loops, uvs):
                loop[self.uv].uv = (u / 1024.0, 1.0 - v / 512.0)

    def obj(self, name):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-4)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self._add_decals()
        col = self.bm.loops.layers.float_color.new("paint")
        mats = [m for m in self.mats if m not in SKIN] + ["paint"]
        for f in self.bm.faces:
            m = self.mats[f.material_index]
            rgb = lin(PAINT[m][0]) if m in SKIN else (1.0, 1.0, 1.0)
            for loop in f.loops:
                loop[col] = (*rgb, 1.0)
            f.material_index = mats.index("paint" if m in SKIN else m)
        self.mats = mats
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(material(m))
        for p in me.polygons:
            p.use_smooth = me.materials[p.material_index].name.split(".")[0] != "decal"
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        return o


N = 24


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


HALF = LENGTH / 2
# The fuselage from the nose radome's tip back to the tail radome's: (y, half width, half height, centre z), read off
# the side photographs (the drooped nose radome to the cockpit, the tail cone rising to the radome's bulb).
STATIONS = [
    (HALF, 0.0, 0.0, -0.90, 2.0),
    (HALF - 0.07, 0.24, 0.17, -0.87, 2.0),
    (HALF - 0.25, 0.42, 0.29, -0.81, 2.5),
    (HALF - 0.7, 0.80, 0.49, -0.73, 3.0),
    (HALF - 1.3, 1.02, 0.69, -0.615, 4.0),
    (HALF - 2.6, 1.18, 0.90, -0.42, 6.0),
    (HALF - 3.5, 1.27, 1.20, -0.12, 4.0),
    (HALF - 4.5, 1.30, 1.32, 0.0, 2.0),
    (-7.0, 1.30, 1.32, 0.0, 2.0),
    (-10.0, 1.12, 1.14, 0.12, 2.0),
    (-12.4, 0.92, 0.94, 0.16, 2.0),
    (-13.6, 0.86, 0.86, 0.14, 2.0),
    (-14.3, 0.62, 0.62, 0.12, 2.0),
    (-HALF, 0.0, 0.0, 0.10, 2.0),
]


def section(y):
    """The fuselage's (half width, half height, centre z, upper exponent) at y, between its stations."""
    for a, b in zip(STATIONS, STATIONS[1:]):
        if b[0] <= y <= a[0]:
            t = (a[0] - y) / (a[0] - b[0])
            return tuple(p + t * (q - p) for p, q in zip(a[1:], b[1:]))
    return 0.0, 0.0, 0.0, 2.0


def at(y):
    """The fuselage's (half width, half height, centre z) at y."""
    return section(y)[:3]


def sides(ang, k):
    """(cos, sin) of `ang` with the upper half squared off by the exponent `k` (2: an ellipse): the flight deck's
    flat windshield and its shoulders."""
    c, s = math.cos(ang), math.sin(ang)
    if s <= 0 or k == 2.0:
        return c, s
    return math.copysign(abs(c) ** (2 / k), c), s ** (2 / k)


def skin(s, y, ang, out=0.0):
    """The point at angle `ang` (rad, from the side's middle up) on side `s` at y, `out` m off the skin."""
    rx, rz, cz, k = section(y)
    c, si = sides(ang, k)
    return (s * (rx + out) * c, y, cz + (rz + out) * si)


def ang_at(y, z):
    """The angle on the skin (skin()) at y of the height z; CENTRE is the crown."""
    rx, rz, cz, k = section(y)
    if z is CENTRE:
        return math.acos((0.03 / rx) ** (k / 2))  # 3 cm off the centre line: the centre post
    h = max(-1.0, min(1.0, (z - cz) / rz))
    return math.asin(h if h <= 0 else h ** (k / 2))


CENTRE = None
# The flight deck's windows a side as (y, height) corners: lower aft, lower fore, upper fore, upper aft. The side
# window with its raked front edge, the small forward side window between it and the windshield, the windshield pane
# from its side post to the centre post.
WINDOWS = [
    [(HALF - 4.17, 0.53), (HALF - 3.39, 0.53), (HALF - 3.74, 0.97), (HALF - 4.17, 0.97)],
    [(HALF - 3.31, 0.53), (HALF - 2.64, 0.47), (HALF - 3.47, 0.95), (HALF - 3.70, 0.95)],
    [(HALF - 2.58, 0.47), (HALF - 2.62, CENTRE), (HALF - 3.31, CENTRE), (HALF - 3.41, 0.95)],
]


def build():
    body = Part()
    rings = [[skin(1, y, 2 * math.pi * i / N) for i in range(N)] if rx > 0 else [(0, y, cz)] * N
             for y, rx, rz, cz, _ in STATIONS]
    body.loft(rings[:6], "radome", cap=False)  # the nose radome
    body.loft(rings[5:11], "white", cap=False)
    body.loft(rings[10:], "radome", cap=False)  # the tail radome
    # The flight deck's six windows (two windshield panes, two side windows a side), dark glass in a thin grey frame,
    # the white posts between them; corners (y, height) read off the Le Bourget photograph from the same camera, the
    # windshield's on the centre line (CENTRE).
    for s in (-1, 1):
        for quad in WINDOWS:
            body.pane(s, quad)
    # The side cheeks (the L-band arrays): flat slabs on the upper side from behind the cockpit to over the wing,
    # their front rounded in plan, (y, the share of their full bulge).
    for s in (-1, 1):
        rings = []
        for y, k in [(HALF - 6.1, 0.0), (HALF - 6.5, 0.55), (HALF - 7.2, 0.9), (HALF - 7.8, 1.0), (-1.9, 1.0),
                     (-2.5, 0.6), (-2.8, 0.0)]:
            rx, rz, cz = at(y)
            wall, hh = rx + 0.3 * k, 0.8 * (0.55 + 0.45 * k)
            ring = []
            for a in [math.pi * (i / 8 - 0.5) for i in range(9)]:
                # A flat wall with rounded edges, its top and bottom edges on the skin.
                z = 0.24 + hh * math.sin(a)
                skin_x = rx * math.sqrt(max(0.0, 1.0 - ((z - cz) / rz) ** 2)) - 0.03
                ring.append((s * max(skin_x, wall * max(0.0, math.cos(a)) ** 0.35), y, z))
            rings.append(ring)
        body.loft(rings, "radome")
    # The belly blister behind the wing.
    body.loft([ellipse(y, rx, rz, cz=-1.28 + rz * 0.3, n=12) for y, rx, rz in
               [(-2.2, 0.0, 0.0), (-2.6, 0.32, 0.18), (-4.2, 0.38, 0.22), (-4.9, 0.0, 0.0)]], "radome", cap=False)
    # The cheatline: from under the cheek's lower aft corner, rising aft across the side, under the engine, to the
    # fin's root.
    for s in (-1, 1):
        ys = [-1.4 - 0.5 * i for i in range(21)]
        ang = [math.radians(-38 + 115 * min(1.0, i / 17)) for i in range(21)]
        body.strip([skin(s, y, a - 0.2 / at(y)[1], 0.035) for y, a in zip(ys, ang)],
                   [skin(s, y, a + 0.2 / at(y)[1], 0.035) for y, a in zip(ys, ang)], "blue")
    # The wing: low, swept 27° (inferred), its root at the fuselage's side, the winglets canted out.
    sweep = math.tan(math.radians(27))
    root_le, root_c, tip_c = 1.0, 5.6, 1.5
    tip_x = SPAN / 2 - 0.3
    tz = -0.85 + 0.06 * tip_x
    for s in (-1, 1):
        secs = [foil(s * 1.1, root_le, root_c, 0.7, -0.85), foil(s * tip_x, root_le - sweep * (tip_x - 1.1), tip_c,
                                                                 0.18, tz)]
        body.loft(secs, "white")
        wl = [fin(tz, root_le - sweep * (tip_x - 1.1), tip_c, 0.16, x=s * tip_x),
              fin(tz + 2.1, root_le - sweep * (tip_x - 1.1) - 1.1, 0.7, 0.08, x=s * (tip_x + 0.3))]
        body.loft(wl, "white")
        # The roundel near the tip, over the wing and under it.
        rx = s * (tip_x - 2.6)
        ry = root_le - sweep * (abs(rx) - 1.1) - 1.2
        rz = -0.85 + 0.06 * abs(rx)
        body.decal(rx, ry, rz + 0.12, 1.4, 1.4, ROUNDEL, 2)
        body.decal(rx, ry, rz - 0.07, 1.4, 1.4, ROUNDEL, -2)
        # The engine high on the rear fuselage: its nacelle, intake, exhaust and pylon; the roundel on its side.
        cx, cz = s * 2.3, 1.05
        nac = [ellipse(y, r, r, cx=cx, cz=cz) for y, r in [(-8.7, 0.76), (-9.1, 0.9), (-12.0, 0.84), (-13.5, 0.6)]]
        body.loft(nac, "white", cap=False)
        body.loft([ellipse(-8.72, 0.68, 0.68, cx=cx, cz=cz), ellipse(-9.0, 0.68, 0.68, cx=cx, cz=cz)], "dark")
        body.loft([ellipse(-13.5, 0.6, 0.6, cx=cx, cz=cz), ellipse(-13.4, 0.42, 0.42, cx=cx, cz=cz)], "metal")
        body.loft([foil(s * 0.8, -10.0, 2.6, 0.4, cz - 0.1), foil(s * (abs(cx) - 0.5), -10.0, 2.6, 0.35, cz)], "white")
        body.decal(s * (abs(cx) + 0.92), -10.9, cz + 0.05, 0.85, 0.85, ROUNDEL, s)
    # The T-tail: the fin from the rear fuselage up, swept, the stabiliser and the satcom bullet on top.
    fin_root, fin_top = 0.9, 5.4
    body.loft([fin(fin_root, -10.8, 4.2, 0.45), fin(fin_top, -12.9, 2.0, 0.22)], "white")
    for s in (-1, 1):
        body.loft([foil(s * 0.1, -12.4, 2.5, 0.25, fin_top), foil(s * 5.0, -13.8, 1.1, 0.12, fin_top + 0.3)], "white")
        # The roundel and the serial on the fin.
        body.decal(s * 0.19, -13.2, 4.2, 0.95, 0.95, ROUNDEL, s)
        body.decal(s * 0.22, -13.2, 3.25, 0.75, 0.33, SERIAL, s)
        # ISRAEL AIR FORCE on the cheek.
        body.decal(s * (at(2.6)[0] + 0.32), 2.6, 0.4, 3.6, 0.39, TITLE, s)
    body.loft([ellipse(y, r, r * 0.9, cz=fin_top + 0.25, n=12) for y, r in
               [(-12.3, 0.0), (-12.7, 0.3), (-13.6, 0.42), (-14.3, 0.36), (-14.9, 0.0)]], "white", cap=False)
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
