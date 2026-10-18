# Build the detailed F-16D (Preferences -> Extras -> Models: Detailed; docs/aircraft-models.md) from the FlightGear
# F-16 (github.com/NikolaiVChr/f16, GPL-2.0-or-later; tools/f16d/SOURCES.md) with tools/plane/kit.py:
#   - FlightGear's single-seat f16.ac made two-seat: the canopy and the spine behind it stretched aft, a second
#     cockpit, seat and pilot;
#   - placed on the original model's frame: the wing on the original's wing, the pylons moved onto the original's
#     Station helpers, the oleos compressed so the wheels touch at the original's `height` helper;
#   - the moving parts named and hinged as the original's (`<part>1/2` helpers on FlightGear's own hinge lines,
#     taken from its F-16.xml animations), the helpers the game reads copied from the original model;
#   - the IAF dorsal spine (the avionics hump of the Block 30 / 40 "Brakeet") lofted over the slim US spine, from
#     the canopy's rear end to a box under the fin that ends over the nozzle;
#   - closed gear doors (LdgDrUp, shown only with the gear up), the GE nozzle, an IAF desert livery (FlightGear's,
#     its wing roundels moved to the IAF positions) with our PBR maps (baked occlusion, panel-line normal map, roughness / metallic);
#   - written as one glb with KTX2 textures (tools/plane/glb_ktx2.py, needs `basisu`).
#
#   blender -b --python tools/f16d/rig.py -- <FlightGear f16 checkout> <assets/converted/planes/f16/f16_h.gltf> <out.glb>
#
# The original model is read only for its helper positions (where the game hangs stores, sees the wheels, …).
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "plane"))
import kit  # noqa: E402
import glb_ktx2  # noqa: E402
import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

FG, ORIG, OUT = sys.argv[sys.argv.index("--") + 1:][:3]
M = os.path.join(FG, "Models")
FAST = os.environ.get("F16D_FAST") == "1"  # skip the occlusion bake (quick geometry iterations)
LIVERY = "Liveries/Block40/90-0874.png"  # IAF desert camouflage, 101 Sqn (FlightGear's own art, GPL)
# The livery's roundel above the left wing, near the tip: centre (x, y pixels from the top-left), white disc radius.
# Its art is copied to the IAF positions below and the original is painted over.
ROUNDEL_ART = (539.4, 115.2, 25.0)
# IAF wing roundels (photos in SOURCES.md): (span, fore-aft, diameter in m, FlightGear's frame; upper surface).
# Above each wing: on the fixed panel forward of the flaperon, 43 % of the way from the fuselage side to the tip rail,
# mid-chord, 0.2 x the local chord across. Under the left wing: the mirror of the livery's own one under the right.
ROUNDELS = [(-2.65, -0.70, 0.53, True), (2.65, -0.70, 0.53, True), (-3.673, -1.184, 0.46, False)]

# FlightGear's model -> the original's frame: the wing (flaperon hinge and trailing edge) on the original's wing.
SHIFT = Vector((0.0, -1.05, 0.0))
# Two-seat: everything above the canopy sill between the fin root and the front seat is stretched aft so the canopy
# ends EXT further back (FlightGear's frame, before SHIFT); the second cockpit sits SEAT_GAP behind the first.
Y_FRONT, Y_CANOPY_REAR, Y_FIN, EXT = 3.45, 2.48, -2.8, 0.95
Z_SILL0, Z_SILL1, X_SPINE = 0.28, 0.42, 0.95
SEAT_GAP = 0.98

DROP = {"ExternalFlame", "InternalFlame", "Chute", "RNLAF_Tailroot", "Link16Antennas", "Fan", "FanSpinning",
        "FanR.001", "FanRHighSpeed", "FanRHighSpeed.001", "CanopyBackInside", "CanopyForwardInside",
        "FuselageLogoLeft", "FuselageLogoRight", "LogoPilotRight", "Rect", "VstabBandLeftAft", "VstabBandLeftFront",
        "VstabBandRightAft", "VstabBandRightFront", "VstabLogoLeftBottom", "VstabLogoLeftTop", "VstabLogoRightBottom",
        "VstabLogoRightTop", "WinglogoLeftTop", "WinglogoRightBottom", "WinglogoRightTop", "GreenPosLight2",
        "RedPosLight2", "USAF_Tailroot", "AftPosLight1"}  # the last two: inside the IAF dorsal spine
