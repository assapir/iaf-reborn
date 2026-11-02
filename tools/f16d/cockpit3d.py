# The F-16's real-time 3D front cockpit (Extras "Cockpit": 3D; docs/cockpit.md "3D cockpit") from the FlightGear
# F-16's interior (github.com/NikolaiVChr/f16 at PIN, GPL-2.0-or-later; game/extra/models/f16/SOURCES.md) with
# tools/plane/kit.py:
#   - FlightGear's `Models/Cockpit/Main/cockpit.xml` and the parts it includes, as its Block 50/52 (sim/variant-id 5)
#     shows them: the tub and glareshield, the HUD, both MFDs, ICP, DED, the instruments, eyebrow lamp panels, the
#     consoles (decimated), throttle, stick and pedals; not the seat, canopy and rear cockpit (the detailed F-16's own,
#     docs/aircraft-models.md §1.4), the kneeboards, pilot and helmet;
#   - each sub-model placed by its <offsets>; its `select` animations evaluated once for a powered jet with every lamp
#     off (the off flags and lamps hidden), but for the lamps the game lights (LAMPS: their own nodes, <out>.json
#     `lamps`); its `rotate` / `knob` animations on the properties the game drives (NEEDLE_PROPS) made nodes turning
#     about their hinge, listed in <out>.json with FlightGear's value mapping; its texture scrolls on TEX_PROPS (the
#     AoA tape) in <out>.json `textures`; the canvas displays the game draws (DISPLAYS) as named nodes;
#   - in the detailed F-16's frame (tools/f16/base.py: FlightGear's model moved SHIFT aft, under a root at the original
#     model's origin), so the game hangs it in the cut cockpit model (own_bc) as is;
#   - the MFD screens (MFD_L, MFD_R: FlightGear's canvas quads), the HUD combiner glass (HUD_glass) and the 20 OSBs of
#     each MFD as named nodes; written as one glb with KTX2 textures (tools/plane/glb_ktx2.py, needs `basisu`).
#
#   blender -b --python tools/f16d/cockpit3d.py -- <FlightGear f16 checkout> \
#       <assets/converted/planes/f16/f16_h.gltf> game/extra/models/cockpit3d/f16.glb
import json
import math
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

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
PIN = "ef4f192f06243cf4061c2be794511db0576ac2f9"  # the commit the detailed F-16D is built from (SOURCES.md)
SHIFT = Vector((0.0, -1.05, 0.0))  # base.py's: FlightGear's model -> the original's frame (the wing on its wing)
# The sub-models of cockpit.xml left out: the seat and the canopy frame come from the detailed F-16's cut model, the
# kneeboards and helmet are the pilot's; the B10 stick and the other HUDs are other blocks' (their conditions).
SKIP = {"chair", "knee1", "knee2", "HMCS-basic", "HMCS-norm", "HUDb", "HUDd"}
# The two HUDs, each its own node the game shows per jet: the Block 50's (HUDa, hud.xml: two posts and a small
# combiner) for the Barak, FlightGear's wide-angle HUD (HUDc, f16_war.xml) for the Sufa. The Sufa's Elbit wide-angle
# HUD: one large combiner plate over a deep box (an F-16I seen from the side, IDF Spokesperson's Unit, CC BY-SA 3.0,
# commons.wikimedia.org/wiki/File:Israeli_attacks_on_Yemen,_January_2025._XV.jpg, a reference only); its shape
# beyond that is open, the wide-angle HUD inferred the closer of FlightGear's two.
HUDS = {"HUDa": "HUD_std", "HUDc": "HUD_wide"}
# The Block 50/52 jet FlightGear's conditions see: powered, its instruments serviceable, every lamp and test off.
PROPS = {"sim/variant-id": 5, "sim/current-view/internal": 1, "systems/static/serviceable": 1}
POWER_PREFIX = "fdm/jsbsim/elec/bus/"
# FlightGear's properties the game drives (game/cockpit/cockpit3d.gd PROPS): the rotate animations on them become
# turning nodes; the rest stay at rest.
NEEDLE_PROPS = {
    "instrumentation/airspeed-indicator/indicated-speed-kt", "velocities/mach", "f16/avionics/vvi-indicated-speed-fps",
    "engines/engine[0]/n2", "engines/engine[0]/ftit-degc", "engines/engine[0]/nozzle-pos-norm-lag",
    "engines/engine[0]/oil-pressure-psi", "orientation/roll-deg", "orientation/pitch-deg",
    "instrumentation/attitude-indicator[2]/indicated-roll-deg",
    "instrumentation/attitude-indicator[2]/indicated-pitch-deg",
    "instrumentation/magnetic-compass/indicated-heading-deg", "controls/engines/engine/throttle-movement",
    "controls/engines/engine/augmentation", "consumables/fuel/total-fuel-lbs-1", "consumables/fuel/total-fuel-lbs-10",
    "consumables/fuel/total-fuel-lbs-100", "consumables/fuel/total-fuel-lbs-1000",
    "consumables/fuel/total-fuel-lbs-10000", "f16/fuel/hand-fwd-lag", "f16/fuel/hand-aft-lag",
    "instrumentation/clock/indicated-sec", "controls/flight/elevator", "controls/flight/aileron",
    "controls/gear/gear-down", "f16/cockpit/fuel-flow-digit-3", "f16/cockpit/fuel-flow-digit-4",
    "f16/cockpit/fuel-flow-digit-5",
}
# The texture scrolls (`textranslate`) the game drives: the AoA tape.
TEX_PROPS = {"fdm/jsbsim/fcs/fly-by-wire/pitch/alpha-indicated"}
# The lamps the game lights (cockpit3d.gd _lamp_on), by (sub-model, object): FlightGear's `select` lamps (shown when
# lit) and `material` lamps (an emission when lit), each its own node lamp_<key>_<n>, listed in <out>.json `lamps`.
LAMPS = {
    ("EYEBROW_LEFT", "master_caution"): "master_caution", ("EYEBROW_RIGHT", "eng_fire"): "eng_fire",
    ("EYEBROW_RIGHT", "flcs"): "flcs", ("EYEBROW_RIGHT", "to_ldg_config"): "to_ldg_config",
    ("EYEBROW_RIGHT", "engine"): "engine", ("EYEBROW_RIGHT", "hyd_oil_press"): "hyd_oil_press",
    ("Tub", "down"): "aoa_slow", ("Tub", "steady"): "aoa_on_speed", ("Tub", "up"): "aoa_fast",
    ("Tub", "ar_nws"): "ar_nws", ("LeftAuxConsole", "GEAR-nose"): "gear_nose",
    ("LeftAuxConsole", "GEAR-left"): "gear_left", ("LeftAuxConsole", "GEAR-right"): "gear_right",
    ("LeftAuxConsole", "gear_lever_light"): "gear_transit", ("THREAT", "launch"): "rwr_launch",
}
# FlightGear's canvas displays the game draws into (cockpit3d.gd _attach_display), by (sub-model, object): the node.
DISPLAYS = {("IFF", "bkg"): "RWR_scope", ("EHSI", "EHSI-Display"): "EHSI_screen", ("DED", "poly.003"): "DED_screen"}
# Triangles kept of each heavy part (FlightGear's counts; the research's Iris Xe budget, docs/graphics-research.md
# §3.8): the consoles beside and below the eye.
DECIMATE = {"LeftConsole": 0.3, "LeftAuxConsole": 0.3, "RightConsole": 0.35, "RightAuxConsole": 0.5, "ICP": 0.45,
            "MISC": 0.5, "Throttle": 0.4, "F-16-FS": 0.5}
