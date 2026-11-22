# The enemy models (shared/extra/models/<id>/<id>.glb, docs/ai.md §15.4 and §16): each Sketchfab download (CC BY 4.0,
# assets/source/enemy_models/<zip>, the user's own download of 22 Nov 2026) cut to what the game draws, scaled to the
# real vehicle, turned nose along -Z (glTF) on the ground at its middle, joined into one mesh per material, decimated
# and its textures shrunk for the Iris Xe; its license.txt copied beside it. Run once by hand, then committed (setup
# never fetches them: they sit behind a Sketchfab login):
#
#   blender -b --factory-startup -P tools/enemy_models/convert.py -- assets/source/enemy_models shared/extra/models
import math
import os
import shutil
import struct
import sys
import tempfile
import zipfile

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
from glb_ktx2 import read_glb, write_glb  # noqa: E402

# id: (zip, the real size (axis, metres), decimate ratio, the turn (degrees about up) that puts the nose on +Y
# (Blender), the largest texture side, a mesh to cut when its middle lies farther than this from the middle across).
MODELS = {
    # MAZ-543 width 3.05 m (ru.wikipedia), the 5P85S / D's chassis.
    "s300_5p85": ("s-300_5p85_launcher_with_9m83_missiles.zip", ("x", 3.05), 0.15, 0.0, 1024, 1.9),
    # The 30N6E's antenna on the 40V6M tower at 25 m, the site's MAST (crates/iaf-ai/src/site.rs; inferred from the
    # 40V6M's "24 metre", ausairpower), taken as the model's whole height.
    "radar_30n6e": ("30n6e_flap_lid_b_phased_array_radar.zip", ("z", 25.0), 1.0, 0.0, 1024, None),
    # Tor-M1 length 7.5 m (Wikipedia).
    "tor_m1": ("tor-m1_sam_with_9m331_missiles_animated.zip", ("y", 7.5), 0.25, 0.0, 1024, 2.0),
    # ZSU-23-4 length 6.535 m (Wikipedia).
    "zsu23_4": ("lowpoly_zsu-23-4.zip", ("y", 6.535), 0.35, 0.0, 512, None),
    # Shahed-136 length 3.5 m (Wikipedia, docs/ai.md §16).
    "shahed136": ("shahed_136.zip", ("y", 3.5), 0.3, 180.0, 512, None),
    # T-72 height 2.23 m (Wikipedia); the source stands yawed 30 degrees, its turret traversed and its gun raised.
    "t72": ("low_poly_t-72_tank_-_game_ready.zip", ("z", 2.23), 1.0, 30.0, 512, None),
    # Ural-4320 length 7.366 m (Wikipedia).
    "ural4320": ("ural_4320.zip", ("y", 7.366), 1.0, 180.0, 1024, None),
}
BIG = 1500
# Parts cut by name: the S-300's spare 9M83 hidden inside the chassis at the origin, the T-72's helper sphere.
DROP = {"s300_5p85": ("Object_4",), "t72": ("Icosphere",)}
# Big parts kept whole: the S-300's frame behind the cab (thin bars).
WHOLE = {"s300_5p85": ("Object_26",)}


def strip_jpeg(d):
    """The JPEG without its comments and ICC profile (APP2): Godot 4.7's loader refuses Blender's profile."""
    out, i = bytearray(d[:2]), 2
    while d[i + 1] != 0xDA:
        n = struct.unpack(">H", d[i + 2:i + 4])[0]
        if d[i + 1] not in (0xE2, 0xFE):
            out += d[i:i + 2 + n]
        i += 2 + n
    return bytes(out + d[i:])


def clean_images(path):
    doc, blob = read_glb(path)
    views = doc["bufferViews"]
    chunks = [bytes(blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]) for v in views]
    for im in doc.get("images", []):
        if im.get("mimeType") == "image/jpeg":
            chunks[im["bufferView"]] = strip_jpeg(chunks[im["bufferView"]])
    write_glb(path, doc, chunks)


def bounds(objs):
    ws = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return Vector([min(w[i] for w in ws) for i in range(3)]), Vector([max(w[i] for w in ws) for i in range(3)])


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def convert(mid, src_dir, out_root):
    zname, (axis, real), ratio, turn, side, cut = MODELS[mid]
    tmp = tempfile.mkdtemp()
    with zipfile.ZipFile(os.path.join(src_dir, zname)) as z:
        z.extractall(tmp)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(tmp, "scene.gltf"))
    bpy.context.view_layer.update()
    # The display props beside the vehicle (a spare missile, a reload rack) go.
    for o in meshes():
        if o.name in DROP.get(mid, ()):
            bpy.data.objects.remove(o)
    if cut is not None:
        for o in meshes():
            a, b = bounds([o])
            if abs((a.x + b.x) / 2) > cut:
                bpy.data.objects.remove(o)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    # Every mesh in world space, then one object; one UV map each (the join keeps every name as its own map).
    objs = meshes()
    for o in objs:
        uv = o.data.uv_layers
        while len(uv) > 1:
            uv.remove(uv[-1])
        if len(uv):
            uv[0].name = "UVMap"
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Each part's flat faces merged (lossless: one polygon per plane, the UV seams kept); a big part (over BIG
    # triangles: the hull, the wheels) collapsed to `ratio`, the small ones (barrels, antennas, rails) left whole, as
    # a collapse turns a thin part into scattered points.
    for o in objs:
        m = o.modifiers.new("planar", "DECIMATE")
        m.decimate_type = "DISSOLVE"
        m.angle_limit = math.radians(0.5)
        m.delimit = {"UV", "MATERIAL", "SHARP"}
        if ratio < 1.0 and o.name not in WHOLE.get(mid, ()) and sum(len(p.vertices) - 2 for p in o.data.polygons) > BIG:
            o.modifiers.new("collapse", "DECIMATE").ratio = ratio
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o != body:
            bpy.data.objects.remove(o)
    body.name = mid
    body.data.transform(Matrix.Rotation(math.radians(turn), 4, "Z"))
    mn, mx = bounds([body])
    k = real / (mx - mn)["xyz".index(axis)]
    # The origin at the middle of the footprint (the lowest quarter: wheels, tracks, the mast's feet; a traversed
    # gun or a raised antenna does not shift it), on the ground.
    low = [v.co for v in body.data.vertices if v.co.z < mn.z + 0.25 * (mx.z - mn.z)]
    foot = Vector([(min(v[i] for v in low) + max(v[i] for v in low)) / 2 for i in range(2)] + [mn.z])
    body.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-foot))
    body.matrix_world = Matrix.Identity(4)
    for im in bpy.data.images:
        if im.size[0] > side or im.size[1] > side:
            f = side / max(im.size)
            im.scale(max(1, round(im.size[0] * f)), max(1, round(im.size[1] * f)))
    out = os.path.join(out_root, mid)
    os.makedirs(out, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out, mid + ".glb"),
        export_format="GLB",
        export_image_format="JPEG",
        export_jpeg_quality=85,
        export_animations=False,
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
    )
    clean_images(os.path.join(out, mid + ".glb"))
    shutil.copy(os.path.join(tmp, "license.txt"), os.path.join(out, "license.txt"))
    mn, mx = bounds([body])
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("MODEL", mid, "scale %.4f" % k, "size", [round(v, 2) for v in mx - mn], "tris", tris)
    shutil.rmtree(tmp)


args = sys.argv[sys.argv.index("--") + 1:]
for mid in args[2:] or MODELS:
    convert(mid, args[0], args[1])
