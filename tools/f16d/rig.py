# Build the detailed F-16D (Preferences -> Extras -> Models: Detailed; docs/aircraft-models.md) from the FlightGear
# F-16 (github.com/NikolaiVChr/f16, GPL-2.0-or-later; tools/f16d/SOURCES.md) with tools/plane/kit.py:
#   - FlightGear's single-seat f16.ac made two-seat: the canopy and the spine behind it stretched aft, a second
#     cockpit, seat and pilot;
#   - placed on the original model's frame: the wing on the original's wing, the pylons moved onto the original's
#     Station helpers, the oleos compressed so the wheels touch at the original's `height` helper;
#   - the moving parts named and hinged as the original's (`<part>1/2` helpers on FlightGear's own hinge lines,
#     taken from its F-16.xml animations), the helpers the game reads copied from the original model;
#   - the fin and rudder reaching FIN_DROP lower, onto the IAF dorsal spine (the avionics hump of the Block 30 / 40
#     "Brakeet"), lofted over the slim US spine level from the canopy's rear end to a box under the fin that ends
#     over the nozzle, with its three vents;
#   - closed gear doors (LdgDrUp, shown only with the gear up), the GE nozzle, an IAF desert livery (FlightGear's,
#     its wing roundels moved to the IAF positions) with our PBR maps (baked occlusion, panel-line normal map, roughness / metallic);
#   - written as one glb with KTX2 textures (tools/plane/glb_ktx2.py, needs `basisu`).
#
#   blender -b --python tools/f16d/rig.py -- <FlightGear f16 checkout> <assets/converted/planes/f16/f16_h.gltf> \
#       <out.glb> [sufa]
#
# `sufa` builds the F-16I Sufa (f16i.glb, docs/f16i.md §8): the same jet with FlightGear's conformal fuel tanks and
# P&W F100 nozzle, our nose fairings (nose_fairings), our three-tone camouflage in the Sufa's FS colours, 107
# Squadron's orange fin crescent, a badge and tail number 457 (sufa_livery). F16D_KEEP_PNG=1 keeps <out>.png.glb,
# the glb before the KTX2 pass (Blender reads it: tools/f16i/arm_front.py).
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

ARGS = sys.argv[sys.argv.index("--") + 1:]
FG, ORIG, OUT = ARGS[:3]
SUFA = ARGS[3:4] == ["sufa"]
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
# The nose oleo's static compression (m): FlightGear's JSBSim gear (Systems/jsb-ground-reactions.xml), its nose
# spring 17,250 lb/ft under the nose's share of a 24,000 lb jet (9.6 %: the CG 0.22 m aft of the origin, the wheels
# 3.02 m ahead and 0.56 m aft of it). The main oleos go to the original's `height` (within 2 cm of JSBSim's static).
NOSE_STATIC = 0.041
# FlightGear's fin and rudder end FIN_DROP m too high: their root (FIN_ROOT) is level with the canopy's top, where on
# IAF F-16s (F-16D 027 side on, parked; F-16C 557) the canopy stands 0.25 m above the fin's root and the dorsal spine
# (SOURCES.md). Their tip (FIN_TIP) is right: 4.90 m above the static ground, the F-16's published 4.88 m. So the
# fin's parts are stretched down to the new root, the tip kept (fin_z), and its root fairing (USAF_Tailroot, from
# the fuselage at TAILROOT_Z0 up to the fin) squashed to meet them.
FIN_DROP, TAILROOT_Z0, FIN_ROOT, FIN_TIP = 0.27, 0.49, 1.152, 3.191
FIN_K = (FIN_TIP - FIN_ROOT + FIN_DROP) / (FIN_TIP - FIN_ROOT)


def fin_z(z):
    """A fin point's height after the stretch (FlightGear's frame and ours: z up)."""
    return FIN_TIP - (FIN_TIP - z) * FIN_K


# The rudder's hinge (F-16.xml: 0.547371, 0, 0.83689), its upright part stretched with the fin.
RUDDER_AXIS = (0.547371 / math.hypot(0.547371, 0.83689 * FIN_K), 0,
               0.83689 * FIN_K / math.hypot(0.547371, 0.83689 * FIN_K))
FIN = ["Tail", "Rudder.001", "Rudder.002", "Rudder.003", "Rudder.004", "Rudder.005", "Rudder.006",
       "FlashLightProtector", "AntiCollisionStrobe", "AftPosLight2"]

DROP = {"ExternalFlame", "InternalFlame", "Chute", "RNLAF_Tailroot", "Link16Antennas", "Fan", "FanSpinning",
        "FanR.001", "FanRHighSpeed", "FanRHighSpeed.001", "CanopyBackInside", "CanopyForwardInside",
        "FuselageLogoLeft", "FuselageLogoRight", "LogoPilotRight", "Rect", "VstabBandLeftAft", "VstabBandLeftFront",
        "VstabBandRightAft", "VstabBandRightFront", "VstabLogoLeftBottom", "VstabLogoLeftTop", "VstabLogoRightBottom",
        "VstabLogoRightTop", "WinglogoLeftTop", "WinglogoRightBottom", "WinglogoRightTop", "GreenPosLight2",
        "RedPosLight2", "AftPosLight1"}  # the last: inside the IAF dorsal spine
