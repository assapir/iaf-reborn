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
# Paint and details matched side by side to public photographs of the KC-46A (Wikimedia Commons, US Air Force photos;
# reference only, listed in shared/extra/models/tanker/SOURCES.md): the one medium blue-grey all over, the radome a
# shade darker, the dark flight deck windows, the bare-metal inlet lips and bronze exhaust cones, the yellow belly line to the
# boom operator's camera fairing, IAF roundels (tools/eitam/markings.png, ours) where the USAF star sits; the boom's
# faired root, its grey tube, the dark V ruddevators near its end, the pale yellow-green telescope with its red, orange
# and yellow bands next to the tube, and the bare-metal nozzle.
import math
import os
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
        "grey": (156, 165, 177),  # sRGB: matched in the sim to the photographs (kc46_side_1, boom_outside_2)
    },
    "reem": {
        "nose": 23.3, "tail": -23.3, "r": 1.88, "h": 2.1,
        "semi": 22.2, "root": 8.2, "tip": 2.0, "sweep": 35.0, "dihedral": 7.0, "wing_y": 3.6, "wing_z": -1.2,
        "engines": [(8.3, 0.85, 4.3), (14.1, 0.85, 4.3)], "eng_z": -2.2,
        "stab": (7.0, 4.6, 1.6, 35.0, -15.5), "fin": (7.6, 7.0, 2.4, 35.0, -13.5),
        "pivot": (0.0, -19.0, -0.5), "boom_len": (47.0 - 18.0) * FT, "ext_max": 18.0 * FT,
        "grey": (130, 133, 135),  # sRGB
    },
}
T = TYPES[KIND]
HERE = os.path.dirname(os.path.abspath(__file__))
# sRGB, roughness, metallic.
PAINT = {
    "grey": (T["grey"], 0.5, 0.0),
    "skin": (T["grey"], 0.5, 0.0),
    "radome": (tuple(c - 18 for c in T["grey"]), 0.5, 0.0),
    "rudder": (tuple(c - 40 for c in T["grey"]), 0.5, 0.0),  # the boom's ruddevators, darker than its tube
    "window": ((22, 26, 30), 0.12, 0.0),
    "dark": ((30, 32, 35), 0.4, 0.0),
    "metal": ((182, 184, 188), 0.3, 0.85),
    "exhaust": ((168, 138, 104), 0.35, 0.8),  # the hot section's bronze-brown metal
    "yellow": ((222, 178, 30), 0.5, 0.0),
    "telescope": ((196, 202, 142), 0.45, 0.0),  # the boom's inner tube: pale yellow-green
    "band_y": ((236, 196, 40), 0.45, 0.0),
    "band_o": ((232, 118, 30), 0.45, 0.0),
    "band_r": ((200, 40, 30), 0.45, 0.0),
    "decal": ((255, 255, 255), 0.5, 0.0),
}
ROUNDEL = (0, 0, 256, 256)  # its box in tools/eitam/markings.png (1024 x 512 px)
# The fixed tube ends half a metre before boom_len: the telescope's half metre of tip shows at zero extension.
BOOM_LEN = T["boom_len"] - 0.5
INNER_LEN = T["ext_max"] + 1.0


def lin(c):
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in (v / 255.0 for v in c)]


MATS = {}
SKIN = (1024, 512)  # px round the fuselage, along it


