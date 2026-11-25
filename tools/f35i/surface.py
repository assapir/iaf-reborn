# The F-35I's skin as a surface (docs/f35i.md §5.1): the coating's matte grey with a faint tone drift, and only the
# panel lines, saw-tooth doors and lighter edging photos of real F-35Is show (FEATURES), written into the skin's colour
# texture and into a normal map and a roughness map per skin texture, all our own; also the fins' formation strips
# made pale and unlit by day. Runs once on rig.py's output (the skin textures as rig.py baked them; it refuses a model
# it already did):
#
#   blender -b --python tools/f35i/surface.py -- shared/extra/planes/f35i
#
# Every texel's world position and normal are baked from the model (Cycles, emission), so the pattern follows the
# airframe across the UV islands; FEATURES are laid out on the jet's top, bottom and sides from those.
import json
import os
import sys

import bmesh
import bpy
import numpy as np

DIR = sys.argv[sys.argv.index("--") + 1]
MODELS = ("f35i.gltf", "f35i_bc.gltf")  # the cockpit view's model shares the skin textures and UVs
COAT = (0.32, 0.335, 0.36)  # the coating's grey, sRGB (photos of IAF F-35Is by day, docs/f35i.md §5.1)
RIG_GREY = (0.37, 0.39, 0.41)  # rig.py's SKIN_GREY: the grey its baked shading was made on
ROUGH = 0.6  # a matte coating: broad, soft highlights
SPECULAR = 0.25  # its reflectance, half a paint's: no white sky glare along the spine at a low angle (photos)
SEAM_W = 0.004  # m, half width of a panel line (drawn at least 1.2 texels wide)
TAPE_W = 0.045  # m, half width of the lighter edging (RAM tape / sealant) along a door's edge
TOOTH = 0.11  # m, the pitch of a door's saw-tooth
TOOTH_AMP = 0.03  # m, their depth
# The fins' formation ("slime") light strips, two layers in the download, both lit green: real ones are
# electroluminescent panels, a pale grey-green barely seen by day (photos), lit only at night.
LIGHT_STRIPS = {"Glowing_green": [0.004, 0.02, 0.004], "Grey": [0.0, 0.0, 0.0]}
STRIP_COLOUR = (0.28, 0.34, 0.22, 1.0)  # linear
ENC = 0.02  # the position bake's scale (m -> 0..1 round 0.5)