# The game's parts (docs/part-animation.md) from FlightGear's objects, with FlightGear's hinge (F-16.xml: centre and
# axis, FlightGear frame x aft, y right, z up). Axis None: a part that never turns (its own centre is the origin).
PARTS = {
    "AilerL": (["LeftUpperFlap", "LeftLowerFlap"], (1.54, -2.35, 0.12), (0.150157, -0.987872, -0.039515)),
    "AilerR": (["RightUpperFlap", "RightLowerFlap"], (1.54, 2.35, 0.12), (0.150157, 0.987872, -0.039515)),
    "ElevaL": (["LeftUpperHorizonTail", "LeftLowerHorizonTail"], (4.36, -1.965, -0.1), (0, -0.981645, -0.19072)),
    "ElevaR": (["RightUpperHorizonTail", "RightLowerHorizonTail"], (4.36, 1.965, -0.1), (0, 0.981645, -0.19072)),
    "RuddeL": (["Rudder.001", "Rudder.002", "Rudder.003", "Rudder.004", "Rudder.005"], (4.915, 0, fin_z(2.095)),
               RUDDER_AXIS),
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


def lower_fin(body):
    for o in (body[n] for n in FIN):
        for v in o.data.vertices:
            v.co.z = fin_z(v.co.z)
        o.data.update()
    tr = body["USAF_Tailroot"]
    top = max(v.co.z for v in tr.data.vertices)
    k = (top - FIN_DROP - TAILROOT_Z0) / (top - TAILROOT_Z0)
    for v in tr.data.vertices:
        if v.co.z > TAILROOT_Z0:
            v.co.z = TAILROOT_Z0 + (v.co.z - TAILROOT_Z0) * k
    tr.data.update()


def rotate_about(objs, centre, axis, angle):
    m = Matrix.Translation(centre) @ Matrix.Rotation(angle, 4, Vector(axis).normalized()) @ Matrix.Translation(-centre)
    transform(objs, m)


def compress_gear(body, target_z):
    """Oleos compressed as loaded on the ground: the main wheels' lowest points at target_z, the nose oleo by its
    static NOSE_STATIC. Returns where the main wheels and the nose wheel touch (world, on the centre line): the
    game's Sit1 / Sit2 helpers (the nose up on the ground, aircraft_model.gd)."""
    nose = [body["FrontTire"], body["FrontLowerStrut"]]
    transform(nose, Matrix.Translation((0, 0, NOSE_STATIC)))
    lo, hi = bounds([body["FrontTire"]])
    nose_touch = Vector((0, (lo.y + hi.y) / 2, lo.z))
    print("gear nose compression", NOSE_STATIC, "m; nose wheel", round(target_z - lo.z, 3), "m under the mains'")
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
    lo, hi = bounds([body["LeftMainTire"], body["RightMainTire"]])
    return Vector((0, (lo.y + hi.y) / 2, target_z)), nose_touch


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


# The IAF dorsal spine (our frame, after SHIFT; y forward, z up). Its front (SP_Y0) is the glass's rear edge, an arch
# 0.34 m wide whose top is SP_Z0, so the canopy runs on into it; it widens to 0.34 m (half-width) by y = -0.5, eases
# down to SP_Z_TOP by SP_Y_LEVEL and runs level to its end over the nozzle (SP_Y_END), the lowered fin standing on
# it. Half-widths (y, w) between which it is interpolated: the glass's rear arch, 0.34 m to the wing's trailing
# edge, the fin root's width under the fin; its front sections are round as the arch (SP_ROUND m), its shoulders
# 0.12 m from there. Aft of SP_Y_FLOOR the fuselage falls away to the nozzle and the box gets a flat floor at SP_FLOOR; its last
# SP_END_R m round off into a cap. Three vents on each side (SP_VENTS: centre y, width; SP_VENT_Z below the top,
# SP_VENT_H tall) ahead of the fin. Photographs (SOURCES.md): IAF F-16D 027 side on (Oren Rozen): the canopy stands
# 0.25 m above the spine, whose top is level from the canopy's rear frame to the fin, the three vents 0.6 m ahead of
# the fin, the tail box as tall as the spine with a round end (F-16C 333's tail); IAF F-16I from above: the canopy
# ends square at nearly its full width and the spine goes on at that width; F-16D 601, 022 / 046 / 050 / 063.
SP_Y0, SP_Z0, SP_Y_LEVEL, SP_ROUND = 0.47, 0.945, -0.6, 0.7
SP_Z_TOP = 1.148 - FIN_DROP
SP_Y_FIN = -3.86
SP_Y_END, SP_Y_FLOOR, SP_FLOOR, SP_END_R = -6.42, -5.3, 0.62, 0.22
SP_WIDTH = [(SP_Y0, 0.19), (-0.5, 0.34), (-2.4, 0.34), (-3.86, 0.2), (-6.3, 0.2), (SP_Y_END, 0.17)]
SP_FILLET = 0.05  # the concave flare where the sides meet the fuselage
SP_VENTS, SP_VENT_Z, SP_VENT_H = [(-2.80, 0.12), (-3.03, 0.12), (-3.26, 0.12)], 0.18, 0.14
# The F-16I's spine (photos of 890 and 827, SOURCES.md) has the F-16D's outline but two taller grilled vents 0.4 to
# 0.55 m ahead of the fin's root (SP_Y_FIN), and on each side of the tail box under the fin a round blister and an
# oblong fairing (SUFA_TAIL_FAIRINGS: y, below the top, size across / along / up, in m).
if SUFA:
    SP_VENTS, SP_VENT_Z, SP_VENT_H = [(-3.30, 0.12), (-3.46, 0.12)], 0.25, 0.20
SUFA_TAIL_FAIRINGS = [(-4.48, 0.19, (0.06, 0.20, 0.22)), (-4.18, 0.33, (0.05, 0.24, 0.15))]
# The spine's own UV island (its paint: a free, plain grey rectangle of the livery, pixels from the top left; FlightGear
# maps the inner canopy frame below it, from row 1901), at SP_ISLAND_K px per m. It is filled from the livery of the
# fuselage round it, unfolded at its true size (spine_island): the section's arc is laid on the fuselage top from foot
# to foot with a mirror fold on each side, so the panel lines keep their size and the paint runs on at the foot.
SP_ISLAND, SP_ISLAND_K = (1350, 1555, 1910, 1890), 78.0
SPINE_FILL = []  # per ring: (y, island rows [px from the top], livery uvs [n, 2]), for spine_island


def interp(table, y):
    for (y0, v0), (y1, v1) in zip(table, table[1:]):
        if y1 <= y <= y0:
            return v0 + (v1 - v0) * smooth01((y0 - y) / (y0 - y1))
    return table[0][1] if y > table[0][0] else table[-1][1]


def spine_top(y):
    return SP_Z_TOP + (SP_Z0 - SP_Z_TOP) * smooth01((y - SP_Y_LEVEL) / (SP_Y0 - SP_Y_LEVEL))


def dorsal_spine(body):
    """The IAF F-16D's dorsal spine: a loft of rounded-box sections over FlightGear's fuselage (`RadarDomeTop`),
    flared into it at the sides; its livery UVs are its own island (SP_ISLAND), painted by spine_island from the
    fuselage's livery round it, unfolded at true size (the camouflage runs on unbroken at its foot). The fuselage
    faces it covers are removed, the blade antenna and the formation light are raised onto it."""
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
    ys = [SP_Y0 - i * 0.1 for i in range(int((SP_Y0 - SP_Y_END - SP_END_R) / 0.1) + 1)]
    ys += [SP_Y_END + SP_END_R * math.cos(math.pi / 2 * k / 6) for k in range(7)]  # the round end, finer
    for y in ys:
        w, top = interp(SP_WIDTH, y), spine_top(y)
        e = (SP_Y_END + SP_END_R - y) / SP_END_R
        if e > 0:  # the round end: an ellipse quarter in plan and in profile, down to a small last ring
            r = max(0.25, math.sqrt(max(0.0, 1 - e * e)))
            w *= r
            top = SP_FLOOR + (top - SP_FLOOR) * r
        side = []  # the right half from the top centre round to the foot (x >= 0)
        foot_s = surface(w + SP_FILLET, y)
        foot = max(foot_s[0] if foot_s else SP_FLOOR, SP_FLOOR if y < SP_Y_FLOOR else -9.0)
        flare = SP_FILLET * smooth01((foot - SP_FLOOR) / 0.05) if y < SP_Y_FLOOR else SP_FILLET
        rv = min(0.12 + 0.3 * smooth01((y - SP_Y0 + SP_ROUND) / SP_ROUND), max(0.02, (top - foot) * 0.9))
        for k in range(n_top + 1):  # super-ellipse quarter: flat top, rounded shoulder
            t = math.pi / 2 * (1 - k / n_top)
            side.append((w * math.cos(t) ** (2 / 3.5), top - rv + rv * math.sin(t) ** (2 / 3.5)))
        side.append((w, foot + flare))
        for k in range(1, 5):  # concave flare onto the fuselage, its lip 2 cm under the skin
            t = math.pi / 2 * k / 4
            side.append((w + flare * (1 - math.cos(t)), foot + flare * (1 - math.sin(t)) - 0.02 * k / 4))
        pts = [(-x, z) for x, z in reversed(side[1:])] + side
        # Livery: the island's UVs (along the jet, along the arc); the livery to paint them with, from SPINE_FILL.
        arc = [0.0]
        for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
            arc.append(arc[-1] + math.hypot(x1 - x0, z1 - z0))
        xf, total = pts[-1][0], arc[-1]
        fold = max(0.0, (total - 2 * xf) / 4)  # the arc unfolded 1:1: out `fold` from each foot, back over the top
        row, src = [], []
        col = SP_ISLAND[0] + (SP_Y0 - y) * SP_ISLAND_K
        mid = (SP_ISLAND[1] + SP_ISLAND[3]) / 2
        rows_px = [mid + (s - total / 2) * SP_ISLAND_K for s in arc]
        for s, r in zip(arc, rows_px):
            if s < fold:  # out from the left foot
                u = -xf - s
            elif s > total - fold:  # back in to the right foot
                u = xf + fold - (s - total + fold)
            else:  # over the top
                u = -xf - fold + (s - fold)
            # The fuselage ends at -5.78 and narrows before: the box's tail takes its last full row.
            su = next(filter(None, (surface(u * k, yy) for yy in (y, min(y + 0.1, SP_Y0), -5.2) for k in (1, 0.8, 0.6, 0.4))), None)
            src.append(tuple(su[1]))
            row.append(Vector(((col + 0.5) / 2048, 1 - (r + 0.5) / 2048)))
            if mat_idx is None and su:
                mat_idx = su[2]
        SPINE_FILL.append((y, np.array(rows_px), np.array(src)))
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
    for r, rev in ((vs[-1], False), (vs[0], True)):  # end caps (the front one dark, as the canopy's rear frame)
        f = out.faces.new(list(reversed(r)) if rev else r)
        f.material_index = 1
    bmesh.ops.recalc_face_normals(out, faces=out.faces[:])
    for yc, half in ((yc, w / 2) for yc, w in SP_VENTS):  # the vents: dark panels just off each side
        z0 = spine_top(yc) - SP_VENT_Z - SP_VENT_H / 2
        for sx in (1, -1):
            c = [(yc - half, z0), (yc + half, z0), (yc + half, z0 + SP_VENT_H), (yc - half, z0 + SP_VENT_H)]
            q = [out.verts.new((sx * (interp(SP_WIDTH, y) + 0.003), y, z)) for y, z in c]
            f = out.faces.new(q if sx > 0 else q[::-1])  # facing out
            f.material_index = 1
            for lp in f.loops:
                lp[uv_out].uv = uvs[0][0]
    x0, y0, x1, y1 = SP_ISLAND  # no face of the livery maps into the spine's island
    for o in body.values():
        if o.type == 'MESH' and o.data.uv_layers.active:
            painted = {i for i, m in enumerate(o.data.materials) if m and m.name.startswith("ac_f16.png")}
            uv = o.data.uv_layers.active.data
            assert not any(x0 - 4 <= uv[j].uv.x * 2048 <= x1 and y0 <= (1 - uv[j].uv.y) * 2048 <= y1 for p in
                           o.data.polygons if p.material_index in painted for j in p.loop_indices), o.name
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
    if SUFA:
        noz = pw_nozzle()
        # loads_models-inner.xml's CFTTanks, at FlightGear's origin; stretched for two seats with the skin under it.
        body["CFT"] = kit.join(list(kit.import_ac(os.path.join(M, "Armament/External-stores/Fueltanks/CFT.ac"),
                                                  prefix="cft_").values()), "CFT")
    else:
        noz = kit.import_ac(os.path.join(M, "nozzle-GE.ac"), matrix=noz_m, prefix="noz_")
        bpy.data.objects.remove(noz.pop("InNozzleROpen"))
    # The centreline pylon (loads_models.xml's Centerpylon: 0.02 m to the right), grey as the original's.
    body["CLStation"] = kit.join(list(kit.import_ac(os.path.join(M, "central-pylon.ac"), matrix=Matrix.Translation(
        fg((0, 0.02, 0))), prefix="cl_").values()), "CLStation")
    body["CLStation"].data.materials.clear()
    body["CLStation"].data.materials.append(kit.material("pylon_grey", (0.42, 0.44, 0.45), roughness=0.55))
    lower_fin(body)
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
    sit = compress_gear(body, target)
    doors_down, doors_up = gear_doors(body)
    dorsal_spine(body)
    if SUFA:
        body["SufaAntennas"] = nose_fairings(body)
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
    rig.empty("Sit1", sit[0])
    rig.empty("Sit2", sit[1])
    materials(rig)
    tmp = OUT + ".png.glb"
    rig.root.location = root_at
    for o in kit.scene().objects:
        o.select_set(o is rig.root or o.parent is rig.root)
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', export_yup=True, use_selection=True,
                              export_apply=True, export_image_format='AUTO')
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in kit.scene().objects if o.type == 'MESH')
    glb_ktx2.convert(tmp, OUT)
    if os.environ.get("F16D_KEEP_PNG") != "1":
        os.remove(tmp)
    print("F16D", OUT, "triangles", tris, "bytes", os.path.getsize(OUT))