# The game's parts (docs/part-animation.md) from FlightGear's objects, with FlightGear's hinge (F-16.xml: centre and
# axis, FlightGear frame x aft, y right, z up). Axis None: a part that never turns (its own centre is the origin).
PARTS = {
    "AilerL": (["LeftUpperFlap", "LeftLowerFlap"], (1.54, -2.35, 0.12), (0.150157, -0.987872, -0.039515)),
    "AilerR": (["RightUpperFlap", "RightLowerFlap"], (1.54, 2.35, 0.12), (0.150157, 0.987872, -0.039515)),
    "ElevaL": (["LeftUpperHorizonTail", "LeftLowerHorizonTail"], (4.36, -1.965, -0.1), (0, -0.981645, -0.19072)),
    "ElevaR": (["RightUpperHorizonTail", "RightLowerHorizonTail"], (4.36, 1.965, -0.1), (0, 0.981645, -0.19072)),
    "RuddeL": (["Rudder.001", "Rudder.002", "Rudder.003", "Rudder.004", "Rudder.005"], (4.915, 0, 2.095),
               (0.547371, 0, 0.83689)),
    "SpdbrU": (["LeftUpperSpeedbrake", "RightUpperSpeedbrake"], (4.55, 0, 0.15), (0, 1, 0)),
    "SpdbrD": (["LeftLowerSpeedbrake", "RightLowerSpeedbrake"], (4.55, 0, 0.08), (0, 1, 0)),
    "Hook": (["ArresterHook"], (2.58, 0, -0.73), (0, 1, 0)),
    "LdgF": (["FrontTire", "FrontLowerStrut", "FrontUpperStrut", "FrontAftStrut"], (-2.97, 0, -0.805), (0, 1, 0)),
    "LdgL": (["LeftMainTire", "LeftUpperMainStrut", "LeftLowerMainStrut", "LeftInnerStrut", "LeftOuterLowerStrut",
              "LeftOuterUpperStrut"], (0.64, -0.44, -0.66), None),
    "LdgR": (["RightMainTire", "RightUpperMainStrut", "RightLowerMainStrut", "RightInnerStrut",
              "RightOuterLowerStrut", "RightOuterUpperStrut"], (0.64, 0.44, -0.66), None),
    "Canopy": (["CanopyFrame", "CanopyFrameInner", "CanopyForwardOutside", "CanopyBackOutside"], (-3.3, 0, 0.6),
               (0, 1, 0)),
}
# The doors' hinges (F-16.xml) for the closed copies.
DOOR_HINGES = {"ExternalLeftMainDoor": ((-0.755, -0.76, -0.43), (1, 0, 0)),
               "ExternalRightMainDoor": ((-0.755, 0.76, -0.43), (1, 0, 0)),
               "ExternalFrontGearDoor": ((-2.5, 0.28, -0.805), (0.999843, 0.015871, 0.007935)),
               "InternalFrontGearDoor": ((-2.5, 0.28, -0.805), (0.999843, 0.015871, 0.007935))}
# Oleo compression (F-16.xml): the nose oleo slides up, the main legs swing about this axis.
MAIN_COMPRESSION = {"L": ((0.0, -0.41, -0.57), (0.943612, -0.262974, 0.201098)),
                    "R": ((0.0, 0.41, -0.57), (0.943612, 0.262974, 0.201098))}
# FlightGear's pylons -> the original's stations.
PYLONS = {"LWStation1": "StationD", "LWStation2": "StationC", "LWStation3": "StationB",
          "RWStation1": "StationF", "RWStation2": "StationG", "RWStation3": "StationH",
          "CLStation": "StationE"}  # FlightGear's centreline pylon (Models/central-pylon.ac), always fitted


def fg(p):
    """FlightGear's xml frame (x aft, y right, z up) -> Blender's."""
    return Vector((p[1], -p[0], p[2]))


def from_gltf(p):
    return Vector((p[0], -p[2], p[1]))


def original():
    """The original model's root offset and its non-mesh nodes and parts {name: Blender position} (relative to the
    root, as the game's descriptor gives them)."""
    g = json.load(open(ORIG))
    nodes = g["nodes"]
    root = nodes[g["scenes"][0]["nodes"][0]]
    pos = lambda n: from_gltf(n.get("matrix", [0] * 12 + [0, 0, 0, 1])[12:15] if "matrix" in n else n.get("translation", (0, 0, 0)))
    return pos(root), {nodes[c]["name"]: pos(nodes[c]) for c in root["children"]}


def verts_world(objs):
    return [o.matrix_world @ v.co for o in objs for v in o.data.vertices]


def bounds(objs):
    pts = verts_world(objs)
    return Vector(map(min, *pts)), Vector(map(max, *pts))


def transform(objs, m):
    for o in objs:
        o.data.transform(m)