# The panel lines and edging real F-35Is show (docs/f35i.md §5.1), in metres in the model's frame (x right, y forward,
# z up), for the jet's right side and mirrored to the left. A view picks the texels it draws on by their normal: "top"
# and "bottom" are (x, y) seen from above, "side" is (y, z). Kinds: "line" a panel line (an open polyline); "door" a
# panel line with saw-tooth edges and a lighter band astride it (RAM tape / sealant); "patch" a lighter filled shape.
# Positions are read off the photos against the model's top, side and bottom views.
def _rect(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def _diamond(x, y, a, b):
    return [(x, y + a), (x + b, y), (x, y - a), (x - b, y)]


FEATURES = [
    # Upper wing: the leading-edge flap's hinge line and the flaperon's (the flight photos).
    ("top", "line", [(2.23, 0.63), (5.42, -1.70)]),
    ("top", "line", [(2.2, -2.73), (4.38, -2.73), (4.38, -3.06)]),
    # The spine: the air-refuelling door behind the canopy and the auxiliary inlet doors (2016 flight photo).
    ("top", "door", _rect(-0.2, 2.15, 0.2, 2.7)),
    ("top", "door", _rect(0.3, 1.0, 0.72, 1.65)),
    # Lower wing: the same hinge lines, and the lighter lens-shaped access patches (116 Sqn pair from below).
    ("bottom", "line", [(2.23, 0.63), (5.42, -1.70)]),
    ("bottom", "line", [(2.2, -2.73), (4.38, -2.73), (4.38, -3.06)]),
    ("bottom", "patch", _diamond(2.9, -0.35, 0.2, 0.09)),
    ("bottom", "patch", _diamond(3.35, -1.0, 0.22, 0.1)),
    ("bottom", "patch", _diamond(3.95, -1.5, 0.2, 0.09)),
    ("bottom", "patch", _diamond(2.85, -1.9, 0.25, 0.1)),
    ("bottom", "patch", _diamond(4.6, -2.15, 0.18, 0.08)),
    ("bottom", "patch", _diamond(3.6, -2.45, 0.2, 0.09)),
    # The belly: each weapon bay's two doors with saw-tooth ends, the main gear doors (Red Flag and flight photos).
    ("bottom", "door", _rect(0.4, -2.4, 0.95, 1.8)),
    ("bottom", "door", _rect(0.95, -2.4, 1.5, 1.8)),
    ("bottom", "door", _rect(1.8, -2.3, 2.4, -0.45)),
    # The fuselage side: the hexagonal panel behind the intake with its lighter edging, the panel line under the
    # chine (116 Sqn's 930).
    ("side", "door", [(0.45, 0.0), (0.25, 0.2), (-0.45, 0.2), (-0.65, 0.0), (-0.45, -0.2), (0.25, -0.2)]),
    ("side", "line", [(1.2, -0.3), (-3.2, -0.3)]),
]
VIEWS = {"top": 0, "bottom": 1, "side": 2}


def h(*k):
    """A hash of integer arrays to [0, 1)."""
    x = np.uint64(1469598103934665603)
    for v in k:
        x = (x ^ np.asarray(v).astype(np.int64).astype(np.uint64)) * np.uint64(1099511628211)
        x ^= x >> np.uint64(29)
    return (x % np.uint64(1 << 20)).astype(np.float64) / float(1 << 20)


def tri(x):
    """A triangle wave of period 1, from 0 to 1."""
    return 1.0 - np.abs(2.0 * (x - np.floor(x)) - 1.0)


def noise(p, scale, seed):
    """Smooth value noise in 3D, [0, 1)."""
    q = p / scale
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (
                    f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * h(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz, seed)
    return out


def bake(objs, images, socket):
    """Bakes the shading `socket` ("Position" or "Normal") of every skin material into its float image."""
    for mat, img in images.items():
        nt = mat.node_tree
        for n in [n for n in nt.nodes if n.name.startswith("srf_")]:
            nt.nodes.remove(n)
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        geo.name = "srf_geo"
        em = nt.nodes.new("ShaderNodeEmission")
        em.name = "srf_em"
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        out.name = "srf_out"
        out.target = 'CYCLES'
        enc = nt.nodes.new("ShaderNodeVectorMath")  # into 0..1: the bake keeps no negative values
        enc.name = "srf_enc"
        enc.operation = 'MULTIPLY_ADD'
        k = ENC if socket == "Position" else 0.5
        enc.inputs[1].default_value = (k, k, k)
        enc.inputs[2].default_value = (0.5, 0.5, 0.5)
        nt.links.new(geo.outputs[socket], enc.inputs[0])
        nt.links.new(enc.outputs[0], em.inputs["Color"])
        nt.links.new(em.outputs[0], out.inputs[0])
        nt.nodes.active = out
        out.is_active_output = True
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.name = "srf_tex"
        tex.image = img
        nt.nodes.active = tex
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.bake(type='EMIT', margin=4)
    return {m: np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4) for m, img in images.items()}


def _poly(q, pts, closed):
    """For points q (N, 2): the distance to the outline `pts` (m), the distance along it (m), and inside (bool)."""
    d = np.full(len(q), 1e3)
    along = np.zeros(len(q))
    inside = np.zeros(len(q), bool)
    run = 0.0
    edges = list(zip(pts, pts[1:] + pts[:1])) if closed else list(zip(pts, pts[1:]))
    for (ax, ay), (bx, by) in edges:
        e = np.array([bx - ax, by - ay])
        n = float(np.hypot(*e))
        r = q - (ax, ay)
        t = np.clip((r @ e) / (n * n), 0, 1)
        dd = np.hypot(r[:, 0] - t * e[0], r[:, 1] - t * e[1])
        near = dd < d
        d = np.where(near, dd, d)
        along = np.where(near, run + t * n, along)
        run += n
        if closed:  # even-odd crossings of a ray along +x
            cross = ((ay > q[:, 1]) != (by > q[:, 1])) & (q[:, 0] < ax + (q[:, 1] - ay) * (bx - ax) / (by - ay + 1e-12))
            inside ^= cross
    return d, along, inside


def features(p, n, aa):
    """Per texel: the panel lines' cover, the lighter edging's and patches' cover, (0..1 each)."""
    view = np.where(n[..., 2] > 0.4, 0, np.where(n[..., 2] < -0.4, 1, 2))
    uv = np.where((view < 2)[..., None], np.dstack([np.abs(p[..., 0]), p[..., 1]]),
                  np.dstack([p[..., 1], p[..., 2]]))
    line = np.zeros(p.shape[:2])
    light = np.zeros(p.shape[:2])
    w = np.maximum(SEAM_W, 0.6 * aa)  # a line never thinner than 1.2 texels
    for vname, kind, pts in FEATURES:
        sel = view == VIEWS[vname]
        (x0, y0), (x1, y1) = np.min(pts, 0) - 0.2, np.max(pts, 0) + 0.2
        sel &= (uv[..., 0] > x0) & (uv[..., 0] < x1) & (uv[..., 1] > y0) & (uv[..., 1] < y1)
        idx = np.nonzero(sel)
        if not len(idx[0]):
            continue
        q = uv[idx]
        d, along, inside = _poly(q, pts, kind != "line")
        a = aa[idx]
        if kind == "patch":
            light[idx] = np.maximum(light[idx], np.clip((d * np.where(inside, 1, -1) + a) / (2 * a), 0, 1))
            continue
        if kind == "door":
            d = np.abs(d * np.where(inside, 1, -1) + TOOTH_AMP * (tri(along / TOOTH) - 0.5))
        wi = w[idx]
        line[idx] = np.maximum(line[idx], np.clip((wi + a - d) / (2 * a), 0, 1))
        if kind == "door":
            light[idx] = np.maximum(light[idx], 0.6 * np.clip((TAPE_W + a - d) / (2 * a), 0, 1))
    return line, light


def surface(pos, nrm, texel, base):
    """New colour, height (m) and roughness for one texture's texels."""
    p, n = pos[..., :3], nrm[..., :3] * 2 - 1
    aa = np.full(p.shape[:2], max(texel, 1e-4))  # a line's soft edge: one texel
    line, light = features(p, n, aa)
    # The coating's grey on rig.py's baked shading (linear), a faint slow tone drift (hand-applied coating).
    lin = lambda c: np.where(np.asarray(c) <= 0.04045, np.asarray(c) / 12.92, ((np.asarray(c) + 0.055) / 1.055) ** 2.4)
    srgb = lambda c: np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)
    col = lin(base[..., :3]) * (lin(COAT) / lin(RIG_GREY))
    tone = 1 + 0.06 * (noise(p, 2.5, 11) - 0.5) + 0.03 * (noise(p, 0.6, 12) - 0.5)
    col = col * (tone * (1 - 0.45 * line) * (1 + 0.35 * light))[..., None]
    height = -0.0005 * line + 0.0001 * light
    rough = ROUGH + 0.05 * (noise(p, 1.2, 13) - 0.5) + 0.06 * light + 0.12 * line
    return np.clip(srgb(col), 0, 1), height, np.clip(rough, 0.05, 1)