# --- F-16I Sufa ------------------------------------------------------------------------------------------------

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
        sec = kit.import_ac(os.path.join(M, "nozzle-section.ac"), prefix="noz%d_" % k)
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

# The Sufa's colours (docs/f16i.md §8), sRGB 0..1, approximate sRGB of the FS 595 chips set against photos of
# F-16Is in sunlight (SOURCES.md): FS 30219 tan (the reddish brown), FS 33531 sand, FS 34424 green over FS 36375
# light ghost grey; radome FS 36270.
FS = {"30219": (0.60, 0.47, 0.36), "33531": (0.74, 0.67, 0.52), "34424": (0.53, 0.60, 0.49),
      "36375": (0.745, 0.761, 0.773), "36270": (0.518, 0.541, 0.557)}
CAMO = ("30219", "33531", "34424")
# The livery's colours (measured from 90-0874.png): its brown, sand and pale green camouflage and its light grey
# underside (bluer than the green: each texel takes the nearest).
FG_PAINT = [((0.624, 0.553, 0.431), "30219"), ((0.867, 0.820, 0.706), "33531"), ((0.792, 0.827, 0.776), "34424"),
            ((0.792, 0.824, 0.831), "36375")]
FG_RADOME = (0.337, 0.337, 0.337)
# Our camouflage: three noise fields over the airframe (world frame, m), each texel the colour of the strongest, so
# the three colours come in about equal measure as irregular blotches of about BLOTCH_M that run on across parts
# and UV seams. Seed: the pattern is the same on every build.
BLOTCH_M, CAMO_SEED = 1.5, 16
# The CFTs' own UV island in the livery (u0, v0, u1, v1; unpainted in FlightGear's livery): painted with the pattern.
CFT_UV = (0.19, 0.205, 0.535, 0.40)
# Places in the 2048 px livery (pixels from the top left). The radome's top and bottom halves (x0, y0, x1, y1).
RADOME = [(1340, 420, 1600, 560), (390, 990, 670, 1130)]
# On the fin, 101 Squadron's markings to paint over: its badge and the red disc above it (circles x, y, r) and the
# red and white stripes (boxes), on each side; and the tail number "547" (boxes; the right side's is upside down).
BADGES = [(1800, 190, 70), (1820, 115, 26), (1800, 570, 70), (1820, 655, 26)]
STRIPES = [(1850, 30, 1960, 190), (1850, 585, 1960, 745)]
DIGITS = [((1640, 245, 1757, 312), False), ((1640, 468, 1759, 537), True)]
OLD_NUMBER, TAIL_NUMBER = "547", "457"  # the new number from the old one's glyphs
# 107 Squadron ("Knights of the Orange Tail", Hatzerim; docs/f16i.md §8), as on its F-16I 827: an orange crescent
# down the fin's leading edge whose lower end runs aft as a thin stripe through the tail number, and a small round
# badge high on the fin inside the crescent. Ours, in the fin's plane (a: m aft of the leading edge, h: m above
# the leading edge's root): the crescent lies between two circles round (CRES_A, CRES_H x fin height); the inner one
# just touches the stripe, the outer one is CRES_W bigger. The number: NUM_H x fin height up, digits NUM_M tall,
# centred NUM_A of the chord aft. The badge (ours; the squadron's emblem is not drawn): BADGE_R m round at BADGE_H
# x fin height, BADGE_A m aft of the crescent.
ORANGE = (0.82, 0.52, 0.20)
CRES_H, CRES_TOP, CRES_W, STRIPE_M = 0.97, 0.18, 0.36, 0.05
NUM_H, NUM_M, NUM_A = 0.27, 0.30, 0.56
BADGE_H, BADGE_R, BADGE_A = 0.66, 0.15, 0.32
BADGE_RING, BADGE_FILL, BADGE_CORE = (0.20, 0.16, 0.10), (0.93, 0.70, 0.18), (0.86, 0.84, 0.76)