def smooth01(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def remap_y(y):
    """The two-seat stretch along y: the front seat and canopy front stay, the canopy's rear end goes EXT aft and
    the spine from there to the fin root is compressed to make room."""
    if y >= Y_FRONT or y <= Y_FIN:
        return y
    if y >= Y_CANOPY_REAR:
        return Y_FRONT + (y - Y_FRONT) * (Y_FRONT - Y_CANOPY_REAR + EXT) / (Y_FRONT - Y_CANOPY_REAR)
    return Y_FIN + (y - Y_FIN) * (Y_CANOPY_REAR - EXT - Y_FIN) / (Y_CANOPY_REAR - Y_FIN)


def two_seat(objs):
    for o in objs:
        for v in o.data.vertices:
            c = v.co
            w = smooth01((c.z - Z_SILL0) / (Z_SILL1 - Z_SILL0)) * smooth01((X_SPINE - abs(c.x)) / 0.2)
            if w > 0:
                c.y += (remap_y(c.y) - c.y) * w
        o.data.update()


def rotate_about(objs, centre, axis, angle):
    m = Matrix.Translation(centre) @ Matrix.Rotation(angle, 4, Vector(axis).normalized()) @ Matrix.Translation(-centre)
    transform(objs, m)


def compress_gear(body, target_z):
    """Oleos compressed (as loaded on the ground) until each wheel's lowest point is at target_z."""
    nose = [body["FrontTire"], body["FrontLowerStrut"]]
    dz = target_z - bounds([body["FrontTire"]])[0].z
    transform(nose, Matrix.Translation((0, 0, dz)))
    print("gear nose compression", round(dz, 3), "m")
    for side, name in (("L", "Left"), ("R", "Right")):
        c, ax = MAIN_COMPRESSION[side]
        c, ax = fg(c) + SHIFT, fg(ax).normalized()
        tyre = verts_world([body[name + "MainTire"]])
        low = lambda a: min((Matrix.Translation(c) @ Matrix.Rotation(a, 4, ax) @ Matrix.Translation(-c) @ p).z
                            for p in tyre)
        s = 1.0 if low(0.01) > low(0.0) else -1.0
        lo, hi = 0.0, 0.4
        for _ in range(30):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if low(s * mid) < target_z else (lo, mid)
        rotate_about([body[n] for n in PARTS["Ldg" + side][0]], c, ax, s * lo)
        print("gear", side, "compression", round(math.degrees(s * lo), 2), "deg")


def turned_copy(src, centre, axis, deg):
    o = src.copy()
    o.data = src.data.copy()
    kit.scene().collection.objects.link(o)
    o.data.transform(Matrix.Translation(centre) @ Matrix.Rotation(math.radians(deg), 4, axis) @
                     Matrix.Translation(-centre))
    return o


def gear_doors(body):
    """FlightGear's rest pose has the main doors shut and the nose door open. The game's LdgDr (shown while the gear
    is out): the nose door as it is, the main doors turned 95° open (F-16.xml) downwards; LdgDrUp (ours, shown with
    the gear up): the main doors as they are, the nose door turned to the angle that lays it flattest on the skin
    (least mean distance from its vertices to the fuselage and intake)."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    skin = [BVHTree.FromObject(body[n], dg) for n in ("RadarDomeTop", "AirIntake")]
    down, up = [], []
    for name, (c, ax) in DOOR_HINGES.items():
        src = body.pop(name)
        c, ax = fg(c) + SHIFT, fg(ax).normalized()
        if "Main" in name:
            opened = [turned_copy(src, c, ax, d) for d in (95, -95)]
            low = min(opened, key=lambda o: sum(v.co.z for v in o.data.vertices))
            for o in opened:
                if o is not low:
                    bpy.data.objects.remove(o)
            down.append(low)
            up.append(src)
            continue
        best = None
        for deg in range(-150, 151):
            m = Matrix.Translation(c) @ Matrix.Rotation(math.radians(deg), 4, ax) @ Matrix.Translation(-c)
            gap = sum(min(t.find_nearest(m @ v.co)[3] for t in skin) for v in src.data.vertices) / len(src.data.vertices)
            if best is None or gap < best[0]:
                best = (gap, deg)
        print("door", name, "closed by", best[1], "deg, mean gap", round(best[0], 3), "m")
        up.append(turned_copy(src, c, ax, best[1]))
        down.append(src)
    return kit.join(down, "LdgDr"), kit.join(up, "LdgDrUp")


def fit_pylons(body, helpers, root):
    """Each pylon onto its station: the middle of its bottom edge on the station, then raised or lowered so its
    surface straight above the station touches it (where the store's attach point hangs)."""
    from mathutils.bvhtree import BVHTree
    for pylon, station in PYLONS.items():
        o = body[pylon]
        lo, hi = bounds([o])
        at = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))  # the middle of its bottom edge
        st = helpers[station] + root
        d = st - at
        o.data.transform(Matrix.Translation(d))
        tree = BVHTree.FromPolygons([v.co for v in o.data.vertices], [p.vertices for p in o.data.polygons])
        hit = tree.ray_cast(st - Vector((0, 0, 0.5)), Vector((0, 0, 1)))[0]
        if hit is not None:
            o.data.transform(Matrix.Translation((0, 0, st.z - hit.z)))
            d.z += st.z - hit.z
        print("pylon", pylon, "->", station, "moved", tuple(round(x, 3) for x in d))


