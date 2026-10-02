# The F-35I's arming screen art (docs/f35i.md): its front view in the arming greens (tools/plane/kit.py
# arm_front_view) and arm.json: the base and max take-off weights, the station boxes (the F-16's positions, the
# original's f-16.trx layout) and where each box's leader line ends on the jet. `iaf-convert arm-extra` composes
# the screen from these and the original arming art on the user's machine (docs/adding-a-plane.md §5).
#
#   blender -b --python tools/f35i/arm_front.py -- <plane dir>      (reads <dir>/f35i.gltf, writes <dir>/arm/)
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402

DIR = sys.argv[sys.argv.index("--") + 1]
# The F-16's art: 9.45 m span across ~430 px, its nose at (227, 160): the F-35I's 10.9 m at the same scale fits.
PX_PER_M, CENTRE = 40.0, (227.0, 160.0)
# F-35I weights (docs/f35i.md §2): empty 29,300 lb + internal fuel 18,250 lb; max take-off 65,918 lb.
BASE_LB, MAX_LB = 47550, 65918
# The station boxes (menu px, top-left of the 51 x 32 box), the F-16's (f-16.trx), stations A..I.
BOXES = [(1, 210), (21, 261), (81, 261), (141, 261), (201, 282), (261, 261), (321, 261), (381, 261), (401, 210)]

pts = kit.arm_front_view(os.path.join(DIR, "f35i.gltf"), os.path.join(DIR, "arm", "front.png"), PX_PER_M, CENTRE)
arm = {"_doc": "F-35I arming screen (tools/f35i/arm_front.py): front.png over the original's arming background "
               "(iaf-convert arm-extra), weights in lb, boxes = top-left of each station's 51x32 box (menu px, "
               "stations A..I), points = where each leader line ends on the jet.",
       "title": "F-35I", "base": BASE_LB, "max": MAX_LB,
       "boxes": [list(b) for b in BOXES],
       "points": [list(pts.get("Station" + c, (0, 0))) for c in "ABCDEFGHI"]}
json.dump(arm, open(os.path.join(DIR, "arm", "arm.json"), "w"), indent=1)
print("ARM", arm["points"])