def recolour(albedo, pairs, reach, where):
    """The texels in `where` near a source colour (within `reach`) shifted by (target - source), blended between the
    nearest sources, so the shading and panel lines on the paint keep their contrast."""
    px = albedo[where][:, :3]
    d = np.stack([np.linalg.norm(px - np.array(src), axis=1) for src, _ in pairs])
    k = np.exp(-(d / 0.025) ** 2)
    steps = np.array([np.array(dst) - np.array(src) for src, dst in pairs])
    shift = (k.T @ steps) / np.maximum(k.sum(axis=0), 1e-6)[:, None]
    albedo[where, :3] = np.clip(px + shift * np.clip((reach - d.min(axis=0)) / (reach * 0.4), 0, 1)[:, None], 0, 1)


def texels(albedo, tris, uvs):
    """Every texel of the triangles (world, UVs) -> its world position and the z of its face's normal ([h, w, 3] and
    [h, w], NaN where no triangle is). Where triangles share texels, the one whose texel size is nearest the
    livery's usual wins (not a sliver that FlightGear mapped over a large part of the texture)."""
    h, w = albedo.shape[:2]
    pos = np.full((h, w, 3), np.nan, dtype=np.float32)
    nz = np.full((h, w), np.nan, dtype=np.float32)

    def density(k):
        t, uv = tris[k], uvs[k]
        a = (uv[1] - uv[0]).cross(uv[2] - uv[0]).length
        return np.log(max((t[1] - t[0]).cross(t[2] - t[0]).length, 1e-12) / max(a, 1e-12))

    dens = np.array([density(k) for k in range(len(tris))])
    usual = np.median(dens)
    for k in np.argsort(-np.abs(dens - usual)):
        t, uv = tris[k], uvs[k]
        n = (t[1] - t[0]).cross(t[2] - t[0])
        p = np.array([[u.x * w - 0.5, u.y * h - 0.5] for u in uv])
        lo = np.maximum(np.floor(p.min(axis=0)).astype(int), 0)
        hi = np.minimum(np.ceil(p.max(axis=0)).astype(int) + 1, (w, h))
        m = np.array([[p[0, 0] - p[2, 0], p[1, 0] - p[2, 0]], [p[0, 1] - p[2, 1], p[1, 1] - p[2, 1]]])
        if (hi <= lo).any() or abs(np.linalg.det(m)) < 1e-12 or n.length < 1e-12:
            continue
        cols, rows = np.meshgrid(np.arange(lo[0], hi[0]), np.arange(lo[1], hi[1]))
        l01 = np.einsum("ij,jrc->irc", np.linalg.inv(m), np.stack([cols - p[2, 0], rows - p[2, 1]]))
        bary = np.stack([l01[0], l01[1], 1 - l01[0] - l01[1]])
        inside = (bary >= -0.02).all(axis=0)
        pos[rows[inside], cols[inside]] = np.einsum("krc,kj->rcj", bary, np.array([tuple(v) for v in t]))[inside]
        nz[rows[inside], cols[inside]] = n.z / n.length
    return pos, nz


