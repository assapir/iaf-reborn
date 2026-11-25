# The F-35I's skin as a surface (docs/f35i.md §5.1): panels of slightly different tone and sheen, their seams, access
# doors with saw-tooth edges and a lighter caulk outline, fastener rows, written into the skin's colour texture and
# into a normal map and a metallic / roughness map per skin texture, all our own (procedural, seeded). Runs once on
# rig.py's output (the skin textures as rig.py baked them; it refuses a model it already did):
#
#   blender -b --python tools/f35i/surface.py -- shared/extra/planes/f35i
#
# Every texel's world position and normal are baked from the model (Cycles, emission), so the pattern follows the
# airframe across the UV islands; the panels are laid out on the jet's top, bottom and sides from those.
import json
import os
import sys

import bpy
import numpy as np

DIR = sys.argv[sys.argv.index("--") + 1]
MODELS = ("f35i.gltf", "f35i_bc.gltf")  # the cockpit view's model shares the skin textures and UVs
SEAM_W = 0.004  # m, half width of a panel seam
CAULK_W = 0.018  # m, the lighter caulk band along a door's edge
TOOTH = 0.09  # m, the saw-tooth's pitch on a door's edge
TOOTH_AMP = 0.025  # m, the saw-tooth's depth
RIVET_PITCH = 0.065  # m along the door's edge
RIVET_IN = 0.03  # m inside the door's edge
RIVET_R = 0.005  # m
METALLIC = 0.1  # the coating's metallic sheen (photos, docs/f35i.md §5.1)
ROUGH = 0.42
ENC = 0.02  # the position bake's scale (m -> 0..1 round 0.5)


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


def panels(p, n):
    """Per texel: the panel's id, the distance to its seam (m), the door's id or -1, the distance to the door's
    saw-tooth edge (m, signed: inside > 0) and the distance along it for the fasteners."""
    top = np.abs(n[..., 2]) > 0.55
    face = np.where(top, np.where(n[..., 2] > 0, 0, 1), np.where(n[..., 0] > 0, 2, 3))
    a = p[..., 1]  # along the jet (nose +y)
    b = np.where(top, p[..., 0], p[..., 2])  # across: span on the top and bottom, height on the sides
    L = 1.35
    ia = np.floor(a / L + 0.5 * h(face)).astype(np.int64)
    fa = a / L + 0.5 * h(face) - ia
    W = 0.55 + 0.7 * h(face, ia, 1)
    off = h(face, ia, 2)
    ib = np.floor(b / W + off).astype(np.int64)
    fb = b / W + off - ib
    # About two thirds of the panels' seams drawn: the coating hides the rest (the panels keep their tone).
    big = 1e3
    seam_a = np.minimum(np.where(h(face, ia, 20) < 0.7, fa * L, big),
                        np.where(h(face, ia + 1, 20) < 0.7, (1 - fa) * L, big))
    seam_b = np.minimum(np.where(h(face, ia, ib, 21) < 0.6, fb * W, big),
                        np.where(h(face, ia, ib + 1, 21) < 0.6, (1 - fb) * W, big))
    seam = np.minimum(seam_a, seam_b)
    cell = (face * 1000 + ia) * 1000 + ib
    # A door in about a third of the panels: inset in it, its edges saw-toothed.
    door = h(cell, 3) < 0.35
    m0a, m1a = 0.12 + 0.2 * h(cell, 4), 0.12 + 0.2 * h(cell, 5)
    m0b, m1b = 0.12 + 0.2 * h(cell, 6), 0.12 + 0.2 * h(cell, 7)
    ua, ub = fa * L, fb * W  # metres inside the panel
    tooth_b = TOOTH_AMP * (tri(ub / TOOTH) - 0.5)
    tooth_a = TOOTH_AMP * (tri(ua / TOOTH) - 0.5)
    ea = np.minimum(ua - m0a * L + tooth_b, (1 - m1a) * L - ua + tooth_b)  # fore and aft edges
    eb = np.minimum(ub - m0b * W + tooth_a, (1 - m1b) * W - ub + tooth_a)  # side edges
    edge = np.where(door, np.minimum(ea, eb), -1.0)
    along = np.where(ea < eb, ub, ua)
    return cell, seam, np.where(door, cell, -1), edge, along


