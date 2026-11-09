# The F-16 base of the detailed F-16 models (docs/aircraft-models.md §2; run through tools/f16/rig.py with a variant
# layer: barak.py, sufa.py). From the FlightGear F-16 (github.com/NikolaiVChr/f16, GPL-2.0-or-later;
# shared/extra/models/f16/SOURCES.md) with tools/plane/kit.py:
#   - FlightGear's single-seat f16.ac made two-seat: the canopy and the spine behind it stretched aft, a second
#     cockpit, seat and pilot, the single seater's aft canopy hoop rebuilt as the two-seater's centre bow;
#   - placed on the original model's frame: the wing on the original's wing, the pylons moved onto the original's
#     Station helpers, the oleos compressed so the wheels touch at the original's `height` helper;
#   - the moving parts named and hinged as the original's (`<part>1/2` helpers on FlightGear's own hinge lines,
#     taken from its F-16.xml animations), the helpers the game reads copied from the original model;
#   - the fin and rudder reaching FIN_DROP lower, onto the IAF dorsal spine (the avionics hump of the Block 30 / 40
#     "Brakeet"), lofted over the slim US spine level from the canopy's rear end to a box under the fin that ends
#     over the nozzle, with the layer's vents;
#   - closed gear doors (LdgDrUp, shown only with the gear up), FlightGear's IAF desert livery (its wing roundels
#     moved to the IAF positions) painted by the layer, with our PBR maps (baked occlusion, panel-line normal map,
#     roughness / metallic);
#   - written as one glb with KTX2 textures (tools/plane/glb_ktx2.py, needs `basisu`).
#
# A variant layer is a module with SPINE_VENTS (the spine's vents: [(centre y, width)], below its top, height),
# MATTE (added to the paint's roughness), nozzle() (its nozzle's objects, FlightGear's frame), fg_parts(body) (its
# own FlightGear parts, added before the two-seat stretch), own_parts(body) (its parts made on the finished
# airframe) and livery(albedo, skin) (its paint over FlightGear's livery).
#
# The original model is read only for its helper positions (where the game hangs stores, sees the wheels, …).
import json
import math
import os
import sys

import bmesh
import bpy
import glb_ktx2
import kit
import numpy as np
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
FG, ORIG, OUT = ARGS[:3]
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


# The two-seat canopy's centre bow (aircraft-models.md §1): on the F-16B / D / I the forward and aft transparencies
# meet on one narrow, near-black, upright bow just behind the front seat's headrest, halfway along the canopy
# (photos in SOURCES.md). FlightGear's single-seat frame has the F-16C's aft hoop there instead: 0.18 m deep at the
# top, leaning 24° aft and painted from the livery. canopy_bow rebuilds it upright, BOW_D deep, at BOW_Y (its middle;
# FlightGear's frame after two_seat): the hoop's two rings go to its faces, the forward glass's rear edge onto its
# front face (the glass eased over BOW_EASE m), the aft glass's front edge onto its back face; the frame below
# BOW_Z0 (the sill rails) slides with the glass's lower edge. The hoop's front ring (= the forward glass's rear edge)
# runs from y 3.40 at its top (z 1.129) forward by BOW_SLANT per m down.
BOW_Y, BOW_D, BOW_Z0, BOW_EASE, BOW_SLANT, BOW_TOP = 3.455, 0.07, 0.625, 0.4, 0.46, (3.40, 1.129)
BOW_COLOUR = (0.035, 0.036, 0.04)
BOW_SINK = 0.985  # the hoop's section scaled about the canopy's axis: FlightGear's stood 2 cm proud of the glass
DECK_Y = 2.45


