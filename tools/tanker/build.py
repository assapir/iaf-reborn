# Our own low-poly tanker models (no free one is on disk; modern-iaf/docs/research/air-refuelling.md §8.1): the
# KC-46A Gideon (a Boeing 767-2C) and the 707 Re'em (a 707-320C), from the published dimensions, each with its
# refuelling boom as separate nodes the sim moves (shared/ai/tanker.gd). Writes shared/extra/models/tanker/<type>.glb:
#
#   blender -b --factory-startup -P tools/tanker/build.py -- kc46 shared/extra/models/tanker/kc46.glb
#   blender -b --factory-startup -P tools/tanker/build.py -- reem shared/extra/models/tanker/reem.glb
#
# Blender frame: +Y forward (glTF and Godot -Z), +Z up, +X right; metres; the origin on the fuselage axis at about the
# wing's quarter chord. Nodes: <type> (the airframe), boom_pivot (the boom's hinge: its local -Y aft, the boom along it
# at zero elevation), boom (the fixed tube), boom_inner (the telescope at zero extension: tanker.gd moves it aft by the
# extension), nozzle (the tip, a marker), pdl_l / pdl_r (the pilot director lights' rows on the belly, markers:
# tanker.gd draws their lamps). The boom's figures match crates/iaf-ai/src/tanker.rs (KC46, REEM): the hinge `pivot`
# (forward, right, up), the nozzle at `boom_len` + the extension from the hinge.
# Dimensions (sources in modern-iaf/docs/research/air-refuelling.md §8.1 and shared/extra/models/tanker/SOURCES.md):
# KC-46A 50.5 m long, 47.6 m span, 15.9 m high, the 767's 5.03 m wide body and 31.5° sweep, two engines; 707-320C
# 46.6 m long, 44.4 m span, 12.9 m high, a 3.76 m wide body, 35° sweep, four engines. Shapes between those: inferred.
import math
import sys

import bmesh
import bpy

KIND, OUT = sys.argv[sys.argv.index("--") + 1 : sys.argv.index("--") + 3]
FT = 0.3048
TYPES = {
    "kc46": {
        "nose": 25.5, "tail": -25.0, "r": 2.515, "h": 2.7,
        "semi": 23.8, "root": 8.6, "tip": 2.2, "sweep": 31.5, "dihedral": 6.0, "wing_y": 4.0, "wing_z": -1.6,
        "engines": [(7.6, 1.4, 5.2)], "eng_z": -2.9,
        "stab": (9.3, 6.2, 2.2, 36.0, -16.0), "fin": (9.0, 9.0, 3.2, 40.0, -14.0),
        "pivot": (0.0, -20.6, -0.6), "boom_len": (57.5 - 21.0) * FT, "ext_max": 21.0 * FT,
        "grey": (0.17, 0.185, 0.2, 1.0),  # linear: about sRGB 115, 119, 124
    },
    "reem": {
        "nose": 23.3, "tail": -23.3, "r": 1.88, "h": 2.1,
        "semi": 22.2, "root": 8.2, "tip": 2.0, "sweep": 35.0, "dihedral": 7.0, "wing_y": 3.6, "wing_z": -1.2,
        "engines": [(8.3, 0.85, 4.3), (14.1, 0.85, 4.3)], "eng_z": -2.2,
        "stab": (7.0, 4.6, 1.6, 35.0, -15.5), "fin": (7.6, 7.0, 2.4, 35.0, -13.5),
        "pivot": (0.0, -19.0, -0.5), "boom_len": (47.0 - 18.0) * FT, "ext_max": 18.0 * FT,
        "grey": (0.22, 0.23, 0.24, 1.0),  # linear: about sRGB 130, 133, 135
    },
}
T = TYPES[KIND]
DARK = (0.04, 0.045, 0.05, 1.0)
# The fixed tube ends half a metre before boom_len: the telescope's half metre of tip shows at zero extension.
BOOM_LEN = T["boom_len"] - 0.5
INNER_LEN = T["ext_max"] + 1.0


def material(name, rgba):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgba
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = 0.55
    return m