def skin_image():
    """The fuselage's paint as an image on its lathe's UVs (u round from the right side, v from the tail): the grey, a
    shade darker toward the belly (the photographs' shaded underside), faint panel lines (the circumferential joints,
    two lap joints a side), the doors' outlines (two a side, the main deck cargo door forward left) and the antennas
    on the spine and belly as dark dots (photographs; their places inferred)."""
    import numpy as np

    w, h = SKIN
    nose, tail = T["nose"], T["tail"]
    length = nose - tail
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    uu, vv = np.meshgrid(u, v)
    ang = uu * 360.0  # deg round from the right side, 90 the top
    y = tail + vv * length
    shade = 1.0 - 0.1 * np.clip(-np.sin(np.radians(ang)), 0.0, None)
    line = np.zeros((h, w), bool)
    px_m = length / h
    for yy in np.arange(tail + 0.2 * length, nose - 0.1 * length, 5.3):  # the circumferential joints
        line |= np.abs(y - yy) < px_m
    for a in (35, 145, 215, 325):  # the lap joints
        line |= (np.abs(ang - a) < 360.0 / w) & (y > tail + 0.2 * length) & (y < nose - 0.1 * length)

    def door(y_fwd, y_aft, a_mid, a_half):
        box = (y < y_fwd) & (y > y_aft) & (np.abs(ang - a_mid) < a_half)
        edge = (np.abs(y - y_fwd) < px_m) | (np.abs(y - y_aft) < px_m) | (np.abs(np.abs(ang - a_mid) - a_half) < 0.5)
        return box & edge | edge & (y < y_fwd + px_m) & (y > y_aft - px_m) & (np.abs(ang - a_mid) <= a_half + 0.5)

    r = T["r"]
    door_a = math.degrees(0.95 / r)  # a 1.9 m door's half height in degrees round the side
    for a_mid in (5.0, 175.0):  # the right side and the left (round from the right, up)
        for yy in (nose - 0.13 * length, tail + 0.3 * length):
            line |= door(yy, yy - 1.05, a_mid, door_a)
    line |= door(nose - 0.2 * length, nose - 0.2 * length - 3.4, 170.0, math.degrees(1.3 / r))  # the cargo door
    dots = np.zeros((h, w), bool)
    for yy, a in ((nose - 0.25 * length, 90), (0.0, 90), (-6.0, 90), (nose - 0.3 * length, 270), (-9.0, 270)):
        dots |= (np.abs(y - yy) < 3 * px_m) & (np.abs(ang - a) < 3 * 360.0 / w)
    base = np.array(T["grey"], float) / 255.0
    rgb = base[None, None, :] * shade[:, :, None]
    rgb[line] *= 0.93
    rgb[dots] = 0.12
    img = bpy.data.images.new("skin", w, h)
    px = np.ones((h, w, 4), np.float32)
    px[:, :, :3] = rgb
    img.pixels = px.ravel()
    img.file_format = "PNG"
    img.pack()
    return img


def material(name):
    if name in MATS:
        return MATS[name]
    rgb, rough, metal = PAINT[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*lin(rgb), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if name == "skin":  # the fuselage's paint with its panel lines (skin_image)
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = skin_image()
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if name == "decal":  # the markings cut out by their alpha (glTF MASK), as the Eitam's
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(HERE, "..", "eitam", "markings.png"))
        cut = nt.nodes.new("ShaderNodeMath")
        cut.operation = "ROUND"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
        nt.links.new(cut.outputs[0], bsdf.inputs["Alpha"])
    MATS[name] = m
    return m


def obj(name, bm, mats, parent=None, loc=(0, 0, 0)):
    """A mesh object; `mats` one material name, or a list the faces' material_index picks from."""
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in [mats] if isinstance(mats, str) else mats:
        me.materials.append(material(m))
    for p in me.polygons:
        p.use_smooth = me.materials[p.material_index].name != "decal"
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


def lathe(bm, stations, n=24, mats=None, caps=None):
    """Rings along Y: (y, rx, rz, zc) each; the ends closed. `mats`: each segment's material index; `caps` the first
    and the last ring's (else the end segments')."""
    rings = []
    for y, rx, rz, zc in stations:
        rings.append([bm.verts.new((rx * math.cos(a), y, zc + rz * math.sin(a))) for a in
                      (2 * math.pi * j / n for j in range(n))])
    uv = bm.loops.layers.uv.verify()  # u round from the right side (0.25 the top), v along from the first ring
    y0, y1 = stations[0][0], stations[-1][0]
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for j in range(n):
            f = bm.faces.new((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]))
            f.material_index = mats[i] if mats else 0
            for loop, (jj, k) in zip(f.loops, ((j, i), (j + 1, i), (j + 1, i + 1), (j, i + 1))):
                loop[uv].uv = (jj / n, (stations[k][0] - y0) / (y1 - y0))
    caps = caps or ((mats[0], mats[-1]) if mats else (0, 0))
    bm.faces.new(rings[0][::-1]).material_index = caps[0]
    bm.faces.new(rings[-1]).material_index = caps[1]


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