def value_noise(p, seed):
    """Smooth value noise in 3D (lattice spacing 1) at the points p [n, 3]."""
    table = np.random.default_rng(seed).random(1 << 16).astype(np.float32)
    i = np.floor(p).astype(np.int64)
    f = p - i
    u = f * f * (3 - 2 * f)
    out = np.zeros(len(p), dtype=np.float32)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                hsh = ((i[:, 0] + dx) * 73856093) ^ ((i[:, 1] + dy) * 19349663) ^ ((i[:, 2] + dz) * 83492791)
                wgt = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1])
                wgt = wgt * (u[:, 2] if dz else 1 - u[:, 2])
                out += table[hsh & 0xFFFF] * wgt
    return out


def camo_weights(p):
    """Our three-tone pattern at the world points p [n, 3]: the weight of each colour of CAMO [n, 3], soft over
    about 2 cm at a blotch's edge. Fields stretched 1.3 x along the jet, their coordinates warped for ragged
    edges."""
    q = p / BLOTCH_M * np.array([1.0, 1 / 1.3, 1.0], dtype=np.float32)
    warp = np.stack([value_noise(q * 2.1 + 7.3 * k, CAMO_SEED + 10 + k) for k in range(3)], axis=1) - 0.5
    q = q + 0.35 * warp
    f = np.stack([value_noise(q, CAMO_SEED + k) + 0.45 * value_noise(q * 2.3 + 3.1, CAMO_SEED + 5 + k)
                  for k in range(3)], axis=1)
    for _ in range(40):  # about a third each over the airframe's painted surface
        share = np.bincount(f.argmax(axis=1), minlength=3) / len(f)
        f -= 0.1 * (share - 1 / 3)
    e = np.exp((f - f.max(axis=1, keepdims=True)) * 1.4 * BLOTCH_M / 0.02)
    return e / e.sum(axis=1, keepdims=True)