# The IAF dorsal spine (our frame, after SHIFT; y forward, z up). Its top runs straight from the canopy's rear end
# (SP_Y0, SP_Z0) to the fin's root (SP_Y_FIN, SP_Z_FIN: the bottom of FlightGear's fin and rudder) and stays there
# along a box under the fin to SP_Y_END, over the nozzle's exit. Half-widths (y, w) between which it is
# interpolated: the canopy's rear width, as wide as the original's spine (0.34 m) to the wing's trailing edge, the
# fin root's width under the fin. Aft of SP_Y_FLOOR the fuselage falls away to the nozzle and the box gets a flat
# floor at SP_FLOOR. Photographs: IAF F-16D 046 / 022 / 050 / 063 (Wikimedia Commons, Aldo Bidini) and 601
# (Itayba): the top line is straight from the canopy to the tail, the fin stands on it, the box ends square just
# aft of the nozzle; the original game model has the same shape (tests/godot/test_detailed_models.gd).
SP_Y0, SP_Z0 = 0.47, 0.93
SP_Y_FIN, SP_Z_FIN = -3.86, 1.148
SP_Y_END, SP_Y_FLOOR, SP_FLOOR = -6.42, -5.3, 0.62
SP_WIDTH = [(0.47, 0.21), (0.0, 0.32), (-0.3, 0.34), (-2.4, 0.34), (-3.86, 0.2), (-6.3, 0.2), (SP_Y_END, 0.17)]
SP_BLEND = 0.22  # the front SP_BLEND m grow out of FlightGear's fairing behind the canopy
SP_FILLET = 0.05  # the concave flare where the sides meet the fuselage


def interp(table, y):
    for (y0, v0), (y1, v1) in zip(table, table[1:]):
        if y1 <= y <= y0:
            return v0 + (v1 - v0) * smooth01((y0 - y) / (y0 - y1))
    return table[0][1] if y > table[0][0] else table[-1][1]


def spine_top(y):
    if y <= SP_Y_FIN:
        return SP_Z_FIN
    return SP_Z0 + (SP_Z_FIN - SP_Z0) * (SP_Y0 - y) / (SP_Y0 - SP_Y_FIN)