# The fuselage: the nose, the constant section, the tail cone rising to the fin.
nose, tail, R, H = T["nose"], T["tail"], T["r"], T["h"]
L = nose - tail
FUSE = [
        (tail, 0.06 * R, 0.09 * H, 0.6 * H),
        (tail + 0.06 * L, 0.36 * R, 0.37 * H, 0.45 * H),
        (tail + 0.16 * L, 0.76 * R, 0.78 * H, 0.22 * H),
        (tail + 0.26 * L, R, H, 0.0),
        (nose - 0.15 * L, R, H, 0.0),
        (nose - 0.08 * L, 0.92 * R, 0.93 * H, -0.06 * H),
        (nose - 0.04 * L, 0.68 * R, 0.67 * H, -0.15 * H),
        (nose - 0.012 * L, 0.36 * R, 0.37 * H, -0.26 * H),
        (nose, 0.06 * R, 0.07 * H, -0.33 * H),
]
bm = bmesh.new()
lathe(bm, FUSE, mats=[0] * (len(FUSE) - 3) + [1, 1])  # the last two segments: the radome
body = obj(KIND, bm, ["skin", "radome"])


def section(y):
    """The fuselage's (rx, rz, zc) at `y`, between its stations."""
    for (y0, *a), (y1, *b) in zip(FUSE, FUSE[1:]):
        if y0 <= y <= y1:
            t = (y - y0) / (y1 - y0)
            return [u + (v - u) * t for u, v in zip(a, b)]
    return FUSE[-1][1:] if y > nose else FUSE[0][1:]


def skin(y, ang, out=0.02):
    """The point on the fuselage at `y`, `ang` deg round from the right (90 the top), `out` m off the skin."""
    rx, rz, zc = section(y)
    a = math.radians(ang)
    return ((rx + out) * math.cos(a), y, zc + (rz + out) * math.sin(a))


def band(bm, y0, y1, a0, a1, k, n=6, out=0.03):
    """A painted patch `out` m off the skin from y0 to y1 and a0 to a1 deg, material index k."""
    rows = [[bm.verts.new(skin(y0 + (y1 - y0) * i / n, a0 + (a1 - a0) * j / n, out)) for j in range(n + 1)]
            for i in range(n + 1)]
    for i in range(n):
        for j in range(n):
            f = bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
            f.material_index = k


def decal(bm, uv, pts, box, k):
    """A marking on the quad `pts` (counter-clockwise from outside, from its lower left), `box` in markings.png."""
    u0, v0, u1, v1 = box
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    f.material_index = k
    for loop, (u, v) in zip(f.loops, [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]):
        loop[uv].uv = (u / 1024.0, 1.0 - v / 512.0)


# The paint on the fuselage: the flight deck's windows, the belly line, the roundels (KC-46A photographs; the Re'em
# the same places, inferred).
bm = bmesh.new()
uv = bm.loops.layers.uv.new("uv")
for s in (1, -1):
    a0, a1 = (22, 36) if s > 0 else (144, 158)
    band(bm, nose - 0.078 * L, nose - 0.05 * L, a0, a1, 0)  # the side windows
