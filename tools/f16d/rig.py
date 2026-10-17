# Build the detailed F-16D (Preferences -> Extras -> Models: Detailed; docs/aircraft-models.md) from the FlightGear
# F-16 (github.com/NikolaiVChr/f16, GPL-2.0-or-later; tools/f16d/SOURCES.md) with tools/plane/kit.py:
#   - FlightGear's single-seat f16.ac made two-seat: the canopy and the spine behind it stretched aft, a second
#     cockpit, seat and pilot;
#   - placed on the original model's frame: the wing on the original's wing, the pylons moved onto the original's
#     Station helpers, the oleos compressed so the wheels touch at the original's `height` helper;
#   - the moving parts named and hinged as the original's (`<part>1/2` helpers on FlightGear's own hinge lines,
#     taken from its F-16.xml animations), the helpers the game reads copied from the original model;
#   - closed gear doors (LdgDrUp, shown only with the gear up), the GE nozzle, an IAF desert livery (FlightGear's)
#     with our PBR maps (baked occlusion, panel-line normal map, roughness / metallic);
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
        "RedPosLight2"}
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
          "RWStation1": "StationF", "RWStation2": "StationG", "RWStation3": "StationH"}


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
    for pylon, station in PYLONS.items():
        o = body[pylon]
        lo, hi = bounds([o])
        at = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))  # the middle of its bottom edge
        d = helpers[station] + root - at
        o.data.transform(Matrix.Translation(d))
        print("pylon", pylon, "->", station, "moved", tuple(round(x, 3) for x in d))


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


def materials(rig):
    objs = [o for o in kit.scene().objects if o.type == 'MESH']
    livery = bpy.data.images.load(os.path.join(M, LIVERY))
    albedo = pixels(livery)
    size = albedo.shape[0]
    skin = [o for o in objs if any(m and m.name.startswith("ac_f16.png") for m in o.data.materials)]
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