def dorsal_spine(body):
    """The IAF F-16D's dorsal spine: a loft of rounded-box sections over FlightGear's fuselage (`RadarDomeTop`),
    flared into it at the sides; its livery UVs are those of the fuselage under it, spread over the section (the
    camouflage runs on unbroken at its foot). The fuselage faces it covers are removed (they would bake black in the
    occlusion map, which they share with the spine), the blade antenna and the formation light are raised onto it."""
    from mathutils.bvhtree import BVHTree
    from mathutils.geometry import barycentric_transform
    skin = body["RadarDomeTop"]
    bm = bmesh.new()
    bm.from_mesh(skin.data)
    bm.transform(skin.matrix_world)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv.active
    tree = BVHTree.FromBMesh(bm)

    def surface(x, y):
        """(z, uv, material index) of the fuselage's top at (x, y), or None."""
        hit, _, i, _ = tree.ray_cast(Vector((x, y, 5.0)), Vector((0, 0, -1)))
        if hit is None:
            return None
        f = bm.faces[i]
        a, b, c = (lp.vert.co for lp in f.loops)
        ua, ub, uc = (lp[uvl].uv.to_3d() for lp in f.loops)
        return hit.z, barycentric_transform(hit, a, b, c, ua, ub, uc).to_2d(), f.material_index

    n_top, n_bot = 9, 4  # points on each upper quarter / across the floor
    rings, uvs, mat_idx = [], [], None
    ys = [SP_Y0 - i * 0.1 for i in range(int((SP_Y0 - SP_Y_END) / 0.1) + 1)] + [SP_Y_END + 0.03, SP_Y_END]
    for y in ys:
        w, top = interp(SP_WIDTH, y), spine_top(y)
        if y < SP_Y_END + 0.06:  # a slightly rounded square end
            top -= 0.03 * smooth01((SP_Y_END + 0.06 - y) / 0.06)
        side = []  # the right half from the top centre round to the foot (x >= 0)
        foot_s = surface(w + SP_FILLET, y)
        foot = max(foot_s[0] if foot_s else SP_FLOOR, SP_FLOOR if y < SP_Y_FLOOR else -9.0)
        flare = SP_FILLET * smooth01((foot - SP_FLOOR) / 0.05) if y < SP_Y_FLOOR else SP_FILLET
        rv = min(0.16, max(0.02, (top - foot) * 0.6))
        for k in range(n_top + 1):  # super-ellipse quarter: flat top, rounded shoulder
            t = math.pi / 2 * (1 - k / n_top)
            side.append((w * math.cos(t) ** (2 / 3.5), top - rv + rv * math.sin(t) ** (2 / 3.5)))
        side.append((w, foot + flare))
        for k in range(1, 5):  # concave flare onto the fuselage, its lip 2 cm under the skin
            t = math.pi / 2 * k / 4
            side.append((w + flare * (1 - math.cos(t)), foot + flare * (1 - math.sin(t)) - 0.02 * k / 4))
        pts = [(-x, z) for x, z in reversed(side[1:])] + side
        # The front grows out of FlightGear's fairing: each point starts on the fuselage under it.
        g = smooth01((SP_Y0 - y) / SP_BLEND)
        if g < 1:
            def on_skin(x, z):
                su = surface(x, y)
                return su[0] + 0.002 if su else z
            pts = [(x, on_skin(x, z) + (z - on_skin(x, z)) * g) for x, z in pts]
        # Livery: the fuselage's UVs under the foot-to-foot span, spread over the section by its arc length.
        arc = [0.0]
        for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
            arc.append(arc[-1] + math.hypot(x1 - x0, z1 - z0))
        xf = pts[-1][0]
        row = []
        for (x, z), s in zip(pts, arc):
            u = -xf + 2 * xf * s / arc[-1]
            # The fuselage ends at -5.78 and narrows before: the box's tail takes its last full row.
            su = next(filter(None, (surface(u * k, yy) for yy in (y, min(y + 0.1, SP_Y0), -5.2) for k in (1, 0.8, 0.6, 0.4))), None)
            row.append(su[1])
            if mat_idx is None and su:
                mat_idx = su[2]
        bottom_z = min(pts[0][1], pts[-1][1])
        floor = [(xf - 2 * xf * k / (n_bot + 1), bottom_z) for k in range(1, n_bot + 1)]
        rings.append([Vector((x, y, z)) for x, z in pts + floor])
        uvs.append(row + [row[0]] * n_bot)
    n_up = len(rings[0]) - n_bot
    out = bmesh.new()
    vs = [[out.verts.new(p) for p in r] for r in rings]
    uv_out = out.loops.layers.uv.new("UVMap")
    n = len(rings[0])
    for i in range(len(rings) - 1):
        for j in range(n):
            j1 = (j + 1) % n
            f = out.faces.new((vs[i][j], vs[i][j1], vs[i + 1][j1], vs[i + 1][j]))  # outward (y falls with i)
            livery = j < n_up - 1
            f.material_index = 0 if livery else 1
            for lp, (ii, jj) in zip(f.loops, ((i, j), (i, j1), (i + 1, j1), (i + 1, j))):
                lp[uv_out].uv = uvs[ii][jj] if livery else uvs[ii][0]
            f.smooth = True
    for r, rev in ((vs[-1], False), (vs[0], True)):  # end caps (the front one is flat on the fairing)
        f = out.faces.new(list(reversed(r)) if rev else r)
        f.material_index = 1
    bmesh.ops.recalc_face_normals(out, faces=out.faces[:])
    me = bpy.data.meshes.new("DorsalSpine")
    out.to_mesh(me)
    out.free()
    me.materials.append(skin.data.materials[mat_idx])
    me.materials.append(kit.material("spine_floor", (0.09, 0.09, 0.085), metallic=0.3, roughness=0.6))
    spine = bpy.data.objects.new("DorsalSpine", me)
    kit.scene().collection.objects.link(spine)
    body["DorsalSpine"] = spine

    def inside(p):
        if not (SP_Y_END + 0.02 < p.y < SP_Y0 - 0.03 and p.z > 0.25):
            return False
        return abs(p.x) < interp(SP_WIDTH, p.y) - 0.01 and p.z < spine_top(p.y) - 0.01
    hidden = bmesh.new()
    hidden.from_mesh(skin.data)
    mw = skin.matrix_world
    gone = [f for f in hidden.faces if all(inside(mw @ v.co) for v in f.verts)]
    bmesh.ops.delete(hidden, geom=gone, context='FACES')
    hidden.to_mesh(skin.data)
    hidden.free()
    bm.free()
    print("spine", len(me.vertices), "vertices; fuselage faces under it removed:", len(gone))
    for name, sink in (("Tail-antenna", 0.01), ("FwdFormationLight", 0.03)):
        o = body[name]
        lo, hi = bounds([o])
        dz = spine_top((lo.y + hi.y) / 2) - lo.z - sink
        o.data.transform(Matrix.Translation((0, 0, dz)))
        print("raised", name, round(dz, 3), "m")