y, rr = tail + 0.3 * L, 1.1  # the roundels aft, where the USAF star is
for s in (1, -1):
    x = s * (section(y)[0] + 0.03)
    zc = section(y)[2] + 0.15 * H
    pts = [(x, y - s * rr, zc - rr), (x, y + s * rr, zc - rr), (x, y + s * rr, zc + rr), (x, y - s * rr, zc + rr)]
    decal(bm, uv, pts, ROUNDEL, 2)
band(bm, nose - 0.057 * L, nose - 0.047 * L, 36, 144, 0)  # the windshield's front panels
band(bm, T["wing_y"] - T["root"], T["pivot"][1] + 3.2, -91.2, -88.8, 1, 8, 0.05)  # the yellow belly line
obj("paint", bm, ["window", "yellow", "decal"], body)
# The boom operator's camera fairing on the belly before the hinge.
bm = bmesh.new()
yc = T["pivot"][1] + 2.6
rz = section(yc)
lathe(bm, [(yc + 0.9, 0.05, 0.05, 0), (yc + 0.5, 0.45, 0.35, 0), (yc - 0.5, 0.45, 0.35, 0),
           (yc - 0.9, 0.05, 0.05, 0)], 12)
obj("camera_fairing", bm, "dark", body, (0, 0, rz[2] - rz[1] + 0.05))

sw = math.tan(math.radians(T["sweep"]))
for s, side in ((1, "r"), (-1, "l")):
    # The wing: low, swept at the quarter chord, with dihedral.
    bm = bmesh.new()
    root_x = 0.95 * R
    y0, z0, semi = T["wing_y"], T["wing_z"], T["semi"]
    tip_y = y0 - 0.25 * T["root"] - (semi - root_x) * sw + 0.25 * T["tip"]
    tip_z = z0 + (semi - root_x) * math.tan(math.radians(T["dihedral"]))
    plate(bm, ((s * root_x, y0, z0), T["root"]), ((s * semi, tip_y, tip_z), T["tip"]), 0.13, 0.10)
    uv = bm.loops.layers.uv.new("uv")
    rx, rr = s * (semi - 5.0), 1.0
    ry = y0 - 0.25 * T["root"] - (semi - 5.0 - root_x) * sw - 0.6
    rz = z0 + (semi - 5.0 - root_x) * math.tan(math.radians(T["dihedral"]))
    for up in (1, -1):  # the roundels on the wing, above and below
        zz = rz + up * 0.2
        pts = [(rx - rr, ry - rr, zz), (rx + rr, ry - rr, zz), (rx + rr, ry + rr, zz), (rx - rr, ry + rr, zz)]
        decal(bm, uv, pts if up > 0 else [pts[1], pts[0], pts[3], pts[2]], ROUNDEL, 1)
    obj("wing_" + side, bm, ["grey", "decal"], body)
    # The engines: nacelles under and ahead of the wing, each on a pylon.
    for i, (ex, er, el) in enumerate(T["engines"]):
        le = y0 - (ex - root_x) * sw  # the wing's leading edge there
        z = z0 + (ex - root_x) * math.tan(math.radians(T["dihedral"])) + T["eng_z"] - z0 + 0.0
        bm = bmesh.new()
        lathe(bm, [(el, 0.9 * er, 0.9 * er, 0), (el - 0.6, er, er, 0), (1.2, 0.95 * er, 0.95 * er, 0),
                   (0.0, 0.62 * er, 0.62 * er, 0), (-0.9, 0.42 * er, 0.42 * er, 0), (-1.6, 0.08 * er, 0.08 * er, 0)],
              20, [2, 1, 1, 3, 3], (0, 3))  # the inlet's lip in bare metal, the exhaust and its cone bronze
        obj("engine_%s%d" % (side, i), bm, ["dark", "grey", "metal", "exhaust"], body, (s * ex, le - 0.55 * el, z))
        bm = bmesh.new()
        plate(bm, ((s * ex, le + 0.2, z + er * 0.8), 0.9 * el), ((s * ex, le - 0.4, z + er + 0.6), 0.7 * el), 0.12,
              0.12, "z")
        obj("pylon_%s%d" % (side, i), bm, "grey", body)
    # The horizontal tail.
    span, rc, tc, sweep, y = T["stab"]
    bm = bmesh.new()
    plate(bm, ((s * 0.4 * R, y, 0.35 * H), rc), ((s * span, y - (span - 0.4 * R) * math.tan(math.radians(sweep)),
          0.6 * H), tc), 0.1, 0.09)
    obj("stab_" + side, bm, "grey", body)

