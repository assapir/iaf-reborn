# The pilot's body seen from the F-16's 3D cockpit (Modern IAF; docs/cockpit.md "3D cockpit", modern-iaf/docs/cockpit.md):
# FlightGear's `Models/Pilots/pilot_internalview.ac` (github.com/NikolaiVChr/f16 at PIN, GPL-2.0-or-later;
# shared/extra/models/cockpit3d/SOURCES.md), the pilot without head and helmet, legs to the rudder pedals, the right
# hand on the stick and the left on the throttle, in FlightGear's cockpit frame. Placed as tools/f16d/cockpit3d.py
# places the cockpit (FlightGear's model moved SHIFT aft, under a root at the original model's origin), so the game
# hangs it beside f16.glb as is. Its textures as JPEG, the suit's halved.
#
#   blender -b --python tools/f16d/pilot.py -- <FlightGear f16 checkout> \
#       <assets/converted/planes/f16/f16_h.gltf> shared/extra/models/cockpit3d/f16_pilot.glb
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "plane"))
import kit  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

FG, ORIG, OUT = sys.argv[sys.argv.index("--") + 1:][:3]
PIN = "ef4f192f06243cf4061c2be794511db0576ac2f9"  # cockpit3d.py's
SHIFT = Vector((0.0, -1.05, 0.0))  # cockpit3d.py's

head = subprocess.run(["git", "-C", FG, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
if head != PIN:
    raise SystemExit(f"FlightGear F-16 checkout at {head or '?'}, expected {PIN}")
bpy.ops.wm.read_factory_settings(use_empty=True)
g = json.load(open(ORIG))
n = g["nodes"][g["scenes"][0]["nodes"][0]]
t = n["matrix"][12:15] if "matrix" in n else n.get("translation", (0, 0, 0))
root_at = Vector((t[0], -t[2], t[1]))  # cockpit3d.py original_root
objs = list(kit.import_ac(os.path.join(FG, "Models/Pilots/pilot_internalview.ac"), prefix="pilot/").values())
body = kit.join(objs, "pilot_body")
body.data.transform(Matrix.Translation(SHIFT - root_at))
# The left glove on the throttle's grip (the Mac play test's finding 12). FlightGear posed it for its own grip turned
# about 28° aft (the throttle near idle), 4 cm inboard of the grip and 3 cm over it. The forearm and glove turn about
# the throttle's pivot to the grip's rest pose (the model's mid throttle) and move onto the grip, fading in from the
# elbow (no turn) to the wrist (all of it). Shape keys `throttle_idle` / `throttle_full` turn them on by the grip's
# travel either way (TRAVEL_DEG), so the glove follows the grip (cockpit3d.gd _pilot_throttle). Godot's frame (y up,
# −z forward) below; THR_PIVOT is f16.glb's THROTTLE node.
THR_PIVOT = Vector((-0.491, 0.119, -3.239))
REST_DEG = -28.0
# The palm centred over the grip's head (2026-11-13: x −0.08 → −0.055, y −0.05 → −0.04; at −0.08 the glove lay on the
# console outboard of the head).
NUDGE = Vector((-0.055, -0.04, 0.045))
TRAVEL_DEG = 40.0  # f16.json's THROTTLE: 40 − 80 · throttle


def godot_of(co):
    w = co + root_at
    return Vector((w.x, w.z, -w.y))


def co_of(g):
    return Vector((g.x, -g.z, g.y)) - root_at


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def arm_weight(g):
    """The left forearm and glove: 0 at the elbow, 1 from the wrist on; faded out inboard (the thigh's edge, |x| ≤ 0.22
    under y 0.23), below (the thigh) and above (the upper arm, y ≥ 0.45)."""
    return (smooth(-2.80, -3.10, g.z) * smooth(-0.17, -0.20, g.x) * smooth(0.21, 0.25, g.y)
            * (1.0 - smooth(0.40, 0.46, g.y)))


def turn(g, deg):
    """`g` turned about the throttle's pivot, + aft (the grip toward idle), as Godot's Basis(X, deg)."""
    return THR_PIVOT + Matrix.Rotation(math.radians(deg), 3, "X") @ (g - THR_PIVOT)


arm = [(v, arm_weight(godot_of(v.co))) for v in body.data.vertices]
for v, w in arm:
    if w > 0.0:
        v.co = co_of(turn(godot_of(v.co), REST_DEG * w) + NUDGE * w)
hand = [godot_of(v.co) for v, w in arm if w > 0.99]
print("PILOT left glove centre", sum(hand, Vector()) / max(len(hand), 1), "vertices", len(hand))
# The right glove on the side-stick's grip (the user, 2026-11-13: "hands still not on stick"). FlightGear's cockpit
# leaves this pilot out (Models/Cockpit/Main/cockpit.xml has it commented out), so nothing posed it for the current
# stick: its fist closed 9 cm ahead of the grip and 2 cm inboard. The forearm and glove move onto the grip whole; the
# upper arm takes up the move, fading from the elbow (all of it) to the shoulder (none), and leans back a little.
STICK_NUDGE = Vector((0.018, -0.012, 0.09))


def stick_arm_weight(g):
    """The right forearm and glove: 1 up to the elbow's height, faded out up the upper arm (y 0.40-0.58), inboard (the
    right thigh and knee, x ≤ 0.22) and aft (the torso, z ≥ -2.90)."""
    return smooth(0.22, 0.235, g.x) * smooth(-2.85, -2.95, g.z) * (1.0 - smooth(0.40, 0.58, g.y))


right = 0
for v in body.data.vertices:
    w = stick_arm_weight(godot_of(v.co))
    if w > 0.0:
        v.co = co_of(godot_of(v.co) + STICK_NUDGE * w)
        right += 1
print("PILOT right arm vertices moved", right)
body.shape_key_add(name="Basis", from_mix=False)
for name, deg in (("throttle_idle", TRAVEL_DEG), ("throttle_full", -TRAVEL_DEG)):
    key = body.shape_key_add(name=name, from_mix=False)
    for v, w in arm:
        if w > 0.0:
            key.data[v.index].co = co_of(turn(godot_of(v.co), deg * w))
# Cloth and rubber, not FlightGear's 0.5 sheen; named for cockpit3d.gd's dim fill. Two-sided: some of the chest's and
# belly's single-sided faces face inward, and from the eye the tub's black floor showed through them.
for m in body.data.materials:
    m.name = "pilot_" + m.name
    m.use_backface_culling = False
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Roughness"].default_value = 0.85
# The suit's sheet (Tex_0008_1, 2048 x 4096) halved: the legs and arms are 0.4-1 m from the eye. The harness and vest
# sheet (Tex_0004_1, 2048 x 2048) kept whole: the vest's pads are 0.2 m under the eye.
for img in bpy.data.images:
    if img.size[1] > 2048:
        img.scale(img.size[0] // 2, img.size[1] // 2)
root = bpy.data.objects.new("f16_pilot", None)
kit.scene().collection.objects.link(root)
root.location = root_at
body.parent = root
for o in kit.scene().objects:
    o.select_set(o is root or o.parent is root)
# JPEG, not KTX2: at the vest's 8x magnification Basis Universal's 4 x 4 blocks (ETC1S and UASTC alike) showed as
# blotches of green and grey-blue the size of a thumb.
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, use_selection=True, export_apply=True,
                          export_morph=True, export_image_format='JPEG', export_image_quality=90)
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
print("PILOT", OUT, "triangles", tris, "bytes", os.path.getsize(OUT))