def canopy_bow(body):
    front = BOW_Y + BOW_D / 2

    def ring(z):  # the hoop's front ring at height z
        return BOW_TOP[0] + BOW_SLANT * (BOW_TOP[1] - max(z, BOW_Z0))

    # FlightGear's fuselage closes the single-seat cockpit with a bulkhead under the hoop and a deck from its foot to
    # the canopy's rear end, which two_seat stretched over the rear cockpit: the bulkhead goes, the deck's front edge
    # moves back to DECK_Y, behind the rear seat, so the rear cockpit is open as the front one.
    skin = body["RadarDomeTop"].data
    wall = {v.index for v in skin.vertices if v.co.z > 0.6 and abs(v.co.x) < 0.45 and 2.9 < v.co.y < 3.75}
    bm = bmesh.new()
    bm.from_mesh(skin)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.index in wall for v in f.verts)], context='FACES')
    for v in bm.verts:
        if abs(v.co.x) < 0.35 and 0.6 < v.co.z < 0.7 and 3.4 < v.co.y < 3.5:
            v.co.y = DECK_Y
    bm.to_mesh(skin)
    bm.free()
    frame = body["CanopyFrame"].data
    hoop = {v.index for v in frame.vertices if v.co.z > BOW_Z0 and 3.0 < v.co.y < 3.65}
    for o in (body["CanopyFrame"], body["CanopyFrameInner"], body["CanopyForwardOutside"]):
        for v in o.data.vertices:
            c = v.co
            if o.data is frame and v.index in hoop:
                c.y = front if c.y > ring(c.z) - 0.04 else BOW_Y - BOW_D / 2
                c.x, c.z = c.x * BOW_SINK, 0.45 + (c.z - 0.45) * BOW_SINK  # nearly flush with the glass
            else:
                c.y += (front - ring(c.z)) * (1 - smooth01((c.y - ring(c.z)) / BOW_EASE))
        o.data.update()
    for v in body["CanopyBackOutside"].data.vertices:
        if v.co.y > 3.0:
            v.co.y = BOW_Y - BOW_D / 2
    bow = kit.material("canopy_bow", BOW_COLOUR, roughness=0.45)
    frame.materials.append(bow)
    for p in frame.polygons:
        if any(i in hoop for i in p.vertices):  # its foot too, down to the sill
            p.material_index = len(frame.materials) - 1
    frame.update()
    smooth_bow(frame, hoop, len(frame.materials) - 1)


# The bow's arch made smooth (2026-11-08): FlightGear's hoop has a section every 6-8° (8 a side), which from the seat
# looking back read as a faceted black polygon. smooth_bow puts in its place a box section swept through BOW_SEGS
# steps: its outer face on the hoop's outer edge (the convex hull of its sections about the canopy's axis at
# BOW_AXIS_Z, interpolated by angle), BOW_T m deep inward (inferred; the photos show a narrow bow), BOW_D along the
# jet as before. The hoop's feet (the faces down to the sill) stay.
BOW_SEGS, BOW_T, BOW_AXIS_Z = 48, 0.03, 0.45


def smooth_bow(frame, hoop, mat):
    def polar(c):
        return math.atan2(c.x, c.z - BOW_AXIS_Z), math.hypot(c.x, c.z - BOW_AXIS_Z)

    pts = sorted({(round(v.co.x, 4), round(v.co.z, 4)) for v in frame.vertices if v.index in hoop})
    hull = []  # the upper chain of the convex hull (x ascending): the arch's outer edge
    for p in pts:
        while len(hull) > 1 and ((hull[-1][0] - hull[-2][0]) * (p[1] - hull[-2][1]) -
                                 (hull[-1][1] - hull[-2][1]) * (p[0] - hull[-2][0])) >= 0:
            hull.pop()
        hull.append(p)
    th, r = zip(*sorted(polar(Vector((x, 0, z))) for x, z in hull))
    bm = bmesh.new()
    bm.from_mesh(frame)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.index in hoop for v in f.verts)], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    ys = (BOW_Y + BOW_D / 2, BOW_Y - BOW_D / 2)
    ang = np.linspace(th[0], th[-1], BOW_SEGS + 1)
    ro = np.interp(ang, th, r)

    def at(a, rad, y):
        return bm.verts.new((rad * math.sin(a), y, BOW_AXIS_Z + rad * math.cos(a)))

    def face(vs, out):  # a face of the bow facing `out`
        f = bm.faces.new(vs)
        f.material_index = mat
        f.normal_update()
        if f.normal.dot(out) < 0:
            f.normal_flip()
        return f

    # Four strips, each with its own vertices (smooth along the arch, sharp at the section's corners): outer, inner,
    # front, back (r offset, y of each edge, the side they face); then the end caps.
    for (r0, y0), (r1, y1), side in (((0, ys[1]), (0, ys[0]), 1), ((-BOW_T, ys[0]), (-BOW_T, ys[1]), -1),
                                     ((-BOW_T, ys[0]), (0, ys[0]), 0), ((0, ys[1]), (-BOW_T, ys[1]), 0)):
        rows = [(at(a, ro[i] + r0, y0), at(a, ro[i] + r1, y1)) for i, a in enumerate(ang)]
        for i, ((a0, b0), (a1, b1)) in enumerate(zip(rows, rows[1:])):
            a = (ang[i] + ang[i + 1]) / 2
            out = Vector((side * math.sin(a), y0 - BOW_Y if side == 0 else 0, side * math.cos(a)))
            face((a0, b0, b1, a1), out).smooth = True
    for i, j in ((0, 1), (-1, -2)):
        q = [at(ang[i], ro[i] + dr, y) for dr, y in ((0, ys[0]), (0, ys[1]), (-BOW_T, ys[1]), (-BOW_T, ys[0]))]
        face(q, Vector((math.sin(ang[i]) - math.sin(ang[j]), 0, math.cos(ang[i]) - math.cos(ang[j]))))
    bm.to_mesh(frame)
    bm.free()
    frame.update()


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


