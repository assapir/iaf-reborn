# The F-16 3D cockpit's CMDS panel knobs (modern-iaf/docs/cockpit.md §5.13), run after each tools/f16d/cockpit3d.py build
# (and after split_control.py's):
#   python3 -I tools/f16d/cmds_knobs.py shared/extra/models/cockpit3d/f16.glb
# - PRGM: FlightGear's Block 50 panel paints the PRGM knob (BIT, 1, 2, 3, 4) but models no knob over it. The node
#   PRGM_50_knob is the MODE knob's mesh (the same pointer knob, shared) moved onto the painted one: 87.5 px of the
#   panel sheet (panels-B50-left_right-aux-consoles.png: the painted MODE knob centred at 473.5, 671 px, the PRGM knob
#   at 386, 671) along the sheet's u, mapped through the CMDS panel plate's UVs (its quad in the body: 0.357 mm a
#   px). It turns on f16/ews/prgm-knob (1-4: the CMDS's programs) to the panel's painted marks (measured on the
#   sheet, from the panel's top: BIT -89°, 1 -57°, 2 -22°, 3 +25°, 4 +58°; the MODE knob's measured the same way
#   within 2°). Its stops are 1 to 4; BIT, the built-in test, is a painted mark (the sim's CMDS has no test).
# - MODE: FlightGear turns it 60° a step, its marks are 30° apart (OFF at -90° ... BYP at +60°): 30° a step here, and
#   all six positions (FlightGear's binding stops at 2, MAN).
# The knob's mesh as modelled points at +30° (the paint's AUTO): the PRGM node is turned to its mark 1 (unset, as in the
# 1998 game's cockpit, it shows program 1), its turns counted from there.
# Needs numpy.
import json
import struct
import sys

import numpy as np

GLB = sys.argv[1]
SRC, NAME, PROP = "MODE_50_knob", "PRGM_50_knob", "f16/ews/prgm-knob"
MOVE = [-0.03126, 0.00555, 0.00400]  # the 87.5 px along u, in the cockpit's frame (m)
MARKS = {1: -57.0, 2: -22.0, 3: 25.0, 4: 58.0}
data = open(GLB, "rb").read()
jn = struct.unpack("<I", data[12:16])[0]
gl = json.loads(data[20:20 + jn])
binc = data[20 + jn:]  # the BIN chunk with its header, unchanged
nodes = gl["nodes"]
if any(n.get("name") == NAME for n in nodes):
    sys.exit(f"{NAME}: already there")
i = next(k for k, n in enumerate(nodes) if n.get("name") == SRC)
src = nodes[i]
meta_path = GLB[:-4] + ".json"
meta = json.load(open(meta_path))
turn = meta["animations"][SRC][0]
half = np.radians(MARKS[1] - 30.0) / 2
q = np.r_[np.array(turn["axis"]) / np.linalg.norm(turn["axis"]) * np.sin(half), np.cos(half)]
nodes.append({"name": NAME, "mesh": src["mesh"], "rotation": q.tolist(),
              "translation": (np.array(src["translation"]) + MOVE).tolist()})
next(n for n in nodes if i in n.get("children", []))["children"].append(len(nodes) - 1)
turn.update(factor=30.0, offset=-120.0)
meta["controls"][SRC].update(max=5.0, modelled=4.0)  # the mesh as modelled points at AUTO
meta["animations"][NAME] = [{"prop": PROP, "table": [[float(v), a - MARKS[1]] for v, a in MARKS.items()],
                             "centre": turn["centre"], "axis": turn["axis"]}]
meta["controls"][NAME] = {"prop": PROP, "mode": "cycle", "min": 1.0, "max": 4.0, "step": 1.0, "wrap": True,
                          "modelled": 1.0}
js = json.dumps(gl, separators=(",", ":")).encode()
js += b" " * (-len(js) % 4)
out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + len(binc))
out += struct.pack("<II", len(js), 0x4E4F534A) + js + binc
open(GLB, "wb").write(out)
open(meta_path, "w").write(json.dumps(meta, indent=1))
print(f"{NAME}: at {nodes[-1]['translation']}")