def cockpit(prefix, shift):
    """FlightGear's cockpit tub, ACES II seat and pilot (decimated), shifted `shift` along y."""
    tub = kit.join(list(kit.import_ac(os.path.join(M, "Cockpit/Main/cockpit.ac"), prefix=prefix + "tub_").values()),
                   prefix + "tub")
    seat = kit.join(list(kit.import_ac(os.path.join(M, "Cockpit/chair/chair.ac"), prefix=prefix + "seat_").values()),
                    prefix + "seat")
    pilot = kit.join(list(kit.import_ac(os.path.join(M, "pilot_externalview.ac"), prefix=prefix + "pil_").values()),
                     prefix + "pilot")
    kit.decimate(tub, 0.5)
    kit.decimate(seat, 0.3)
    kit.decimate(pilot, 0.1)
    for o in (tub, seat, pilot):
        o.data.transform(Matrix.Translation((0, shift, 0)))
    return tub, kit.join([seat, pilot], prefix + "crew")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root_at, helpers = original()
    body = kit.import_ac(os.path.join(M, "f16.ac"))
    for n in DROP:
        if n in body:
            bpy.data.objects.remove(body.pop(n))
    # F-16.xml's GE_nozzle: its file's own offset taken out (translate -7.74, -1.4827, 1.25336), scaled 0.82 across,
    # then placed 4.61285 m aft, onto the fuselage's nozzle ring.
    noz_m = Matrix.Translation((0, -4.61285, 0)) @ Matrix.Diagonal((0.82, 1.0, 0.82, 1.0)) @ \
        Matrix.Translation(fg((-7.74, -1.4827, 1.25336)))
    noz = kit.import_ac(os.path.join(M, "nozzle-GE.ac"), matrix=noz_m, prefix="noz_")
    bpy.data.objects.remove(noz.pop("InNozzleROpen"))
    # The centreline pylon (loads_models.xml's Centerpylon: 0.02 m to the right), grey as the original's.
    body["CLStation"] = kit.join(list(kit.import_ac(os.path.join(M, "central-pylon.ac"), matrix=Matrix.Translation(
        fg((0, 0.02, 0))), prefix="cl_").values()), "CLStation")
    body["CLStation"].data.materials.clear()
    body["CLStation"].data.materials.append(kit.material("pylon_grey", (0.42, 0.44, 0.45), roughness=0.55))
    tub_f, crew_f = cockpit("front_", 0.0)
    two_seat(list(body.values()) + [tub_f])
    tub_r, crew_r = cockpit("rear_", -SEAT_GAP)
    everything = [o for o in kit.scene().objects if o.type == 'MESH']
    transform(everything, Matrix.Translation(SHIFT))
    fit_pylons(body, helpers, root_at)
    # The afterburner (EngineL, EngineL1 its radius above) at our nozzle's exit, in place of the original's (its
    # nozzle ends 0.26 m further aft): the flame starts on the petals. Visual only.
    lo, hi = bounds(list(noz.values()))
    exit_r = (hi.z - lo.z) / 2 * 0.85
    helpers["EngineL"] = Vector(((lo.x + hi.x) / 2, lo.y + 0.05, (lo.z + hi.z) / 2)) - root_at
    helpers["EngineL1"] = helpers["EngineL"] + Vector((0, 0, exit_r))
    print("nozzle exit", tuple(round(x, 3) for x in helpers["EngineL"]), "radius", round(exit_r, 3))
    target = helpers["height"].z + root_at.z
    compress_gear(body, target)
    doors_down, doors_up = gear_doors(body)
    dorsal_spine(body)
    if os.environ.get("F16D_DEBUG") == "1":
        for o in kit.scene().objects:
            if o.type == 'MESH':
                lo, hi = bounds([o])
                print("OBJ %-28s %s %s" % (o.name, tuple(round(x, 2) for x in lo), tuple(round(x, 2) for x in hi)))

    parts = {}
    for name, (objs, centre, axis) in PARTS.items():
        parts[name] = kit.join([body.pop(n) for n in objs], name)
    parts["LdgDr"] = doors_down
    parts["LdgDrUp"] = doors_up
    parts["pilot"] = crew_f
    parts["pilotB"] = crew_r
    for name, o in parts.items():
        o.name = o.data.name = name
    keep = set(parts.values())
    rest = [o for o in kit.scene().objects if o.type == 'MESH' and o not in keep]
    rig = kit.Rig(kit.join(rest, "f16"), parts, root_at)
    for name, (objs, centre, axis) in PARTS.items():
        c = fg(centre) + SHIFT
        if axis is None:  # the gear legs: the original's hinge direction through FlightGear's hinge point
            a = helpers[name + "2"] - helpers[name + "1"]
            if a.length < 1e-6:
                a = Vector((1, 0, 0))
        else:
            a = fg(axis)
        # Turn the same way as the original's part: its axis runs nearer -> farther from the origin.
        o1, o2 = helpers.get(name + "1"), helpers.get(name + "2")
        if o1 is not None and o2 is not None:
            ref = (o2 - o1) if o2.length >= o1.length else (o1 - o2)
            if a.dot(ref) < 0:
                a = -a
        rig.part(name, c, a)
    for name in ("LdgDr", "LdgDrUp", "pilot", "pilotB"):
        rig.place_centre(name)
    # Every other helper of the original, at the original's position.
    hinge_names = {n + s for n in PARTS for s in "12"}
    for name, p in helpers.items():
        if name in parts or name in hinge_names or name in PARTS:
            continue
        rig.empty(name, p + root_at)
    materials(rig)
    tmp = OUT + ".png.glb"
    rig.root.location = root_at
    for o in kit.scene().objects:
        o.select_set(o is rig.root or o.parent is rig.root)
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', export_yup=True, use_selection=True,
                              export_apply=True, export_image_format='AUTO')
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in kit.scene().objects if o.type == 'MESH')
    glb_ktx2.convert(tmp, OUT)
    os.remove(tmp)
    print("F16D", OUT, "triangles", tris, "bytes", os.path.getsize(OUT))