def obj(name, bm, mat, parent=None, loc=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    return o


def empty(name, parent, loc):
    o = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    return o


def lathe(bm, stations, n=24):
    """Rings along Y: (y, rx, rz, zc) each; the ends closed."""
    rings = []
    for y, rx, rz, zc in stations:
        rings.append([bm.verts.new((rx * math.cos(a), y, zc + rz * math.sin(a))) for a in
                      (2 * math.pi * j / n for j in range(n))])
    for a, b in zip(rings, rings[1:]):
        for j in range(n):
            bm.faces.new((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])


def plate(bm, root, tip, t_root, t_tip, axis="x"):
    """A tapered slab: root / tip = ((x, y_le, z), chord). axis x: a wing (span along x); z: a fin (span up)."""
    vs = []
    for (p, c), t in ((root, t_root), (tip, t_tip)):
        x, y, z = p
        for yy, off in ((y, 0.0), (y - 0.3 * c, t * c / 2), (y - c, 0.0), (y - 0.3 * c, -t * c / 2)):
            vs.append(bm.verts.new((x + off, yy, z) if axis == "z" else (x, yy, z + off)))
    for j in range(4):
        bm.faces.new((vs[j], vs[(j + 1) % 4], vs[4 + (j + 1) % 4], vs[4 + j]))
    bm.faces.new(vs[0:4][::-1])
    bm.faces.new(vs[4:8])


bpy.ops.wm.read_factory_settings(use_empty=True)
grey = material("grey", T["grey"])
dark = material("dark", DARK)

# The fuselage: the nose, the constant section, the tail cone rising to the fin.
nose, tail, R, H = T["nose"], T["tail"], T["r"], T["h"]
L = nose - tail
bm = bmesh.new()
lathe(
    bm,
    [
        (tail, 0.06 * R, 0.09 * H, 0.6 * H),
        (tail + 0.06 * L, 0.36 * R, 0.37 * H, 0.45 * H),
        (tail + 0.16 * L, 0.76 * R, 0.78 * H, 0.22 * H),
        (tail + 0.26 * L, R, H, 0.0),
        (nose - 0.15 * L, R, H, 0.0),
        (nose - 0.08 * L, 0.92 * R, 0.93 * H, -0.06 * H),
        (nose - 0.04 * L, 0.68 * R, 0.67 * H, -0.15 * H),
        (nose - 0.012 * L, 0.36 * R, 0.37 * H, -0.26 * H),
        (nose, 0.06 * R, 0.07 * H, -0.33 * H),
    ],
)
body = obj(KIND, bm, grey)

sw = math.tan(math.radians(T["sweep"]))
for s, side in ((1, "r"), (-1, "l")):
    # The wing: low, swept at the quarter chord, with dihedral.
    bm = bmesh.new()
    root_x = 0.95 * R
    y0, z0, semi = T["wing_y"], T["wing_z"], T["semi"]
    tip_y = y0 - 0.25 * T["root"] - (semi - root_x) * sw + 0.25 * T["tip"]
    tip_z = z0 + (semi - root_x) * math.tan(math.radians(T["dihedral"]))
    plate(bm, ((s * root_x, y0, z0), T["root"]), ((s * semi, tip_y, tip_z), T["tip"]), 0.13, 0.10)
    obj("wing_" + side, bm, grey, body)
    # The engines: nacelles under and ahead of the wing, each on a pylon.
    for i, (ex, er, el) in enumerate(T["engines"]):
        le = y0 - (ex - root_x) * sw  # the wing's leading edge there
        z = z0 + (ex - root_x) * math.tan(math.radians(T["dihedral"])) + T["eng_z"] - z0 + 0.0
        bm = bmesh.new()
        lathe(bm, [(el, 0.9 * er, 0.9 * er, 0), (el - 0.6, er, er, 0), (1.2, 0.95 * er, 0.95 * er, 0),
                   (0.0, 0.62 * er, 0.62 * er, 0)], 20)
        obj("engine_%s%d" % (side, i), bm, grey, body, (s * ex, le - 0.55 * el, z))
        bm = bmesh.new()
        plate(bm, ((s * ex, le + 0.2, z + er * 0.8), 0.9 * el), ((s * ex, le - 0.4, z + er + 0.6), 0.7 * el), 0.12,
              0.12, "z")
        obj("pylon_%s%d" % (side, i), bm, grey, body)
    # The horizontal tail.
    span, rc, tc, sweep, y = T["stab"]
    bm = bmesh.new()
    plate(bm, ((s * 0.4 * R, y, 0.35 * H), rc), ((s * span, y - (span - 0.4 * R) * math.tan(math.radians(sweep)),
          0.6 * H), tc), 0.1, 0.09)
    obj("stab_" + side, bm, grey, body)

# The fin.
height, rc, tc, sweep, y = T["fin"]
bm = bmesh.new()
plate(bm, ((0.0, y, 0.85 * H), rc), ((0.0, y - height * math.tan(math.radians(sweep)), 0.85 * H + height), tc), 0.11,
      0.09, "z")
obj("fin", bm, grey, body)

# The boom: its hinge under the tail cone; at zero elevation it lies along -Y (aft).
pivot = empty("boom_pivot", body, T["pivot"])
bm = bmesh.new()
lathe(bm, [(0.0, 0.42, 0.42, 0), (-1.0, 0.3, 0.3, 0), (-BOOM_LEN, 0.24, 0.24, 0)], 12)
boom = obj("boom", bm, grey, pivot)
for s, side in ((1, "r"), (-1, "l")):  # the ruddevators: a V under the tube near its end
    bm = bmesh.new()
    plate(bm, ((0.0, -BOOM_LEN + 2.4, 0.0), 1.6), ((s * 2.2, -BOOM_LEN + 1.9, 0.0), 1.0), 0.08, 0.06)
    o = obj("ruddevator_" + side, bm, grey, boom)
    o.rotation_euler = (0, s * math.radians(35), 0)
bm = bmesh.new()
lathe(bm, [(0.0, 0.15, 0.15, 0), (-INNER_LEN, 0.15, 0.15, 0), (-INNER_LEN - 0.3, 0.08, 0.08, 0)], 10)
# Its tip half a metre past the tube's end at zero extension: the nozzle `boom_len` from the hinge.
inner = obj("boom_inner", bm, dark, boom, (0, -BOOM_LEN + INNER_LEN - 0.2, 0))
empty("nozzle", inner, (0, -INNER_LEN - 0.3, 0))

# The pilot director lights: two rows on the belly behind the nose gear, left elevation, right telescope.
empty("pdl_l", body, (-0.8, nose - 0.2 * L, -0.98 * H))
empty("pdl_r", body, (0.8, nose - 0.2 * L, -0.98 * H))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
print("wrote", OUT)