def normal_map(height, pos, texel):
    """Tangent-space normal map (OpenGL: green up) of `height` over the UV layout; no slope across an island's edge."""
    p = pos[..., :3]
    def d(axis):
        dh = np.roll(height, -1, axis) - np.roll(height, 1, axis)
        dp = np.linalg.norm(np.roll(p, -1, axis) - np.roll(p, 1, axis), axis=-1)
        ok = (dp > 0) & (dp < 4 * texel) & (np.roll(pos[..., 3], -1, axis) > 0) & (np.roll(pos[..., 3], 1, axis) > 0)
        return np.where(ok, dh / np.maximum(dp, 1e-6), 0.0)
    nx, ny = -d(1), -d(0)  # rows run up the image in Blender's pixels
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5])


def save(rgb, path, colour):
    hgt, wid = rgb.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), wid, hgt, alpha=False)
    img.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
    img.pixels.foreach_set(np.dstack([rgb, np.ones((hgt, wid))]).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()


def outward(objs):
    """Turns the download's inward-facing faces outward (the game draws them two-sided), so the normal bake picks
    the right view: a face turns when a ray along its normal hits the model and one against it leaves it."""
    dg = bpy.context.evaluated_depsgraph_get()
    sc = bpy.context.scene
    turned = 0
    for o in objs:
        mw = o.matrix_world
        rot = mw.to_3x3().inverted().transposed()
        flip = []
        for poly in o.data.polygons:
            c = mw @ poly.center
            n = (rot @ poly.normal).normalized()
            hit_out = sc.ray_cast(dg, c + n * 0.002, n, distance=30.0)[0]
            hit_in = sc.ray_cast(dg, c - n * 0.002, -n, distance=30.0)[0]
            if hit_out and not hit_in:
                flip.append(poly.index)
        if flip:
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bm.faces.ensure_lookup_table()
            bmesh.ops.reverse_faces(bm, faces=[bm.faces[i] for i in flip])
            bm.to_mesh(o.data)
            bm.free()
            turned += len(flip)
    print("surface.py: %d inward faces turned" % turned)


def _uvs(doc, mat_names):
    """{skin material name: [TEXCOORD_0 accessor index, ...]} of a glTF."""
    out = {}
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            name = mat_names[prim.get("material", 0)]
            if name.startswith("skin_") and name != "skin_plain":
                out.setdefault(name, set()).add(prim["attributes"]["TEXCOORD_0"])
    return out


def widen():
    """rig.py's UV atlas leaves some skin textures mostly empty: their islands sit in a strip a sixth to three fifths of
    the width (the wings' texels 3.5 cm across). Stretches each such texture's UVs across the width in both models
    (the same atlas) and its colour image with them, so the panel lines have texels to be drawn in."""
    span = {}
    for i, model in enumerate(MODELS):
        path = os.path.join(DIR, model)
        doc = json.load(open(path))
        names = [m["name"] for m in doc["materials"]]
        for b in doc["buffers"]:
            assert b["uri"].endswith(".bin")
        bins = {}
        for name, accs in _uvs(doc, names).items():
            views = []
            for a in accs:
                acc = doc["accessors"][a]
                bv = doc["bufferViews"][acc["bufferView"]]
                assert acc["componentType"] == 5126 and bv.get("byteStride", 8) == 8
                uri = doc["buffers"][bv["buffer"]]["uri"]
                buf = bins.setdefault(uri, bytearray(open(os.path.join(DIR, uri), "rb").read()))
                off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
                uv = np.frombuffer(buf, np.float32, acc["count"] * 2, off).reshape(-1, 2).copy()
                views.append((acc, buf, off, uv))
            if i == 0:
                u = np.concatenate([v[3][:, 0] for v in views])
                span[name] = (float(u.min()), float(u.max()))
            u0, u1 = span[name]
            if u1 - u0 > 0.7:
                continue
            for acc, buf, off, uv in views:
                uv[:, 0] = 0.004 + (uv[:, 0] - u0) / (u1 - u0) * 0.992
                buf[off:off + uv.nbytes] = uv.astype(np.float32).tobytes()
                if "min" in acc:
                    acc["min"][0], acc["max"][0] = float(uv[:, 0].min()), float(uv[:, 0].max())
        for uri, buf in bins.items():
            open(os.path.join(DIR, uri), "wb").write(buf)
        json.dump(doc, open(path, "w"), indent="\t", separators=(",", ":"), ensure_ascii=False)
        open(path, "a").write("\n")
    for name, (u0, u1) in span.items():
        if u1 - u0 > 0.7:
            continue
        path = os.path.join(DIR, "textures", name + ".png")
        img = bpy.data.images.load(path)
        wid, hgt = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(hgt, wid, 4)
        x = (u0 + ((np.arange(wid) + 0.5) / wid - 0.004) / 0.992 * (u1 - u0)) * wid - 0.5
        x0 = np.clip(np.floor(x).astype(int), 0, wid - 1)
        f = np.clip(x - x0, 0, 1)[None, :, None]
        out = px[:, x0] * (1 - f) + px[:, np.minimum(x0 + 1, wid - 1)] * f
        save(out[..., :3], path, True)
        bpy.data.images.remove(img)
        print("surface.py: %s widened %.0f %% -> 99 %%" % (name, 100 * (u1 - u0)))


def main():
    gltf = os.path.join(DIR, MODELS[0])
    doc = json.load(open(gltf))
    if any("normalTexture" in m for m in doc["materials"] if m["name"].startswith("skin_")):
        sys.exit("surface.py: already done on " + gltf)
    widen()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=gltf)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 1
    sc.cycles.device = 'CPU'
    images, sizes = {}, {}
    for mat in bpy.data.materials:
        if not mat.name.startswith("skin_") or mat.name == "skin_plain" or not mat.use_nodes:
            continue
        src = next(n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image)
        sizes[mat] = src
        images[mat] = bpy.data.images.new("srf_" + mat.name, src.size[0], src.size[1], alpha=True, float_buffer=True)
    objs = [o for o in sc.objects if o.type == 'MESH' and any(s.material in images for s in o.material_slots)]
    outward(objs)
    # Every other material on those objects bakes into a scratch image.
    scratch = bpy.data.images.new("srf_scratch", 64, 64, float_buffer=True)
    for o in objs:
        for s in o.material_slots:
            if s.material and s.material not in images and s.material.use_nodes:
                nt = s.material.node_tree
                tex = nt.nodes.get("srf_tex") or nt.nodes.new("ShaderNodeTexImage")
                tex.name, tex.image = "srf_tex", scratch
                nt.nodes.active = tex
    for img in images.values():
        img.pixels.foreach_set(np.zeros(img.size[0] * img.size[1] * 4, dtype=np.float32))
    pos = bake(objs, images, "Position")
    nrm = bake(objs, images, "Normal")
    for mat in images:
        pos[mat][..., :3] = (pos[mat][..., :3] - 0.5) / ENC
    for mat, src in sizes.items():
        name = mat.name
        hgt, wid = src.size[1], src.size[0]
        base = np.array(src.pixels[:], dtype=np.float32).reshape(hgt, wid, 4)
        P = pos[mat]
        dp = np.linalg.norm(np.roll(P[..., :3], -1, 1) - P[..., :3], axis=-1)
        texel = float(np.median(dp[(P[..., 3] > 0) & (dp > 0) & (dp < 0.2)])) if (P[..., 3] > 0).any() else 0.01
        col, height, rough = surface(P, nrm[mat], texel, base)
        inside = (P[..., 3] > 0)[..., None]
        col = np.where(inside, col, base[..., :3])
        nm = np.where(inside, normal_map(height, P, texel), np.array([0.5, 0.5, 1.0]))
        mr = np.where(inside, np.dstack([np.ones_like(rough), rough, np.zeros_like(rough)]),
                      np.array([1.0, ROUGH, 0.0]))
        tex_dir = os.path.join(DIR, "textures")
        save(col, os.path.join(tex_dir, name + ".png"), True)
        save(nm, os.path.join(tex_dir, name + "_n.png"), False)
        save(mr, os.path.join(tex_dir, name + "_mr.png"), False)
        print("surface.py: %s %dx%d, texel %.1f mm" % (name, wid, hgt, texel * 1000))
    for model in MODELS:
        path = os.path.join(DIR, model)
        doc = json.load(open(path))
        for m in doc["materials"]:
            if m["name"] in LIGHT_STRIPS:  # the fins' formation strips: pale and unlit by day
                m["emissiveFactor"] = LIGHT_STRIPS[m["name"]]
                m["pbrMetallicRoughness"]["baseColorFactor"] = list(STRIP_COLOUR)
            if not m["name"].startswith("skin_") or m["name"] == "skin_plain":
                continue
            for kind, key in (("_n", "normalTexture"), ("_mr", "metallicRoughnessTexture")):
                doc["images"].append({"mimeType": "image/png", "name": m["name"] + kind,
                                      "uri": "textures/%s%s.png" % (m["name"], kind)})
                doc["textures"].append({"sampler": 0, "source": len(doc["images"]) - 1})
                ref = {"index": len(doc["textures"]) - 1}
                if key == "normalTexture":
                    m[key] = ref
                else:
                    m["pbrMetallicRoughness"][key] = ref
            m.setdefault("extras", {})["specular"] = SPECULAR
            m["pbrMetallicRoughness"]["metallicFactor"] = 1.0
            m["pbrMetallicRoughness"]["roughnessFactor"] = 1.0
        json.dump(doc, open(path, "w"), indent="\t", separators=(",", ":"), ensure_ascii=False)
        open(path, "a").write("\n")


main()