# --- materials -------------------------------------------------------------------------------------------------

def pixels(img):
    w, h = img.size
    return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)


def new_image(name, rgba, colorspace="sRGB"):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.colorspace_settings.name = colorspace
    img.pixels.foreach_set(np.ascontiguousarray(rgba, dtype=np.float32).ravel())
    img.pack()
    return img


def window(a, k, f):
    """f (np.maximum / np.minimum) over a k x k neighbourhood (edges clamped)."""
    r = k // 2
    p = np.pad(a, r, mode="edge")
    out = a.copy()
    for dy in range(k):
        for dx in range(k):
            out = f(out, p[dy:dy + a.shape[0], dx:dx + a.shape[1]])
    return out


def blur(a, k=3):
    r = k // 2
    p = np.pad(a, r, mode="edge")
    return sum(p[dy:dy + a.shape[0], dx:dx + a.shape[1]] for dy in range(k) for dx in range(k)) / (k * k)


def panel_maps(albedo):
    """From the livery: the thin dark lines (panel lines, rivets) as engraved grooves -> a tangent-space normal map
    and their roughness; camouflage edges (wide steps) are left alone by the morphological closing."""
    lum = albedo[..., :3] @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    closed = window(window(lum, 5, np.maximum), 5, np.minimum)
    groove = np.clip((closed - lum) * 5.0, 0, 1)
    height = 1.0 - groove
    gy, gx = np.gradient(height)
    k = 0.35
    n = np.dstack([-gx * k, -gy * k, np.ones_like(height)])  # rows bottom to top (Blender pixel order)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    normal = np.dstack([n * 0.5 + 0.5, np.ones_like(height)])
    return normal, groove


def bake_ao(objs, size):
    img = bpy.data.images.new("f16d_ao", size, size)
    img.colorspace_settings.name = "Non-Color"
    sc = kit.scene()
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 64
    sc.cycles.device = 'CPU'
    sc.render.bake.margin = 6
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = 0.5
    nodes = []
    dummy = bpy.data.images.new("bake_dummy", 8, 8)  # the other materials of these objects bake here
    for m in {m for o in objs for m in o.data.materials if m}:
        n = m.node_tree.nodes.new("ShaderNodeTexImage")
        n.image = img if m.name.startswith("ac_f16.png") else dummy
        m.node_tree.nodes.active = n
        nodes.append((m, n))
    kit.deselect()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.bake(type='AO')
    for m, n in nodes:
        m.node_tree.nodes.remove(n)
    return pixels(img)[..., 0]


