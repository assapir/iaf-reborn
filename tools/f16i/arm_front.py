# The F-16I Sufa's arming screen art (docs/f16i.md §8): its front view in the arming greens (tools/plane/kit.py
# arm_front_view) and arm.json: the base and max take-off weights, the F-16's station boxes (the original's f-16.trx
# layout) and where each box's leader line ends on the jet. `iaf-convert arm-extra` composes the screen from these and
# the original arming art on the user's machine (docs/adding-a-plane.md §5); the Arming screen shows it for every
# F-16 with the Extras switch "F-16 version" on Sufa.
#
#   F16D_KEEP_PNG=1 blender -b --python tools/f16d/rig.py -- <FlightGear f16> <f16_h.gltf> /tmp/f16i.glb sufa
#   blender -b --python tools/f16i/arm_front.py -- /tmp/f16i.glb.png.glb game/extra/planes/f16i/arm
#
# (Blender reads the rig's glb before its KTX2 pass, not f16i.glb.)
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402

GLB, OUT = sys.argv[sys.argv.index("--") + 1:][:2]
# The original F-16 art's scale and place: its wingtip rails ~430 px apart, its wing at y ~148.
PX_PER_M, CENTRE = 45.5, (227.0, 154.0)
# Weights (lb): the F-16's base 27,600 + 1,400 heavier empty + 3,050 CFT fuel; max take-off 52,000 (docs/f16i.md §1).
BASE_LB, MAX_LB = 32050, 52000
# The station boxes (menu px, top-left of the 51 x 32 box), the F-16's (f-16.trx), stations A..I.
BOXES = [(1, 210), (21, 261), (81, 261), (141, 261), (201, 282), (261, 261), (321, 261), (381, 261), (401, 210)]

os.makedirs(OUT, exist_ok=True)
pts = kit.arm_front_view(GLB, os.path.join(OUT, "front.png"), PX_PER_M, CENTRE)
arm = {"_doc": "F-16I Sufa arming screen (tools/f16i/arm_front.py): front.png over the original's arming background "
               "(iaf-convert arm-extra), weights in lb, boxes = top-left of each station's 51x32 box (menu px, "
               "stations A..I), points = where each leader line ends on the jet.",
       "title": "F-16I", "base": BASE_LB, "max": MAX_LB,
       "boxes": [list(b) for b in BOXES],
       "points": [list(pts.get("Station" + c, (0, 0))) for c in "ABCDEFGHI"]}
json.dump(arm, open(os.path.join(OUT, "arm.json"), "w"), indent=1)
print("ARM", arm["points"])