# The fin.
height, rc, tc, sweep, y = T["fin"]
bm = bmesh.new()
plate(bm, ((0.0, y, 0.85 * H), rc), ((0.0, y - height * math.tan(math.radians(sweep)), 0.85 * H + height), tc), 0.11,
      0.09, "z")
obj("fin", bm, "grey", body)

# The boom: its hinge under the tail cone; at zero elevation it lies along -Y (aft).
pivot = empty("boom_pivot", body, T["pivot"])
bm = bmesh.new()
# The faired root at the hinge narrowing to the tube (photographs: a fairing about twice the tube's width).
lathe(bm, [(0.9, 0.1, 0.1, 0.1), (0.5, 0.55, 0.5, 0.05), (-0.6, 0.6, 0.55, 0.0), (-2.4, 0.3, 0.3, 0),
           (-BOOM_LEN, 0.24, 0.24, 0)], 16)
boom = obj("boom", bm, "grey", pivot)
for s, side in ((1, "r"), (-1, "l")):  # the ruddevators: a V over the tube near its end, their tips toward the tanker
    bm = bmesh.new()
    plate(bm, ((0.0, -BOOM_LEN + 2.4, 0.0), 1.6), ((s * 2.2, -BOOM_LEN + 1.9, 0.0), 1.0), 0.08, 0.06)
    o = obj("ruddevator_" + side, bm, "rudder", boom)
    o.rotation_euler = (0, -s * math.radians(35), 0)
# The telescope: pale yellow-green, the red, orange and yellow bands that show as it runs out to the contact range,
# the bare-metal nozzle at its tip (photographs; the bands' places inferred).
IL = INNER_LEN
st, mats = [(0.0, 0.15, 0.15, 0)], []
y = IL - 3.35  # the bands' forward end, m from the tip
for i in range(9):  # red, orange, yellow, three times, the telescope's colour between
    st += [(-(IL - y), 0.15, 0.15, 0), (-(IL - y + 0.12), 0.15, 0.15, 0)]
    mats += [0, 1 + i % 3]
    y -= 0.15
st += [(-(IL - y), 0.15, 0.15, 0), (-(IL - 0.5), 0.15, 0.15, 0)]
mats += [0, 0]
# The nozzle assembly: a wider bare-metal sleeve with a dark ring, the tip's ball.
st += [(-(IL - 0.5), 0.2, 0.2, 0), (-(IL - 0.2), 0.2, 0.2, 0), (-(IL - 0.1), 0.18, 0.18, 0), (-IL, 0.21, 0.21, 0),
       (-IL - 0.12, 0.17, 0.17, 0), (-IL - 0.3, 0.07, 0.07, 0)]
mats += [0, 4, 5, 4, 4, 4]
bm = bmesh.new()
lathe(bm, st, 12, mats)
# Its tip half a metre past the tube's end at zero extension: the nozzle `boom_len` from the hinge.
inner = obj("boom_inner", bm, ["telescope", "band_r", "band_o", "band_y", "metal", "dark"], boom,
            (0, -BOOM_LEN + INNER_LEN - 0.2, 0))
empty("nozzle", inner, (0, -INNER_LEN - 0.3, 0))

# The pilot director lights: two rows on the belly behind the nose gear, left elevation, right telescope.
empty("pdl_l", body, (-0.8, nose - 0.2 * L, -0.98 * H))
empty("pdl_r", body, (0.8, nose - 0.2 * L, -0.98 * H))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
print("wrote", OUT)
