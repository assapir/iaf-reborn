# The pilot's body seen from the F-16's 3D cockpit (Modern IAF; docs/cockpit.md "3D cockpit", iaf-2026/docs/cockpit.md):
# FlightGear's `Models/Pilots/pilot_internalview.ac` (github.com/NikolaiVChr/f16 at PIN, GPL-2.0-or-later;
# shared/extra/models/cockpit3d/SOURCES.md), the pilot without head and helmet, legs to the rudder pedals, the right
# hand on the stick and the left on the throttle, in FlightGear's cockpit frame. Placed as tools/f16d/cockpit3d.py
# places the cockpit (FlightGear's model moved SHIFT aft, under a root at the original model's origin), so the game
# hangs it beside f16.glb as is. Its textures as JPEG, the suit's halved.
#
#   blender -b --python tools/f16d/pilot.py -- <FlightGear f16 checkout> \
#       <assets/converted/planes/f16/f16_h.gltf> shared/extra/models/cockpit3d/f16_pilot.glb
import json
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
                          export_image_format='JPEG', export_image_quality=90)
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
print("PILOT", OUT, "triangles", tris, "bytes", os.path.getsize(OUT))