def is_fin(t):
    """A triangle of the fin or rudder: facing sideways, on the centre line, above the spine aft of the blade
    antenna."""
    n, c = (t[1] - t[0]).cross(t[2] - t[0]), (t[0] + t[1] + t[2]) / 3
    return n.length > 1e-12 and abs(n.x) > 0.8 * n.length and c.z > 1.2 - FIN_DROP and abs(c.x) < 0.1 and c.y < -3.7


# The Barak's camouflage (sRGB 0..1), set against photographs of IAF F-16Ds (SOURCES.md): 027 in sun, 601 under
# cloud. Each tone over the sand in the same light: tan (0.87, 0.70, 0.50) and (0.76, 0.70, 0.66), green (0.93,
# 1.00, 0.98) and (0.87, 0.94, 0.92); the sand itself (1, 0.905, 0.795) in both. The sand is as bright as
# FlightGear's; the tan and green are set so that on screen (the game's tone curve darkens the middle tones: an
# albedo 0.82 of the sand's showed as 0.61) they stand to the sand as in the photos' mean: tan (0.82, 0.70, 0.58),
# green (0.90, 0.97, 0.95). The faded, warm FS 30219 tan, 33531 sand and 34424 grey-green of the jets in service.
BARAK = {"30219": (0.78, 0.64, 0.45), "33531": (0.85, 0.77, 0.675), "34424": (0.80, 0.76, 0.65),
         "36375": FS["36375"]}
BARAK_Z_CAMO = 0.15  # m (our frame): the strakes' height, where the camouflage meets the grey on the sides


def barak_livery(albedo, skin):
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
    return albedo


