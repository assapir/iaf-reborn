# The F-35I canopy's frame and bow (docs/f35i.md §4.1 "Canopy"), seen from outside: canopy_frame.glb beside f35i.gltf,
# which the game puts on the canopy part (aircraft.json parts.canopy.attach, aircraft_model.gd), so it opens with it.
# Built on f35i.gltf's own canopy (tools/f35i/rig.py), in its frame, from rays out of the canopy's axis (AXIS_Z):
#   - the frame (kit.canopy_frame): a solid FRAME_D deep on the glass from FRAME_H above where the airframe hides it
#     (FRONT_H over the front FRONT_LEN) down to the glass's own edge, the whole rear end over its last AFT_W, painted
#     as the airframe and standing FRAME_OFF proud of the glass (the photos: a broad painted frame round the glass's
#     foot, broadest at the front corners, and round its rear end; raised, the lid's lower sides opaque; the widths
#     inferred);
#   - the bow: a dark band inside the glass from sill to sill over the top, on the seam where the model's two
#     transparencies meet (SEAM_*), leaning forward to its top (the photos: a dark arch ahead of the pilot's face).
#
#   blender -b --python tools/f35i/canopy_frame.py -- shared/extra/planes/f35i
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402

DIR = sys.argv[sys.argv.index("--") + 1]
FRAME_H, FRONT_H, FRONT_LEN, AFT_W, FRAME_OFF, FRAME_D = 0.15, 0.28, 0.6, 0.55, 0.004, 0.025
# The download's glass runs on down to 1.3 m inside the airframe (0.4 m at mid-canopy): raised, it hung under the
# frame as bare sheets. The glass is cut GLASS_IN past where the airframe hides it (canopy_glass, written here; the
# part's own mesh gives way to it, aircraft.json parts.canopy.attach_replaces) and the frame reaches FRAME_IN past it.
GLASS_IN, FRAME_IN = 0.08, 0.11
AXIS_Z = -0.15  # the rays' origin over the centre line, in the canopy's frame (Blender: +y nose, z up)
# The seam fore and aft at the sill and at the top (f35i.gltf: an open slot between the front transparency's rear edge
# and the rear one's front edge, 0.57 m ahead of the eye at the sill, 0.73 m at the top; the glass's face there the
# mean of SEAM_GAP ahead and behind).
SEAM_FOOT, SEAM_TOP, SEAM_GAP = 0.13, 0.29, 0.07
BOW = kit.rounded_rect(0.015, 0.07, 0.006)  # 1.5 cm deep, 7 cm wide fore and aft
BOW_IN = 0.011  # its middle under the glass's outer face
# The airframe's grey as rendered beside it (rig.py's SKIN_GREY (0.37, 0.39, 0.41) under its baked shade), a shade
# darker so the frame reads against the airframe's lit grey and the tinted glass (0.20, 0.22, 0.26 until 2026-11-14).
PAINT = (0.13, 0.14, 0.16)
STEP_Y, SMOOTH = 0.03, 5


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def tree(obj, into):
    """obj's mesh as a BVH tree in `into`'s frame."""
    m = into.matrix_world.inverted() @ obj.matrix_world
    return BVHTree.FromPolygons([m @ v.co for v in obj.data.vertices], [p.vertices[:] for p in obj.data.polygons])


def canopy_glass(can, body):
    """The canopy's glass without what lies more than GLASS_IN inside the airframe (seen from straight outside, from
    the axis), a copy in the canopy's frame."""
    me = can.data.copy()
    hidden = []
    for v in me.vertices:
        d = v.co - Vector((0.0, v.co.y, AXIS_Z))
        d = d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))
        hidden.append(body.ray_cast(v.co + d * 1.5, -d, 1.49)[0] is not None)
    seen = [v.co for v, h in zip(me.vertices, hidden) if not h]
    kd = KDTree(len(seen))
    for i, c in enumerate(seen):
        kd.insert(c, i)
    kd.balance()
    deep = [h and kd.find(v.co)[2] > GLASS_IN for v, h in zip(me.vertices, hidden)]
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(deep[v.index] for v in f.verts)], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(me)
    bm.free()
    cut = bpy.data.objects.new("canopy_glass", me)
    kit.scene().collection.objects.link(cut)
    return cut


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(DIR, "f35i.gltf"))
    can = bpy.data.objects["canopy"]
    glass = tree(can, can)
    body = tree(bpy.data.objects["f35i"], can)
    ys = [v.co.y for v in can.data.vertices]
    y0, y1 = min(ys), max(ys)

    # The frame: one solid on the glass (kit.canopy_frame), from FRAME_H above where the airframe starts to hide the
    # glass down to the glass's own edge, so the glass inside the airframe when shut is frame with the canopy up.
    paint = kit.material("canopy_frame_paint", PAINT, roughness=0.75)
    paint.use_backface_culling = False
    frame = kit.canopy_frame(
        "canopy_frame_ext", paint, glass, AXIS_Z, list(np.arange(y0 + 0.005, y1, STEP_Y)),
        lambda y: FRAME_H + (FRONT_H - FRAME_H) * smooth((y - y1 + FRONT_LEN) / FRONT_LEN),
        off=FRAME_OFF, depth=FRAME_D, body=body, below=FRAME_IN, aft_w=AFT_W, smooth_n=SMOOTH)
    cut = canopy_glass(can, body)
    me = frame.data

    # The bow: the seam's section from sill to sill over the top, BOW_IN under the glass's face.
    path = []
    o_at = {}
    for a_i in range(-90, 91, 3):
        a = math.radians(a_i)
        y = SEAM_FOOT + (SEAM_TOP - SEAM_FOOT) * math.cos(a)
        o_at[a_i] = y
    secs = {}
    for a_i, y in o_at.items():
        sec = secs.setdefault(round(y, 3), kit.canopy_section(glass, y, AXIS_Z, body, SEAM_GAP))
        side = 1 if a_i >= 0 else -1
        pts = sec[side][0][:sec[side][1]]  # the visible glass
        if not pts:
            continue
        foot_a = pts[-1][0]
        want = abs(math.radians(a_i)) / (math.pi / 2) * foot_a  # 0 at the top, the sill at +-90
        _a, p = min(pts, key=lambda q: abs(q[0] - want))
        o = Vector((0.0, y, AXIS_Z))
        path.append(tuple(p - (p - o).normalized() * BOW_IN))
    bow = kit.sweep("canopy_bow_ext", kit.material("canopy_bow_ext", (0.012, 0.012, 0.014), roughness=0.8), BOW, path,
                    ref=(0, 1, 0))

    # Both built in the canopy's own frame (the glb's origin on the part's), written alone.
    kit.deselect()
    for o in (frame, bow, cut):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(DIR, "canopy_frame.glb"), export_format='GLB', export_yup=True,
                              use_selection=True, export_apply=True, export_lights=False, export_cameras=False)
    print("CANOPY_FRAME", len(path), "bow points", len(me.polygons), "frame faces", len(can.data.polygons), "->",
          len(cut.data.polygons), "glass faces")


main()