# The wingtip rails and the six wing pylons (ours, 2026-11-09): FlightGear maps each onto one spot of the livery (the
# rails a tan strip, the pylons its grey margin), so on a clean jet they showed as flat, untextured blocks, and leaves
# the pylons' tops open. store_paint caps them and lays every face out flat, at STORE_K px per m, on its own place in
# STORE_ISLAND (a free grey rectangle of the livery, pixels from the top left), painted STORE_PAINT: the paint's
# material, with the occlusion bake's shading. STORE_PAINT (sRGB) is a warm grey so that the rails and pylons, mostly
# in the sky's blue light, render as FS 36375 light ghost grey (166, 173, 180): measured on the 3D cockpit's
# look-back and outside renders, where FS 36375 itself rendered blue (104, 118, 142) (docs/aircraft-models.md §1.5).
STORE_PARTS = ["WingTips"] + [p for p in PYLONS if p != "CLStation"]
STORE_ISLAND, STORE_K = (1640, 1390, 2030, 1545), 36.0
STORE_PAINT = (0.843, 0.824, 0.765)


def store_paint(body):
    x0, y0, x1, y1 = STORE_ISLAND
    cx, cy, row_h = x0 + 2, y0 + 2, 0.0
    for name in STORE_PARTS:
        me = body[name].data
        bm = bmesh.new()
        bm.from_mesh(me)
        caps = bmesh.ops.holes_fill(bm, edges=bm.edges)["faces"]
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        uv = bm.loops.layers.uv.active
        for side in (-1, 1):  # WingTips holds both rails: each side its own place
            faces = [f for f in bm.faces if (f.calc_center_median().x > 0) == (side > 0)]
            if not faces:
                continue
            vs = [v.co for f in faces for v in f.verts]
            lo = Vector([min(c[i] for c in vs) for i in range(3)])
            ext = Vector([max(c[i] for c in vs) for i in range(3)]) - lo
            # Rows: the faces looking +x, -x (along y, z), +z, -z (along y, x), then ±y (along x, z), side by side.
            rows = [((0, 1), 1, 2, 0), ((0, -1), 1, 2, 0), ((2, 1), 1, 0, 0), ((2, -1), 1, 0, 0),
                    ((1, 1), 0, 2, 0), ((1, -1), 0, 2, ext.x * STORE_K + 2)]
            w = max(ext.y, 2 * ext.x) * STORE_K + 4
            h = (3 * ext.z + 2 * ext.x) * STORE_K + 12
            if cx + w > x1:
                cx, cy, row_h = x0 + 2, cy + row_h, 0.0
            assert cy + h <= y1, ("STORE_ISLAND full", name)
            top = cy
            for (axis, sign), a, b, dx in rows:
                for f in faces:
                    k = max(range(3), key=lambda i: abs(f.normal[i]))
                    if k != axis or (f.normal[k] > 0) != (sign > 0):
                        continue
                    for lp in f.loops:
                        c = lp.vert.co - lo
                        lp[uv].uv = ((cx + dx + c[a] * STORE_K) / 2048, 1 - (top + c[b] * STORE_K) / 2048)
                if (axis, sign) != (1, 1):
                    top += ext[b] * STORE_K + 2
            cx, row_h = cx + w, max(row_h, h)
        bm.to_mesh(me)
        print("store paint", name, "caps", len(caps))