def sufa_livery(albedo, skin):
    """FlightGear's IAF livery made the Sufa's: the underside's grey and the radome recoloured to the FS colours;
    the upper surfaces (the CFTs too) repainted with our camouflage over the livery's panel lines; on the fin,
    101 Squadron's markings painted over, 107 Squadron's orange crescent, a badge and the tail number."""
    h, w = albedo.shape[:2]
    src = albedo.copy()
    _, tris, uvs = skin_bvh(skin)
    pos, nz = texels(albedo, tris, uvs)
    # The fin's texels are the fin's (other faces share some of them).
    fin = [i for i, t in enumerate(tris) if is_fin(t)]
    fpos, _ = texels(albedo, [tris[i] for i in fin], [uvs[i] for i in fin])
    on_fin = ~np.isnan(fpos[..., 0])
    pos[on_fin], nz[on_fin] = fpos[on_fin], 0.0
    recolour(albedo, [(c, FS[f]) for c, f in FG_PAINT], 0.16, nz > -0.35)
    recolour(albedo, [(c, FS[f]) for c, f in FG_PAINT[3:]], 0.16, nz <= -0.35)  # underneath: grey only
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
    for x0, y0, x1, y1 in STRIPES + [b for b, _ in DIGITS]:
        hole |= (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
    want = camo_src | cft | hole
    paint = covered & want & (nz > -0.35)
    albedo[covered & cft & (nz <= -0.35), :3] = FS["36375"]
    closed = window(window(lum, 5, np.maximum), 5, np.minimum)
    detail = np.where(cft | hole, 1.0, np.clip(lum / np.maximum(closed, 1e-3), 0.55, 1.0))
    wts = camo_weights(pos[paint])
    albedo[paint, :3] = (wts @ np.array([FS[c] for c in CAMO], dtype=np.float32)) * detail[paint][:, None]
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
    # The fin, in its own plane (see CRES_H): the leading edge runs straight from the root's foremost vertex to the
    # tip's; the trailing edge (the rudder's) likewise from the aftmost ones.
    fv = np.array([tuple(v) for i in fin for v in tris[i]])
    z_lo, z_hi = fv[:, 2].min(), fv[:, 2].max()
    le = [fv[np.abs(fv[:, 2] - z) < 0.02][:, 1:].max(axis=0) for z in (z_lo, z_hi)]
    te = [fv[np.abs(fv[:, 2] - z) < 0.02][:, 1].min() for z in (z_lo, z_hi)]
    tall = le[1][1] - le[0][1]

    def le_y(z):
        return np.interp(z, [le[0][1], le[1][1]], [le[0][0], le[1][0]])

    def chord(z):
        return le_y(z) - np.interp(z, [z_lo, z_hi], te)

    with np.errstate(invalid="ignore"):
        a = le_y(fpos[..., 2]) - fpos[..., 1]
        hh = fpos[..., 2] - le[0][1]
        num_h = NUM_H * tall
        c_h = CRES_H * tall
        r_in = c_h - num_h - STRIPE_M
        c_a = CRES_TOP + np.sqrt(r_in ** 2 - (tall - c_h) ** 2)
        r = np.hypot(a - c_a, hh - c_h)
        crescent = (r > r_in) & (r < r_in + CRES_W) & (hh > num_h - STRIPE_M) & (a < c_a)
        stripe = (np.abs(hh - num_h) < STRIPE_M) & (a > 0)
        orange = on_fin & (crescent | stripe)
        albedo[orange, :3] = albedo[orange, :3] * 0.15 + np.array(ORANGE) * 0.85
        # The badge, inside the crescent.
        b_h = BADGE_H * tall
        b_a = c_a - np.sqrt(r_in ** 2 - (b_h - c_h) ** 2) + BADGE_A
        rb = np.hypot(a - b_a, hh - b_h)
        for rad, col in ((BADGE_R, BADGE_RING), (BADGE_R * 0.88, BADGE_FILL), (BADGE_R * 0.45, BADGE_CORE)):
            k = on_fin & (rb < rad + 0.004)
            edge = np.clip((rad + 0.004 - rb[k]) / 0.008, 0, 1)[:, None]
            albedo[k, :3] = albedo[k, :3] * (1 - edge) + np.array(col) * edge
    # The tail number: the livery's own glyphs, rearranged and scaled onto the fin at NUM_H. On each side, an affine
    # fit from the fin's plane (y, z) to the old number's texels gives where to read each glyph.
    for (x0, y0, x1, y1), flip in DIGITS:
        box = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1) & on_fin
        rows, cols = np.nonzero(box & (lum < 0.3))
        side = np.sign(np.nanmean(fpos[rows, cols, 0]))
        fy, fz = fpos[rows, cols, 1], fpos[rows, cols, 2]
        fit = np.linalg.lstsq(np.column_stack([fy, fz, np.ones_like(fy)]), np.column_stack([cols, rows]), rcond=None)[0]
        # The glyphs in reading order: front to back on the left side, back to front on the right.
        order = np.argsort(cols)
        groups = np.split(order, np.nonzero(np.diff(cols[order]) > 2)[0] + 1)
        assert len(groups) == len(OLD_NUMBER), ("tail number glyphs", len(groups))
        glyphs = sorted(((float(fy[g].min()), float(fy[g].max())) for g in groups), reverse=side < 0)
        g_z0, g_z1 = float(fz.min()), float(fz.max())
        k = NUM_M / (g_z1 - g_z0)  # new size / old size
        old_c = [(a0 + a1) / 2 for a0, a1 in glyphs]
        mid = (old_c[0] + old_c[-1]) / 2
        n_z = le[0][1] + num_h
        n_y = le_y(n_z) - NUM_A * chord(n_z)
        mine = on_fin & (np.sign(fpos[..., 0]) == side)
        ty, tz = fpos[mine, 1], fpos[mine, 2]
        ink = np.zeros(len(ty), dtype=np.float32)
        colour = np.zeros((len(ty), 3), dtype=np.float32)
        for slot, ch in enumerate(TAIL_NUMBER):
            ga0, ga1 = glyphs[OLD_NUMBER.index(ch)]
            gc = (ga0 + ga1) / 2
            sy = gc + (ty - (n_y + (old_c[slot] - mid) * k)) / k  # the source point in the old number
            sz = (g_z0 + g_z1) / 2 + (tz - n_z) / k
            ok = (sy > ga0 - 0.01) & (sy < ga1 + 0.01) & (sz > g_z0 - 0.01) & (sz < g_z1 + 0.01)
            sc, sr = np.column_stack([sy, sz, np.ones_like(sy)])[ok] @ fit[:, 0], \
                np.column_stack([sy, sz, np.ones_like(sy)])[ok] @ fit[:, 1]
            ci, ri = np.clip(np.round(sc).astype(int), 0, w - 1), np.clip(np.round(sr).astype(int), 0, h - 1)
            al = np.clip((0.5 - lum[ri, ci]) / 0.35, 0, 1)
            better = al > ink[ok]
            idx = np.nonzero(ok)[0][better]
            ink[idx] = al[better]
            colour[idx] = src[ri, ci, :3][better]
        dst = albedo[mine, :3]
        albedo[mine, :3] = dst * (1 - ink[:, None]) + colour * ink[:, None]
    print("Sufa livery: camouflage texels", int(paint.sum()), "shares", [round(float(x), 2) for x in share],
          "fin texels", int(on_fin.sum()), "orange", int(orange.sum()), "fin height", round(float(tall), 2),
          "number at", round(float(n_z), 2), "glyph scale", round(float(k), 2), "leading edge",
          [tuple(round(float(x), 2) for x in p) for p in le], "trailing edge", [round(float(x), 2) for x in te])
    return albedo


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