def wing_roundels(albedo, skin):
    """The livery's roundel moved to the IAF positions (ROUNDELS): drawn as a circle on the wing, its texels found by
    casting onto the skin; the livery's own roundel above the left wing painted over with the colours round it."""
    from mathutils.bvhtree import BVHTree
    from mathutils.geometry import barycentric_transform
    h, w = albedo.shape[:2]
    tris, uvs = [], []
    for o in skin:
        me, mw = o.data, o.matrix_world
        uvl = me.uv_layers.active.data
        for p in me.polygons:
            m = me.materials[p.material_index]
            if not (m and m.name.startswith("ac_f16.png")):
                continue
            li = list(p.loop_indices)
            for k in range(1, len(li) - 1):
                t = (li[0], li[k], li[k + 1])
                tris.append([mw @ me.vertices[me.loops[j].vertex_index].co for j in t])
                uvs.append([Vector((uvl[j].uv.x, uvl[j].uv.y, 0)) for j in t])
    verts = [v for t in tris for v in t]
    bvh = BVHTree.FromPolygons(verts, [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))])

    def uv_at(x, y, top):
        # Down from above: the first hit is the wing's upper skin, the next its lower skin (above any pylon).
        loc, _, i, _ = bvh.ray_cast(Vector((x, y, 5.0)), Vector((0, 0, -1)))
        if not top:
            loc, _, i, _ = bvh.ray_cast(loc - Vector((0, 0, 1e-4)), Vector((0, 0, -1)))
        assert loc is not None and abs(loc.z) < 0.3, (x, y, top, loc)
        return np.array(barycentric_transform(loc, *tris[i], *uvs[i])[:2])

    src = albedo.copy()
    sx, sy, sr = ROUNDEL_ART
    sy = h - 1 - sy  # rows bottom to top
    # Paint over the livery's roundel: the texels in its disc relaxed to the average of their neighbours.
    r0 = int(sr + 6)
    win = albedo[int(sy) - r0:int(sy) + r0 + 1, int(sx) - r0:int(sx) + r0 + 1]
    yy, xx = np.mgrid[-r0:r0 + 1, -r0:r0 + 1]
    hole = np.hypot(xx + int(sx) - sx, yy + int(sy) - sy) <= sr + 2.5
    win[hole] = win[~hole].mean(axis=0)
    for _ in range(600):
        p = np.pad(win, ((1, 1), (1, 1), (0, 0)), mode="edge")
        win[hole] = ((p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4)[hole]
    for x, y, d, top in ROUNDELS:
        y += SHIFT.y
        c = uv_at(x, y, top)
        e = 0.02
        jac = np.column_stack([(uv_at(x + e, y, top) - uv_at(x - e, y, top)) / (2 * e),
                               (uv_at(x, y + e, top) - uv_at(x, y - e, top)) / (2 * e)])  # d(u, v) / d(x, y)
        inv = np.linalg.inv(jac)
        cc, cr = c[0] * w - 0.5, c[1] * h - 0.5
        half = int(d / 2 * np.abs(jac).max() * max(w, h)) + 3
        rows, cols = np.mgrid[int(cr) - half:int(cr) + half + 1, int(cc) - half:int(cc) + half + 1]
        duv = np.stack([(cols - cc) / w, (rows - cr) / h])
        mx, my = np.einsum("ij,jrc->irc", inv, duv)  # metres on the wing
        if x > 0:
            mx = -mx
        # The art lies on the left wing with u forward and v outboard (-x): the same axes, scaled to the diameter.
        k = sr / (d / 2)
        ox, oy = k * my, -k * mx
        a = np.clip(sr + 0.5 - np.hypot(ox, oy), 0, 1)[..., None]
        fx, fy = sx + ox, sy + oy
        x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
        tx, ty = (fx - x0)[..., None], (fy - y0)[..., None]
        art = (src[y0, x0] * (1 - tx) * (1 - ty) + src[y0, x0 + 1] * tx * (1 - ty) +
               src[y0 + 1, x0] * (1 - tx) * ty + src[y0 + 1, x0 + 1] * tx * ty)
        albedo[rows, cols] = albedo[rows, cols] * (1 - a) + art * a
        print("roundel", (round(x, 2), round(y, 2)), "top" if top else "under", "texel", (round(cc), h - 1 - round(cr)))
    return albedo


def materials(rig):
    objs = [o for o in kit.scene().objects if o.type == 'MESH']
    livery = bpy.data.images.load(os.path.join(M, LIVERY))
    skin = [o for o in objs if any(m and m.name.startswith("ac_f16.png") for m in o.data.materials)]
    albedo = wing_roundels(pixels(livery), skin)
    size = albedo.shape[0]
    ao = np.ones(albedo.shape[:2], dtype=np.float32) if FAST else bake_ao(skin, size)
    normal, groove = panel_maps(albedo)
    rough = np.clip(0.42 + 0.25 * groove + 0.08 * (1 - ao), 0, 1)
    metal = np.full_like(rough, 0.05)
    orm = np.dstack([0.35 + 0.65 * ao, rough, metal, np.ones_like(rough)])
    col_img = new_image("f16d_albedo", albedo)
    orm_img = new_image("f16d_orm", orm, "Non-Color")
    nor_img = new_image("f16d_normal", normal, "Non-Color")
    # The crew, seat and cockpit textures (up to 2048 x 4096) at most 512 px: a few hundred pixels on screen.
    for img in bpy.data.images:
        if img.size[0] > 512 and img.name not in (col_img.name, orm_img.name, nor_img.name, livery.name):
            k = 512 / max(img.size)
            img.scale(max(1, int(img.size[0] * k)), max(1, int(img.size[1] * k)))
    paint = {}
    glass = kit.material("canopy_glass", (0.42, 0.40, 0.30), metallic=0.0, roughness=0.05, alpha=0.28)
    glass.use_backface_culling = False
    for o in objs:
        for i, m in enumerate(o.data.materials):
            if m is None:
                continue
            if m.name.startswith("ac_plain") and o.name.startswith("Canopy"):
                o.data.materials[i] = glass
            elif m.name.startswith("ac_f16.png"):
                key = m.use_backface_culling
                if key not in paint:
                    paint[key] = pbr("f16d_paint" + ("" if key else "_2s"), col_img, orm_img, nor_img, key)
                o.data.materials[i] = paint[key]


def pbr(name, col, orm, nor, cull):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = cull
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = col
    nt.links.new(tc.outputs["Color"], b.inputs["Base Color"])
    to = nt.nodes.new("ShaderNodeTexImage")
    to.image = orm
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
    # glTF occlusion: the exporter takes it from a "glTF Material Output" group's Occlusion socket.
    grp = bpy.data.node_groups.get("glTF Material Output")
    if grp is None:
        grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    g = nt.nodes.new("ShaderNodeGroup")
    g.node_tree = grp
    nt.links.new(sep.outputs["Red"], g.inputs["Occlusion"])
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = nor
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


main()