# The IAF dorsal spine (our frame, after SHIFT; y forward, z up). Its front (SP_Y0) is the glass's rear edge, an arch
# 0.34 m wide whose top is SP_Z0, so the canopy runs on into it; it widens to 0.34 m (half-width) by y = -0.5, eases
# down to SP_Z_TOP by SP_Y_LEVEL and runs level to its end over the nozzle (SP_Y_END), the lowered fin standing on
# it. Half-widths (y, w) between which it is interpolated: the glass's rear arch, 0.34 m to the wing's trailing
# edge, the fin root's width under the fin; its front sections are round as the arch (SP_ROUND m), its shoulders
# 0.12 m from there. Aft of SP_Y_FLOOR the fuselage falls away to the nozzle and the box gets a flat floor at SP_FLOOR; its last
# SP_END_R m round off into a cap. The layer's vents on each side (SPINE_VENTS) ahead of the fin. Photographs (SOURCES.md): IAF F-16D 027 side on (Oren Rozen): the canopy stands
# 0.25 m above the spine, whose top is level from the canopy's rear frame to the fin, the three vents 0.6 m ahead of
# the fin, the tail box as tall as the spine with a round end (F-16C 333's tail); IAF F-16I from above: the canopy
# ends square at nearly its full width and the spine goes on at that width; F-16D 601, 022 / 046 / 050 / 063.
SP_Y0, SP_Z0, SP_Y_LEVEL, SP_ROUND = 0.47, 0.945, -0.6, 0.7
SP_Z_TOP = 1.148 - FIN_DROP
SP_Y_FIN = -3.86
SP_Y_END, SP_Y_FLOOR, SP_FLOOR, SP_END_R = -6.42, -5.3, 0.62, 0.22
SP_WIDTH = [(SP_Y0, 0.19), (-0.5, 0.34), (-2.4, 0.34), (-3.86, 0.2), (-6.3, 0.2), (SP_Y_END, 0.17)]
SP_FILLET = 0.05  # the concave flare where the sides meet the fuselage
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


def dorsal_spine(body, vents):
    """The IAF F-16D's dorsal spine: a loft of rounded-box sections over FlightGear's fuselage (`RadarDomeTop`),
    flared into it at the sides; its livery UVs are its own island (SP_ISLAND), painted by spine_island from the
    fuselage's livery round it, unfolded at true size (the camouflage runs on unbroken at its foot). The fuselage
    faces it covers are removed, the blade antenna and the formation light are raised onto it. `vents`: the
    layer's SPINE_VENTS."""
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
    vent_ys, vent_z, vent_h = vents
    for yc, half in ((yc, w / 2) for yc, w in vent_ys):  # the vents: dark panels just off each side
        z0 = spine_top(yc) - vent_z - vent_h / 2
        for sx in (1, -1):
            c = [(yc - half, z0), (yc + half, z0), (yc + half, z0 + vent_h), (yc - half, z0 + vent_h)]
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


# The ACES II seat's parts the front pilot sees looking back (the headrest, the pitot tubes beside it, the parachute
# container and the back structure round them), kept at full detail in the front seat (2026-11-08): decimated with
# the rest they were faceted wedges a hand's width from the eye. The rest of the seat, and the rear seat, stay at 0.3.
SEAT_SEEN = {"head-rest", "pitot-tubes", "main-chute-container", "main-chute-extractor", "back-structure",
             "rocket-catapult"}
# The pilots' helmet and visor are kept whole too: the rear pilot's helmet shows over the front headrest, and at the
# pilot's 0.1 it was a faceted dark dome. FlightGear's own helmet is coarse (220 faces, its outline polygonal at a
# metre), so the rear pilot's is subdivided once and shaded smooth (REAR_SMOOTH; the front pilot is hidden from the
# seat, and seen from outside the helmet is a few pixels).
PILOT_WHOLE = {"helmet", "L-visor"}
REAR_SMOOTH = {"helmet"}