def skin_bvh(objs):
    """A BVH of the livery-painted faces of `objs` (world frame), their triangles and each triangle's UVs."""
    from mathutils.bvhtree import BVHTree
    tris, uvs = [], []
    for o in objs:
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
    return BVHTree.FromPolygons(verts, [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(tris))]), tris, uvs


def wing_roundels(albedo, skin):
    """The livery's roundel moved to the IAF positions (ROUNDELS): drawn as a circle on the wing, its texels found by
    casting onto the skin; the livery's own roundel above the left wing painted over with the colours round it."""
    from mathutils.geometry import barycentric_transform
    h, w = albedo.shape[:2]
    bvh, tris, uvs = skin_bvh(skin)

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


def spine_island(albedo):
    """The spine's UV island (SP_ISLAND) painted from the livery at the unfolded places dorsal_spine recorded
    (SPINE_FILL), each texel between the two rings round it; 4 px of margin past the island's edges."""
    h, w = albedo.shape[:2]
    assert (h, w) == (2048, 2048), (h, w)
    x0, y0, x1, y1 = SP_ISLAND
    src = albedo.copy()
    ys = np.array([y for y, _, _ in SPINE_FILL])
    rows = np.arange(y0, y1)
    for col in range(x0 - 4, x1):
        y = SP_Y0 - (col + 0.5 - x0) / SP_ISLAND_K
        i = int(np.clip(np.searchsorted(-ys, -y) - 1, 0, len(ys) - 2))
        t = float(np.clip((ys[i] - y) / (ys[i] - ys[i + 1]), 0, 1))
        if y < ys[-1] - 4 / SP_ISLAND_K:
            break
        uv = 0
        for k, wk in ((i, 1 - t), (i + 1, t)):
            _, rp, su = SPINE_FILL[k]
            uv = uv + wk * np.stack([np.interp(rows + 0.5, rp, su[:, c]) for c in (0, 1)], axis=1)
        near = (rows + 0.5 >= SPINE_FILL[i][1][0] - 4) & (rows + 0.5 <= SPINE_FILL[i][1][-1] + 4)
        px = np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
        py = np.clip((uv[:, 1] * h).astype(int), 0, h - 1)  # rows bottom to top, as pixels() gives them
        albedo[h - 1 - rows[near], col] = src[py[near], px[near]]
    print("spine island painted, columns", x0, "to", col)
    return albedo


def materials(rig):
    objs = [o for o in kit.scene().objects if o.type == 'MESH']
    livery = bpy.data.images.load(os.path.join(M, LIVERY))
    skin = [o for o in objs if any(m and m.name.startswith("ac_f16.png") for m in o.data.materials)]
    albedo = wing_roundels(spine_island(pixels(livery)), skin)
    albedo = sufa_livery(albedo, skin) if SUFA else barak_livery(albedo, skin)
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