# The block panel sheets (Textures/Block-panels; the left aux console's and the RWR head's labels): the model keeps
# FlightGear's Block 50 sheet (the F-16I Sufa's base, a Block 52+); the F-16D Barak (Block 30/40, docs/real-aircraft.md
# §8) gets the Block 40 one.
SUFA_PANELS, BARAK_PANELS = "blck50-panels1.png", "blck40-panels1.png"
MAX_TEX = 1024  # textures larger than this are halved (the console sheets are 1024 x 2048)
# FlightGear's frame (x aft, y right, z up) -> Blender's (x right, y forward, z up).
C = Matrix(((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
# The tub (cockpit.ac) ends at the eye's plane (FlightGear's frame x, aft): the detailed F-16's cut model
# (aircraft_model.gd detailed_cockpit) draws the tub from there aft, with its two-seat changes. The game's eye there:
# the detailed F-16's pilot + F16_EYE_IN_PILOT, 3.3 cm aft of FlightGear's view point (measured in the game).
TUB_CUT_X = -4.072
# FlightGear's pilot view (f16-base.xml view 0: x-offset 0, y-offset 0.8579 up, z-offset -4.105 aft), FlightGear frame.
FG_EYE = (-4.105, 0.0, 0.8579)


def fg_path(p, here):
    """A path in an xml: Aircraft/f16/... from the package root, else relative to the xml's folder."""
    p = p.strip()
    if p.startswith("Aircraft/f16/"):
        return os.path.join(FG, p[len("Aircraft/f16/"):])
    if p.startswith("/") or p.startswith("Aircraft/"):
        return None  # FGData's (not in the package)
    return os.path.join(here, p)


def num(node, tag, default=0.0):
    t = node.findtext(tag) if node is not None else None
    return float(t) if t is not None and t.strip() else default


def offsets(node):
    """<offsets> as a matrix in FlightGear's frame: pitch (about y), then roll (x), then heading (z), then the
    translation (simgear's ReaderWriterXML / osg::Matrix::makeRotate order)."""
    o = node.find("offsets") if node is not None else None
    if o is None:
        return Matrix.Identity(4)
    r = (Matrix.Rotation(math.radians(num(o, "heading-deg")), 4, 'Z')
         @ Matrix.Rotation(math.radians(num(o, "roll-deg")), 4, 'X')
         @ Matrix.Rotation(math.radians(num(o, "pitch-deg")), 4, 'Y'))
    return Matrix.Translation((num(o, "x-m"), num(o, "y-m"), num(o, "z-m"))) @ r


def prop(name):
    name = name.strip().lstrip("/")
    if name.startswith(POWER_PREFIX):
        return 115.0 if "-ac-" in name else 28.0  # volts: an AC bus, a DC bus
    return float(PROPS.get(name, 0))


def value(n):
    p = n.find("property")
    return prop(p.text) if p is not None else float(n.findtext("value", "0") or 0)


def lit(s):
    s = (s or "0").strip()
    try:
        return float(s)
    except ValueError:
        return {"true": 1.0, "false": 0.0}.get(s.lower(), s)


def cond(c):
    """A FlightGear <condition> (an implicit and) for the jet of PROPS."""
    return all(term(t) for t in c)


def term(t):
    k = t.tag
    if k in ("and", "condition"):
        return all(term(x) for x in t)
    if k == "or":
        return any(term(x) for x in t)
    if k == "not":
        return not all(term(x) for x in t)
    if k == "property":
        return prop(t.text) != 0
    vals = [prop(x.text) if x.tag == "property" else lit(x.text) for x in t if x.tag in ("property", "value")]
    if len(vals) < 2:
        return True
    a, b = vals[:2]
    return {"equals": a == b, "not-equals": a != b, "greater-than": a > b, "less-than": a < b,
            "greater-than-equals": a >= b, "less-than-equals": a <= b}.get(k, True)


def axis_of(a):
    ax = a.find("axis")
    if ax is None:
        return Vector((0, 0, 1)), None
    if ax.find("x1-m") is not None:
        p1 = Vector((num(ax, "x1-m"), num(ax, "y1-m"), num(ax, "z1-m")))
        p2 = Vector((num(ax, "x2-m"), num(ax, "y2-m"), num(ax, "z2-m")))
        return (p2 - p1).normalized(), (p1 + p2) / 2
    return Vector((num(ax, "x"), num(ax, "y"), num(ax, "z"))).normalized(), None


def mapping(a):
    """FlightGear's value mapping of a rotate animation (simgear read_value): an interpolation table, else
    factor · value + offset-deg clamped to min-deg / max-deg."""
    tab = a.find("interpolation")
    if tab is not None:
        return {"table": [[float(e.findtext("ind")), float(e.findtext("dep"))] for e in tab.findall("entry")]}
    m = {"factor": num(a, "factor", 1.0), "offset": num(a, "offset-deg")}
    for k in ("min-deg", "max-deg"):
        if a.find(k) is not None:
            m[k[:3]] = num(a, k)
    return m


class Build:
    def __init__(self):
        self.parts = {}  # sub-model name -> [objects]
        self.anims = {}  # object -> [animation records, outermost first]
        self.hidden = 0
        self.texanims = {}  # object -> [textranslate records]
        self.lamps = {}  # object -> {key, hide (a select lamp: hidden when off), colour (its emission)}
        self.displays = {}  # object -> node name

    def walk(self, xml, m, part, depth=0):
        here = os.path.dirname(xml)
        root = ET.parse(xml).getroot()
        m = m @ offsets(root)
        ac = root.findtext("path")
        objs, groups = {}, {}
        if ac and fg_path(ac, here) and os.path.exists(fg_path(ac, here)):
            objs = kit.import_ac(fg_path(ac, here), matrix=C @ m @ C.inverted(), prefix=part + "/", groups=groups)
        hide = set()
        for a in root.findall("animation"):
            t = (a.findtext("type") or "").strip()
            names = [o.text.strip() for o in a.findall("object-name")]
            lamps = [n for n in names if (part, n) in LAMPS and n in objs]
            for n in lamps:
                rec = self.lamps.setdefault(objs[n], {"key": LAMPS[(part, n)], "hide": False, "colour": [1, 1, 1]})
                if t == "select":
                    rec["hide"] = True
                elif t == "material" and a.find("emission") is not None:
                    rec["colour"] = [num(a.find("emission"), c) for c in ("red", "green", "blue")]
            if t == "select" and a.find("condition") is not None and not cond(a.find("condition")):
                hide.update(n for n in names if n not in lamps)
            elif t == "textranslate" and (a.findtext("property") or "").strip() in TEX_PROPS:
                ax = a.find("axis")
                rec = {"prop": a.findtext("property").strip(), "factor": num(a, "factor", 1.0),
                       "offset": num(a, "offset"), "axis": [num(ax, "x"), num(ax, "y")]}
                for n in names:
                    if n in objs:
                        self.texanims.setdefault(objs[n], []).append(rec)
            elif t in ("rotate", "knob") and (a.findtext("property") or "").strip() in NEEDLE_PROPS:
                axis, mid = axis_of(a)
                c = a.find("center")
                centre = Vector((num(c, "x-m"), num(c, "y-m"), num(c, "z-m"))) if c is not None else (mid or Vector())
                rec = {"prop": a.findtext("property").strip(), **mapping(a),
                       "centre": list(C @ m @ centre), "axis": list((C @ m).to_3x3() @ axis)}
                for n in dict.fromkeys(g for n in names for g in groups.get(n, [n])):  # a group: its meshes
                    if n in objs:
                        self.anims.setdefault(objs[n], []).append(rec)
        for n in objs:
            if (part, n) in DISPLAYS:
                self.displays[objs[n]] = DISPLAYS[(part, n)]
        for n in hide & set(objs):
            bpy.data.objects.remove(objs.pop(n))
            self.hidden += 1
        self.parts.setdefault(part, []).extend(objs.values())
        for sub in root.findall("model"):
            name = (sub.findtext("name") or "").strip()
            p = fg_path(sub.findtext("path") or "", here)
            if name in SKIP or (name in hide and name not in HUDS) or p is None or not os.path.exists(p):
                print("skip", name, sub.findtext("path"))
                continue
            if sub.find("condition") is not None and not cond(sub.find("condition")):
                continue
            self.walk(p, m @ offsets(sub), name if depth == 0 else part, depth + 1)


def altimeter(b):
    """The altimeter: FlightGear's comes from FGData (Instruments-3d/altimeter), outside the package. Ours: the ASI's
    mount and dial plate copied to the altimeter's place (cockpit.xml `altitude`: 0.0833 m right of the ASI, the same
    height and tilt), the dial FlightGear's own altimeter face (Textures/faces1.png, its lower left quarter), a white
    needle turning once per 1,000 ft (the 2D panel's long needle, docs/cockpit.md "Round gauges")."""
    asi = {o.name.split("/", 1)[1]: o for o in b.parts["ASI"]}
    shift = Matrix.Translation((0.041 + 0.0423, 0, 0))  # FlightGear y (right) = Blender x
    parts = []
    for name in ("ASI_mount", "ASI_bkg2"):
        o = asi[name].copy()
        o.data = asi[name].data.copy()
        o.name = "altitude/ALT_" + name[4:]
        kit.scene().collection.objects.link(o)
        o.data.transform(shift)
        parts.append(o)
    dial = parts[1]
    img = bpy.data.images.load(os.path.join(FG, "Models/Cockpit/Textures/faces1.png"), check_existing=True)
    dial.data.materials.clear()
    dial.data.materials.append(kit.material("alt_face", (1, 1, 1), roughness=0.6, image=img))
    # The dial's UVs: its plane (tilted 20 degrees back) mapped onto the face's quarter.
    vs = [v.co for v in dial.data.vertices]
    lo, hi = Vector(map(min, *vs)), Vector(map(max, *vs))
    uv = dial.data.uv_layers.active.data
    for poly in dial.data.polygons:
        for li in poly.loop_indices:
            c = dial.data.vertices[dial.data.loops[li].vertex_index].co
            uv[li].uv = ((c.x - lo.x) / (hi.x - lo.x) * 0.5, (c.z - lo.z) / (hi.z - lo.z) * 0.5)
    centre = (lo + hi) / 2
    normal = Vector((0, -math.cos(math.radians(20)), math.sin(math.radians(20))))  # toward the pilot
    up = normal.cross(Vector((1, 0, 0))).normalized()
    if up.z < 0:
        up = -up
    r = (hi.x - lo.x) / 2 * 0.62
    w = Vector((0.0018, 0, 0))
    base = centre + normal * 0.003
    tip = base + up * r
    me = bpy.data.meshes.new("ALT_needle")
    me.from_pydata([base - w, base + w, tip + w * 0.4, tip - w * 0.4], [], [(0, 1, 2, 3)])
    needle = bpy.data.objects.new("altitude/ALT_needle", me)
    kit.scene().collection.objects.link(needle)
    needle.data.materials.append(kit.material("alt_needle", (0.95, 0.95, 0.95), roughness=0.5))
    b.parts["altitude"] = parts + [needle]
    # Clockwise as the pilot sees it: about the axis into the panel (FlightGear's right-hand rule).
    b.anims[needle] = [{"prop": "instrumentation/altimeter/indicated-altitude-ft", "factor": 0.36, "offset": 0.0,
                        "centre": list(base), "axis": list(-normal)}]


def merge_materials(objs):
    """One material per look (texture, colour, alpha, cut-out, sides): import_ac makes one per AC material index and
    file, 195 in all; each is a draw call in the joined body."""
    seen = {}
    for o in objs:
        for i, m in enumerate(o.data.materials):
            if m is None:
                continue
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            tex = next((n for n in m.node_tree.nodes if n.type == 'TEX_IMAGE'), None)
            key = (tex.image.name if tex is not None and tex.image is not None else None,
                   tuple(round(x, 3) for x in bsdf.inputs["Base Color"].default_value) if bsdf else None,
                   round(bsdf.inputs["Alpha"].default_value, 3) if bsdf else None,
                   bsdf.inputs["Alpha"].is_linked if bsdf else None, m.blend_method, m.use_backface_culling,
                   m.name if m.name.startswith(("display_off", "pedal", "hud_black", "alt_")) else "")
            o.data.materials[i] = seen.setdefault(key, m)
    print("materials", len({m for o in objs for m in o.data.materials}), "looks", len(seen))


def original_root():
    g = json.load(open(ORIG))
    n = g["nodes"][g["scenes"][0]["nodes"][0]]
    t = n["matrix"][12:15] if "matrix" in n else n.get("translation", (0, 0, 0))
    return Vector((t[0], -t[2], t[1]))


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)


def fix_materials(objs):
    """FlightGear's textures with cut-out alpha (labels, the button sheets) drawn with alpha clip; images larger than
    MAX_TEX halved; the DED's and PFD's canvas placeholders ("DED panel") a dark, unlit display."""
    seen = set()
    dark = kit.material("display_off", (0.012, 0.016, 0.014), roughness=0.15)
    for o in objs:
        for i, mat in enumerate(o.data.materials):
            tex = next((n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE'), None) if mat else None
            if tex is not None and tex.image is not None and os.path.basename(tex.image.filepath) == "canvas.png":
                o.data.materials[i] = dark
        for mat in o.data.materials:
            if mat is None or mat in seen:
                continue
            seen.add(mat)
            tex = next((n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE'), None)
            if tex is None or tex.image is None:
                continue
            img = tex.image
            if max(img.size) > MAX_TEX and not img.get("halved"):
                img.scale(img.size[0] // 2, img.size[1] // 2)
                img["halved"] = True
            if img.channels == 4:
                a = np.empty(img.size[0] * img.size[1] * 4, np.float32)
                img.pixels.foreach_get(a)
                if (a[3::4] < 0.5).mean() > 0.001:
                    b = mat.node_tree.nodes["Principled BSDF"]
                    mat.node_tree.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
                    mat.blend_method = 'CLIP'


def hud_wide_top(objs):
    """The wide-angle HUD's top left out, so its combiner plate stands free between its two side posts as on the
    F-16I (the HUDS photo): the lid (HUDtop with its screws and tissue); the second glass ahead of the combiner
    (BackGlass, a 4 cm strip at the eye's height in a black cover, BackGlassCover); and HUDFrame's bar over the
    combiner, its faces above the glass that reach in over it (the posts' tops stay). From the eye these drew a dark
    bar across the top of the view, closing the posts into a loop."""
    for o in objs:
        if o.name.split("/", 1)[1] in ("HUDtop", "screws", "tissue", "BackGlass", "BackGlassCover"):
            o.data.clear_geometry()
    glass = next((o for o in objs if o.name.endswith("/HUDImage2")), None)
    frame = next((o for o in objs if o.name.endswith("/HUDFrame")), None)
    if glass is None or frame is None:
        return
    vs = [v.co for v in glass.data.vertices]
    top = max(v.z for v in vs)
    cx = (min(v.x for v in vs) + max(v.x for v in vs)) / 2
    half = (max(v.x for v in vs) - min(v.x for v in vs)) / 2
    bm = bmesh.new()
    bm.from_mesh(frame.data)
    gone = [f for f in bm.faces
            if all(v.co.z > top for v in f.verts) and min(abs(v.co.x - cx) for v in f.verts) < half]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(frame.data)
    bm.free()
    print("hud_wide_top: %d faces left out" % len(gone))


def main():
    head = subprocess.run(["git", "-C", FG, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if head != PIN:
        raise SystemExit(f"FlightGear F-16 checkout at {head or '?'}, expected {PIN} (git checkout {PIN[:7]})")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = Build()
    b.walk(os.path.join(FG, "Models/Cockpit/Main/cockpit.xml"), Matrix.Identity(4), "Tub")
    altimeter(b)
    root_at = original_root()
    for o in b.parts["Tub"]:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=C @ Vector((TUB_CUT_X, 0, 0)),
                               plane_no=(0, 1, 0), clear_inner=True)
        bm.to_mesh(o.data)
        bm.free()
    # The gear handle (8.6 k triangles) and the throttle turn but are decimated with their consoles; the other turning
    # parts are kept whole.
    decimate_turning = {"controls/gear/gear-down", "controls/engines/engine/throttle-movement"}
    for name, ratio in DECIMATE.items():
        objs = [o for o in b.parts.get(name, []) if o not in b.anims or b.anims[o][0]["prop"] in decimate_turning]
        before = tris(objs)
        for o in objs:
            if len(o.data.polygons) > 40:
                kit.decimate(o, ratio)
        print("decimated %-16s %6d -> %6d" % (name, before, tris(objs)))
    everything = [o for o in kit.scene().objects if o.type == 'MESH']
    fix_materials(everything)
    merge_materials(everything)
    # The rudder pedals are untextured and white in rudder_pedals.ac (FlightGear's effects shade them); black rubber
    # and metal on the jet (the F-16C panel photo, docs/graphics-research.md §3.8).
    # The wide-angle HUD's box is untextured light grey in f16_war_hud.ac; black on the F-16I (the HUDS photo).
    hud_black = kit.material("hud_black", (0.03, 0.03, 0.032), roughness=0.6)
    # The combiner plate's 2 cm rim around the image (HUDedge, opaque "hudGlassEdge" in the .ac): glass, its edge a
    # faint tint as on the photo (a frameless plate), not a black frame.
    hud_edge = kit.material("hud_edge", (0.325, 0.251, 0.075), roughness=0.1, alpha=0.25)
    hud_edge.use_backface_culling = False
    hud_wide_top(b.parts.get("HUDc", []))
    for o in b.parts.get("HUDc", []):
        part = o.name.split("/", 1)[1]
        if part == "HUDedge":
            for i in range(len(o.data.materials)):
                o.data.materials[i] = hud_edge
        elif part not in ("HUDImage2", "HUDImage2.back"):  # all but the glass
            for i in range(len(o.data.materials)):
                o.data.materials[i] = hud_black
    pedal = kit.material("pedal", (0.07, 0.07, 0.075), roughness=0.7)
    for o in b.parts.get("RudderPedals", []):
        for i in range(len(o.data.materials)):
            o.data.materials[i] = pedal
    if os.environ.get("C3D_DEBUG") == "1":  # every object's bounds (Blender frame, before the shift)
        for o in everything:
            vs = [v.co for v in o.data.vertices]
            print("OBJ %-40s %s %s %s" % (o.name, tuple(round(x, 2) for x in map(min, *vs)),
                                          tuple(round(x, 2) for x in map(max, *vs)),
                                          [m.name for m in o.data.materials][:3]))
    for o in everything:
        o.data.transform(Matrix.Translation(SHIFT - root_at))
    # The named nodes the game reads: the MFD screens, their OSBs, the HUD's combiner glass.
    named = {}
    buttons = {}  # the push buttons: drawn in the body, their centres in <out>.json
    for side, part in (("L", "MFD1"), ("R", "MFD2")):
        for o in b.parts.get(part, []):
            n = o.name.split("/", 1)[1]
            if n.startswith("MFDimage"):
                named["MFD_" + side] = o
            elif n.startswith("MFDButton") and n[9:10] in "TBLR" and n[10:].isdigit():
                buttons["MFD_%s_%s" % (side, n[9:])] = o
    button_at = {}
    for name, o in buttons.items():
        vs = [v.co for v in o.data.vertices]
        c = (Vector(map(min, *vs)) + Vector(map(max, *vs))) / 2
        button_at[name] = [round(c.x, 5), round(c.z, 5), round(-c.y, 5)]  # the game's frame (x right, y up, z aft)
    for part, node in HUDS.items():
        for o in b.parts.get(part, []):
            if o.name.endswith("/HUDImage2"):
                named[node + "_glass"] = o
    # The lamps, the displays and the scrolled textures as their own nodes.
    lamps = {}
    for o, rec in b.lamps.items():
        name = "lamp_%s_%d" % (rec["key"], sum(1 for r in lamps.values() if r["key"] == rec["key"]))
        named[name] = o
        lamps[name] = rec
    for o, name in b.displays.items():
        named[name] = o
    for o in b.texanims:
        named[o.name.split("/", 1)[1]] = o
    rest_root = bpy.data.objects.new("f16_cockpit3d", None)
    kit.scene().collection.objects.link(rest_root)
    rest_root.location = root_at
    anims = {}
    static = []
    for o in everything:
        name = next((k for k, v in named.items() if v is o), None)
        if o in b.anims or name is not None:
            vs = [v.co for v in o.data.vertices]
            lo, hi = Vector(map(min, *vs)), Vector(map(max, *vs))
            # A turning part's origin on its first hinge, a named one on its centre (the game reads its place).
            pivot = (Vector(b.anims[o][0]["centre"]) + SHIFT - root_at) if o in b.anims else (lo + hi) / 2
            o.data.transform(Matrix.Translation(-pivot))
            o.location = pivot
            o.parent = rest_root
            o.name = o.data.name = name or "anim%03d" % len(anims)
            if o in b.anims:
                anims[o.name] = [{**r, "centre": list(Vector(r["centre"]) + SHIFT - root_at - pivot),
                                  "axis": list(Vector(r["axis"]).normalized())} for r in b.anims[o]]
        else:
            static.append(o)
    for part, node in HUDS.items():
        objs = [o for o in static if o.name.split("/")[0] == part]
        static = [o for o in static if o not in objs]
        hud = kit.join(objs, node)
        hud.parent = rest_root
    body = kit.join(static, "f16_cockpit3d_body")
    body.parent = rest_root
    # Blender (x right, y forward, z up) -> the game's glTF frame (x right, y up, z aft).
    gl = lambda v: [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]  # noqa: E731
    for recs in anims.values():
        for r in recs:
            r["centre"], r["axis"] = gl(r["centre"]), gl(r["axis"])
    eye = C @ Vector(FG_EYE) + SHIFT - root_at
    textures = {k: b.texanims[v] for k, v in named.items() if v in b.texanims}
    meta = {"source": "FlightGear F-16 " + PIN, "eye": gl(eye), "animations": anims, "buttons": button_at,
            "lamps": lamps, "textures": textures}
    for o in kit.scene().objects:
        o.select_set(o is rest_root or o.parent is rest_root)
    tmp = OUT + ".png.glb"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format='GLB', export_yup=True, use_selection=True,
                              export_apply=True, export_image_format='AUTO')
    glb_ktx2.convert(tmp, OUT)
    os.remove(tmp)
    # The Barak's panel sheet (Block 40) in place of the Block 50 one the model carries (the Sufa's); cockpit3d.gd swaps
    # it in at load.
    img = bpy.data.images.load(os.path.join(FG, "Models/Cockpit/Textures/Block-panels", BARAK_PANELS))
    sc = kit.scene()
    sc.render.image_settings.file_format = 'WEBP'
    sc.render.image_settings.quality = 90
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'
    img.save_render(os.path.join(os.path.dirname(OUT), "barak_panels.webp"), scene=sc)
    json.dump(meta, open(os.path.splitext(OUT)[0] + ".json", "w"), indent=1)
    n = tris([o for o in kit.scene().objects if o.type == 'MESH'])
    print("COCKPIT3D", OUT, "triangles", n, "bytes", os.path.getsize(OUT), "animated", len(anims), "hidden", b.hidden,
          "eye", meta["eye"], "named", sorted(named))


main()