def decimated(path, prefix, name, ratio, whole, smooth=()):
    """An AC3D file's objects joined as `name`: those named in `whole` as they are (those also in `smooth` subdivided
    once and shaded smooth), the rest decimated to `ratio`."""
    parts = kit.import_ac(os.path.join(M, path), prefix=prefix)
    rest = kit.join([o for part, o in parts.items() if part not in whole], name)
    kit.decimate(rest, ratio)
    for part in smooth:
        o = parts[part]
        o.modifiers.new("subdiv", 'SUBSURF').levels = 1
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="subdiv")
        o.data.shade_smooth()
    return kit.join([rest] + [o for part, o in parts.items() if part in whole], name)


def cockpit(prefix, shift, seen=(), smooth=()):
    """FlightGear's cockpit tub, ACES II seat and pilot (decimated; the seat's parts named in `seen` and the pilot's
    PILOT_WHOLE kept whole, those in `smooth` subdivided), shifted `shift` along y."""
    tub = kit.join(list(kit.import_ac(os.path.join(M, "Cockpit/Main/cockpit.ac"), prefix=prefix + "tub_").values()),
                   prefix + "tub")
    seat = decimated("Cockpit/chair/chair.ac", prefix + "seat_", prefix + "seat", 0.3, seen)
    pilot = decimated("pilot_externalview.ac", prefix + "pil_", prefix + "pilot", 0.1, PILOT_WHOLE, smooth)
    kit.decimate(tub, 0.5)
    for o in (tub, seat, pilot):
        o.data.transform(Matrix.Translation((0, shift, 0)))
    return tub, kit.join([seat, pilot], prefix + "crew")


def build(variant):
    """The F-16 base with the variant layer `variant` (a module, see the header) written to OUT."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root_at, helpers = original()
    body = kit.import_ac(os.path.join(M, "f16.ac"))
    for n in DROP:
        if n in body:
            bpy.data.objects.remove(body.pop(n))
    noz = variant.nozzle()
    variant.fg_parts(body)
    # The centreline pylon (loads_models.xml's Centerpylon: 0.02 m to the right), grey as the original's.
    body["CLStation"] = kit.join(list(kit.import_ac(os.path.join(M, "central-pylon.ac"), matrix=Matrix.Translation(
        fg((0, 0.02, 0))), prefix="cl_").values()), "CLStation")
    body["CLStation"].data.materials.clear()
    body["CLStation"].data.materials.append(kit.material("pylon_grey", (0.42, 0.44, 0.45), roughness=0.55))
    lower_fin(body)
    tub_f, crew_f = cockpit("front_", 0.0, SEAT_SEEN)
    two_seat(list(body.values()) + [tub_f])
    canopy_bow(body)
    tub_r, crew_r = cockpit("rear_", -SEAT_GAP, smooth=REAR_SMOOTH)
    everything = [o for o in kit.scene().objects if o.type == 'MESH']
    transform(everything, Matrix.Translation(SHIFT))
    fit_pylons(body, helpers, root_at)
    store_paint(body)
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
    dorsal_spine(body, variant.SPINE_VENTS)
    variant.own_parts(body)
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
    materials(variant)
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


# The FS 595 colours of the model paint guides (docs/f16i.md §8), sRGB 0..1: FS 30219 tan, 33531 sand, 34424 green
# over FS 36375 light ghost grey; radome FS 36270. The layers' undersides and radomes use them.
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
# Places in the 2048 px livery (pixels from the top left). The radome's top and bottom halves (x0, y0, x1, y1).
RADOME = [(1340, 420, 1600, 560), (390, 990, 670, 1130)]


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


def materials(variant):
    objs = [o for o in kit.scene().objects if o.type == 'MESH']
    livery = bpy.data.images.load(os.path.join(M, LIVERY))
    skin = [o for o in objs if any(m and m.name.startswith("ac_f16.png") for m in o.data.materials)]
    albedo = variant.livery(wing_roundels(spine_island(pixels(livery)), skin), skin)
    x0, y0, x1, y1 = STORE_ISLAND  # after the layer's paint, which would recolour it
    albedo[albedo.shape[0] - y1:albedo.shape[0] - y0, x0:x1, :3] = STORE_PAINT
    size = albedo.shape[0]
    ao = np.ones(albedo.shape[:2], dtype=np.float32) if FAST else bake_ao(skin, size)
    normal, groove = panel_maps(albedo)
    rough = np.clip(0.42 + 0.25 * groove + 0.08 * (1 - ao) + variant.MATTE, 0, 1)
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


