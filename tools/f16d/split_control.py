# Makes a lever merged into the F-16 3D cockpit's body its own node, for a control FlightGear's model has no object of
# its own in tools/f16d/cockpit3d.py's CONTROLS (modern-iaf/docs/cockpit.md §5.1): the triangles of the body within a
# box (the lever's whole shape, nothing else) leave the body and become node <name> (identity: the body's frame), and
# <model>.json gets its turn about the lever's base. Run after each cockpit3d.py build:
#   python3 -I tools/f16d/split_control.py shared/extra/models/cockpit3d/f16.glb HUD_MODE \
#       0.420,0.140,-3.332,0.430,0.160,-3.323 f16/avionics/hud-brt-switch 25 -25
# (the HUD remote control panel's DAY / AUTO BRT / NIGHT switch: 0 DAY 25° forward, 1 AUTO as modelled, 2 NIGHT 25°
# aft.) Needs numpy.
import json
import struct
import sys

import numpy as np

GLB, NAME, BOX, PROP, FACTOR, OFFSET = sys.argv[1:7]
lo, hi = np.array(BOX.split(","), float).reshape(2, 3)
data = open(GLB, "rb").read()
jn = struct.unpack("<I", data[12:16])[0]
gl = json.loads(data[20:20 + jn])
binc = bytearray(data[20 + jn + 8:])
if any(n.get("name") == NAME for n in gl["nodes"]):
    sys.exit(f"{NAME}: already split")
CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read(i):
    a = gl["accessors"][i]
    v = gl["bufferViews"][a["bufferView"]]
    assert "byteStride" not in v, "interleaved accessor"
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(bytes(binc), CT[a["componentType"]], a["count"] * NC[a["type"]], off).reshape(a["count"], -1)


def append(arr, target, like=None):
    """A new accessor over `arr` at the BIN chunk's end (4-byte aligned); its type and min / max as `like`'s."""
    binc.extend(b"\0" * (-len(binc) % 4))
    gl["bufferViews"].append({"buffer": 0, "byteOffset": len(binc), "byteLength": arr.nbytes, "target": target})
    binc.extend(arr.tobytes())
    a = {"bufferView": len(gl["bufferViews"]) - 1, "count": len(arr),
         "componentType": {np.float32: 5126, np.uint16: 5123, np.uint32: 5125}[arr.dtype.type],
         "type": like["type"] if like else "SCALAR"}
    if like and "min" in like:
        a["min"], a["max"] = arr.min(0).tolist(), arr.max(0).tolist()
    gl["accessors"].append(a)
    return len(gl["accessors"]) - 1


body = next(n for n in gl["nodes"] if n.get("name") == "f16_cockpit3d_body")
prims = []
for p in gl["meshes"][body["mesh"]]["primitives"]:
    pos = read(p["attributes"]["POSITION"])
    idx = read(p["indices"]).reshape(-1, 3)
    inside = np.all((pos >= lo) & (pos <= hi), axis=1)[idx].all(axis=1)
    if not inside.any():
        continue
    # The body keeps the rest, written over its own index view (the tail unused).
    keep = idx[~inside].ravel().astype(read(p["indices"]).dtype)
    a = gl["accessors"][p["indices"]]
    v = gl["bufferViews"][a["bufferView"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    binc[off:off + keep.nbytes] = keep.tobytes()
    a["count"] = len(keep)
    # The lever's own vertices (every attribute), its triangles renumbered.
    used, tri = np.unique(idx[inside].ravel(), return_inverse=True)
    attrs = {k: append(np.ascontiguousarray(read(i)[used]), 34962, gl["accessors"][i]) for k, i in p["attributes"].items()}
    prims.append({"attributes": attrs, "indices": append(tri.astype(np.uint16), 34963), "material": p["material"]})
    lever = read(p["attributes"]["POSITION"])[used]
if not prims:
    sys.exit(f"{NAME}: no triangles inside {BOX}")
gl["meshes"].append({"name": NAME, "primitives": prims})
gl["nodes"].append({"name": NAME, "mesh": len(gl["meshes"]) - 1})
root = next(n for n in gl["nodes"] if body is not n and gl["nodes"].index(body) in n.get("children", []))
root["children"].append(len(gl["nodes"]) - 1)
gl["buffers"][0]["byteLength"] = len(binc)
# The turn: about the lever's base (its lowest tenth's centre), the axis across the shaft and the console (x), so a
# positive angle swings the tip aft (+z).
lever = lever.astype(float)
base = lever[lever[:, 1] <= lever[:, 1].min() + 0.1 * np.ptp(lever[:, 1])].mean(0)
shaft = lever.mean(0) - base
axis = np.cross(shaft, [0.0, 0.0, 1.0])
axis /= np.linalg.norm(axis)
meta_path = GLB[:-4] + ".json"
meta = json.load(open(meta_path))
meta["animations"][NAME] = [{"prop": PROP, "factor": float(FACTOR), "offset": float(OFFSET),
                             "centre": base.round(5).tolist(), "axis": axis.round(5).tolist()}]
js = json.dumps(gl, separators=(",", ":")).encode()
js += b" " * (-len(js) % 4)
binc.extend(b"\0" * (-len(binc) % 4))
out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binc))
out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(binc), 0x004E4942) + bytes(binc)
open(GLB, "wb").write(out)
open(meta_path, "w").write(json.dumps(meta, indent=1))
print(f"{NAME}: {sum(len(read(p['indices'])) // 3 for p in prims)} triangles, base {base.round(4)}, axis {axis.round(3)}")