def surface(pos, nrm, texel, base):
    """New colour, height (m) and metallic / roughness for one texture's texels."""
    p, n = pos[..., :3], nrm[..., :3] * 2 - 1
    cell, seam, door, edge, along = panels(p, n)
    aa = np.maximum(texel, 1e-4)  # a line's soft edge: one texel
    seam_c = np.clip((SEAM_W + aa - seam) / (2 * aa), 0, 1)
    door_line = np.clip((SEAM_W + aa - np.abs(edge)) / (2 * aa), 0, 1) * (door >= 0)
    caulk = np.clip((CAULK_W + aa - np.abs(edge)) / (2 * aa), 0, 1) * (door >= 0) * (1 - door_line)
    t = along / RIVET_PITCH
    rd = np.hypot((t - np.round(t)) * RIVET_PITCH, edge - RIVET_IN)
    rivet = np.clip((RIVET_R + aa - rd) / (2 * aa), 0, 1) * (door >= 0)
    # The panels' tone: each panel and door a little lighter or darker, a slow mottle over it all.
    tone = 1 + 0.14 * (h(cell, 8) - 0.5) + np.where(door >= 0, 0.12 * (h(cell, 9) - 0.5), 0)
    tone = tone + 0.08 * (noise(p, 1.6, 11) - 0.5) + 0.03 * (noise(p, 0.35, 12) - 0.5)
    line = np.maximum(seam_c, door_line)
    col = base[..., :3] * (tone * (1 - 0.3 * line) * (1 + 0.10 * caulk) * (1 - 0.12 * rivet))[..., None]
    height = -0.0006 * line + 0.0002 * caulk + 0.0003 * rivet
    rough = ROUGH + 0.08 * (h(cell, 10) - 0.5) + 0.08 * (noise(p, 0.8, 13) - 0.5) + 0.22 * caulk + 0.15 * line
    metal = METALLIC * (1 - 0.6 * caulk) * (1 - 0.5 * line)
    return np.clip(col, 0, 1), height, np.clip(rough, 0.05, 1), np.clip(metal, 0, 1)


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


def main():
    gltf = os.path.join(DIR, MODELS[0])
    doc = json.load(open(gltf))
    if any("normalTexture" in m for m in doc["materials"] if m["name"].startswith("skin_")):
        sys.exit("surface.py: already done on " + gltf)
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
        col, height, rough, metal = surface(P, nrm[mat], texel, base)
        inside = (P[..., 3] > 0)[..., None]
        col = np.where(inside, col, base[..., :3])
        nm = np.where(inside, normal_map(height, P, texel), np.array([0.5, 0.5, 1.0]))
        mr = np.where(inside, np.dstack([np.ones_like(rough), rough, metal]), np.array([1.0, ROUGH, METALLIC]))
        tex_dir = os.path.join(DIR, "textures")
        save(col, os.path.join(tex_dir, name + ".png"), True)
        save(nm, os.path.join(tex_dir, name + "_n.png"), False)
        save(mr, os.path.join(tex_dir, name + "_mr.png"), False)
        print("surface.py: %s %dx%d, texel %.1f mm" % (name, wid, hgt, texel * 1000))
    for model in MODELS:
        path = os.path.join(DIR, model)
        doc = json.load(open(path))
        for m in doc["materials"]:
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
            m["pbrMetallicRoughness"]["metallicFactor"] = 1.0
            m["pbrMetallicRoughness"]["roughnessFactor"] = 1.0
        json.dump(doc, open(path, "w"), indent="\t", separators=(",", ":"), ensure_ascii=False)
        open(path, "a").write("\n")


main()
