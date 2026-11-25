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
# rounded square tube with its panel lines between the hinge's box and the open shroud at its end, the dark swept V
# ruddevators on the shroud, the dark telescope with its range bands, the pale green nozzle housing, the dark ring and
# the machined nozzle. The Re'em's to photographs of IAF 707s: white, yellow door outlines, cabin windows, a small blue
# star, the black tail number, a dark grey boom. The rest is listed in SOURCES.md.
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
        "radome": (138, 147, 159), "boom": (156, 165, 177), "exhaust": (168, 138, 104),
    },
    "reem": {
        "nose": 23.3, "tail": -23.3, "r": 1.88, "h": 2.1,
        "semi": 22.2, "root": 8.2, "tip": 2.0, "sweep": 35.0, "dihedral": 7.0, "wing_y": 3.6, "wing_z": -1.2,
        "engines": [(8.3, 0.85, 4.3), (14.1, 0.85, 4.3)], "eng_z": -2.2,
        "stab": (7.0, 4.6, 1.6, 35.0, -15.5), "fin": (7.6, 7.0, 2.4, 35.0, -13.5),
        "pivot": (0.0, -19.0, -0.5), "boom_len": (47.0 - 18.0) * FT, "ext_max": 18.0 * FT,
        "grey": (226, 229, 231),  # sRGB: white (the Re'em's photographs, reem_2 / reem_4)
        "radome": (226, 229, 231), "boom": (70, 72, 78), "exhaust": (182, 184, 188),
        "tail_no": "275",
    },
}
T = TYPES[KIND]
HERE = os.path.dirname(os.path.abspath(__file__))
# sRGB, roughness, metallic.
PAINT = {
    "grey": (T["grey"], 0.5, 0.0),
    "skin": (T["grey"], 0.5, 0.0),
    "radome": (T["radome"], 0.5, 0.0),
    "boom": (T["boom"], 0.5, 0.0),  # the boom's tube with its panel lines (boom_image)
    "rudder": ((72, 76, 84), 0.5, 0.0),  # the boom's ruddevators: dark grey (boom_outside_3)
    "window": ((22, 26, 30), 0.12, 0.0),
    "dark": ((30, 32, 35), 0.4, 0.0),
    "metal": ((182, 184, 188), 0.3, 0.85),
    "exhaust": (T["exhaust"], 0.35, 0.8),  # the hot section's metal: the KC-46A's bronze-brown, the 707's bare
    "nozzle": ((206, 208, 212), 0.22, 0.9),  # the nozzle's machined aluminium
    "collar": ((150, 178, 140), 0.5, 0.0),  # the nozzle assembly's pale green housing
    "ring": ((58, 64, 78), 0.4, 0.3),  # the dark blue-grey ring between the housing and the nozzle
    "glass": ((14, 16, 20), 0.08, 0.0),  # the boom operator's camera windows
    "black": ((18, 18, 18), 0.5, 0.0),
    "lamp": ((255, 250, 235), 0.3, 0.0),  # the boom's lights (emissive)
    "star": ((255, 255, 255), 0.5, 0.0),
    "yellow": ((222, 178, 30), 0.5, 0.0),
    "telescope": ((58, 62, 60), 0.45, 0.1),  # the boom's inner tube: dark, its range bands (telescope_image)
    "decal": ((255, 255, 255), 0.5, 0.0),
}
ROUNDEL = (0, 0, 256, 256)  # its box in tools/eitam/markings.png (1024 x 512 px)
# The fixed tube ends half a metre before boom_len: the telescope's half metre of tip shows at zero extension.
BOOM_LEN = T["boom_len"] - 0.5
INNER_LEN = T["ext_max"] + 1.0
NOZZLE_LEN = 1.78  # the nozzle assembly: its housing, the ring, the nozzle (boom_outside_3)
TELE_LEN = INNER_LEN + 0.3 - NOZZLE_LEN  # the telescope's tube, to the housing


def lin(c):
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in (v / 255.0 for v in c)]


MATS = {}
SKIN = (1024, 1024)  # px round the fuselage, along it (5 cm a pixel along the KC-46A)


def packed(name, rgb):
    """An image from an (h, w, 3) array (row 0 at v 0), packed into the .glb."""
    import numpy as np

    h, w = rgb.shape[:2]
    img = bpy.data.images.new(name, w, h)
    px = np.ones((h, w, 4), np.float32)
    px[:, :, :3] = rgb
    img.pixels = px.ravel()
    img.file_format = "PNG"
    img.pack()
    return img


def grid(w, h):
    import numpy as np

    return np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)


def skin_image():
    """The fuselage's paint as an image on its lathe's UVs (u round from the right side, v from the tail): the paint,
    a shade darker toward the belly (the photographs' shaded underside), faint panel lines (the circumferential joints,
    two lap joints a side, closer on the tail cone), the doors' outlines (the Re'em's yellow), access panels on the
    tail cone's belly round the boom, the boom's hinge opening's dark seal, and the Re'em's cabin windows
    (photographs; places inferred)."""
    import numpy as np

    w, h = SKIN
    nose, tail = T["nose"], T["tail"]
    length = nose - tail
    uu, vv = grid(w, h)
    ang = uu * 360.0  # deg round from the right side, 90 the top
    y = tail + vv * length
    shade = 1.0 - 0.1 * np.clip(-np.sin(np.radians(ang)), 0.0, None)
    line = np.zeros((h, w), bool)
    px_m = length / h
    px_a = 360.0 / w
    cone = tail + 0.26 * length  # the tail cone's forward end
    for yy in np.arange(cone, nose - 0.1 * length, 5.3):  # the circumferential joints
        line |= np.abs(y - yy) < px_m
    for yy in np.arange(tail + 0.03 * length, cone, 1.6):  # the tail cone's
        line |= np.abs(y - yy) < px_m
    for a in (35, 145, 215, 325):  # the lap joints
        line |= (np.abs(ang - a) < px_a) & (y > tail + 0.03 * length) & (y < nose - 0.1 * length)

    def box(y_fwd, y_aft, a_mid, a_half):
        """A panel's outline."""
        inside = (y < y_fwd + px_m) & (y > y_aft - px_m) & (np.abs(ang - a_mid) <= a_half + px_a)
        edge = (np.abs(y - y_fwd) < px_m) | (np.abs(y - y_aft) < px_m) | (np.abs(np.abs(ang - a_mid) - a_half) < px_a)
        return inside & edge

    r = T["r"]
    doors = np.zeros((h, w), bool)
    door_a = math.degrees(0.95 / r)  # a 1.9 m door's half height in degrees round the side
    for a_mid in (5.0, 175.0):  # the right side and the left (round from the right, up)
        for yy in (nose - 0.13 * length, tail + 0.3 * length):
            doors |= box(yy, yy - 1.05, a_mid, door_a)
    if KIND == "kc46":
        doors |= box(nose - 0.2 * length, nose - 0.2 * length - 3.4, 170.0, math.degrees(1.3 / r))  # the cargo door
    py = T["pivot"][1]
    for k, (yy, a, l, wa) in enumerate(((py + 4.0, 270, 0.8, 9), (py + 5.4, 262, 0.6, 5), (py + 5.4, 278, 0.6, 5),
                                        (py + 1.8, 250, 0.7, 6), (py + 1.8, 290, 0.7, 6), (py + 7.5, 270, 1.0, 7))):
        line |= box(yy, yy - l, a, wa)  # the access panels round the boom (boom_outside_3)
    seal = box(py + 0.9, py - 1.2, 270.0, math.degrees(0.48 / r))  # the hinge opening's seal
    seal |= np.roll(seal, 1, axis=1)
    base = np.array(T["grey"], float) / 255.0
    rgb = base[None, None, :] * shade[:, :, None]
    rgb[line] *= 0.9 if KIND == "reem" else 0.93
    if KIND == "reem":  # the doors outlined in yellow, the cabin windows a dark row a side
        rgb[doors] = np.array(lin((236, 190, 50))) ** (1 / 2.2)
        win = np.zeros((h, w), bool)
        for a in (12.0, 168.0):
            win |= (np.abs(ang - a) < 1.6) & (np.abs(((y - tail) % 0.508) - 0.25) < 0.1)
        win &= (y < nose - 0.14 * length) & (y > tail + 0.31 * length)
        win &= np.abs(y - (tail + 0.55 * length)) > 2.5  # the over-wing exits' gap (inferred)
        rgb[win] = 0.1
    else:
        rgb[doors] *= 0.9
    rgb[seal] = 0.08
    return packed("skin", rgb)


def boom_image():
    """The boom's tube on its lathe's UVs (u round, v from the hinge to the end): its paint, a joint every 1.2 m, a
    seam along each rounded corner and access panels on its sides (boom_outside_3; places inferred)."""
    import numpy as np

    w, h = 128, 1024
    uu, vv = grid(w, h)
    along = vv * (BOOM_LEN + 0.9)
    line = np.zeros((h, w), bool)
    for yy in np.arange(1.6, BOOM_LEN, 1.2):
        line |= np.abs(along - yy) < 0.012
    for u in (0.125, 0.375, 0.625, 0.875):
        line |= np.abs(uu - u) < 0.6 / w
    for yy, l in ((2.2, 0.7), (4.4, 0.5), (6.6, 0.9), (BOOM_LEN - 0.4, 0.8)):
        for u in (0.0, 0.5, 1.0):
            inside = (along > yy - 0.01) & (along < yy + l + 0.01) & (np.abs(uu - u) < 0.065)
            edge = (np.abs(along - yy) < 0.012) | (np.abs(along - yy - l) < 0.012) | (np.abs(np.abs(uu - u) - 0.06) < 0.6 / w)
            line |= inside & edge
    base = np.array(T["boom"], float) / 255.0
    rgb = np.broadcast_to(base, (h, w, 3)).copy()
    rgb[line] *= 0.82
    return packed("boom", rgb)


def telescope_image():
    """The telescope on its lathe's UVs (u round from the right, v from its inner end to the nozzle's housing): dark,
    and on each side the range bands toward the nozzle: from the housing pale yellow-green, orange, red, orange with
    black ticks, yellow and green ticks; a dark rail along each side's middle (boom_outside_3; the KC-46A's). The
    Re'em's: red and yellow rings near the nozzle (reem_2)."""
    import numpy as np

    w, h = 64, 1024
    uu, vv = grid(w, h)
    d = (1.0 - vv) * TELE_LEN  # m from the housing
    side = np.abs(np.sin(uu * 2 * math.pi)) < 0.8
    base = np.array(PAINT["telescope"][0], float) / 255.0
    rgb = np.broadcast_to(base, (h, w, 3)).copy()
    col = lambda c: np.array(c, float) / 255.0  # noqa: E731
    if KIND == "kc46":
        zones = ((0.0, 1.2, (196, 206, 120), False), (1.2, 1.8, (232, 118, 30), False),
                 (1.8, 2.8, (214, 58, 40), False), (2.8, 3.2, (232, 118, 30), True),
                 (3.2, 3.5, (236, 196, 40), True), (3.5, 3.8, (90, 170, 60), True))
        for d0, d1, c, ticks in zones:
            z = side & (d >= d0) & (d < d1)
            rgb[z] = col(c)
            if ticks:
                rgb[z & ((d % 0.08) < 0.025)] = 0.05
        rgb[np.abs(np.cos(uu * 2 * math.pi)) > 0.995] = 0.06  # the rails
    else:
        for i in range(8):
            rgb[(d >= i * 0.25) & (d < i * 0.25 + 0.25)] = col((200, 40, 30) if i % 2 else (236, 196, 40))
    return packed("telescope", rgb)


def star_image():
    """The roundel's star alone, its ring cut away (the Re'em's: reem_2)."""
    import numpy as np

    src = bpy.data.images.load(os.path.join(HERE, "..", "eitam", "markings.png"))
    w, h = src.size
    px = np.array(src.pixels[:], np.float32).reshape(h, w, 4)
    yy, xx = np.mgrid[0:h, 0:w]
    ring = np.hypot(xx - 128, (h - 1 - yy) - 128) > 104  # the image's rows from its bottom
    px[ring, 3] = 0.0
    img = bpy.data.images.new("star", w, h, alpha=True)
    img.pixels = px.ravel()
    img.file_format = "PNG"
    img.pack()
    return img


IMAGES = {"skin": skin_image, "boom": boom_image, "telescope": telescope_image}


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
    if name in IMAGES:  # a painted image on the lathe's UVs
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = IMAGES[name]()
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if name == "lamp":
        bsdf.inputs["Emission Color"].default_value = (*lin(rgb), 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.5
    if name in ("decal", "star"):  # the markings cut out by their alpha (glTF MASK), as the Eitam's
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = star_image() if name == "star" else bpy.data.images.load(
            os.path.join(HERE, "..", "eitam", "markings.png"))
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
        p.use_smooth = me.materials[p.material_index].name not in ("decal", "star", "rudder")
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


def lathe(bm, stations, n=24, mats=None, caps=None, sq=2.0, vspan=None):
    """Rings along Y: (y, rx, rz, zc) each; the ends closed. `mats`: each segment's material index; `caps` the first
    and the last ring's (else the end segments'). `sq`: the section's superellipse exponent (2 an ellipse, 4 a
    rounded square). `vspan`: the length v runs 0 to 1 over (else the first ring to the last)."""
    e = 2.0 / sq

    def round_(c):
        return math.copysign(abs(c) ** e, c)

    rings = []
    for y, rx, rz, zc in stations:
        rings.append([bm.verts.new((rx * round_(math.cos(a)), y, zc + rz * round_(math.sin(a)))) for a in
                      (2 * math.pi * j / n for j in range(n))])
    uv = bm.loops.layers.uv.verify()  # u round from the right side (0.25 the top), v along from the first ring
    y0, y1 = stations[0][0], stations[-1][0]
    if vspan is not None:
        y1 = y0 + vspan
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
lathe(bm, FUSE, mats=[0] * (len(FUSE) - 3) + [1, 1], caps=(2, 1))  # the last two segments: the radome
body = obj(KIND, bm, ["skin", "radome", "dark"])  # the tail cone's tip: the APU's exhaust


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


# The paint on the fuselage: the flight deck's windows, the belly line, the roundels (KC-46A photographs: IAF roundels
# where the USAF star is, inferred; the Re'em's photographs: a small blue star aft above the windows and on the nose).
bm = bmesh.new()
uv = bm.loops.layers.uv.new("uv")
for s in (1, -1):
    a0, a1 = (22, 36) if s > 0 else (144, 158)
    band(bm, nose - 0.078 * L, nose - 0.05 * L, a0, a1, 0)  # the side windows
marks = [(tail + 0.3 * L, 1.1, 0.15)] if KIND == "kc46" else [(tail + 0.33 * L, 0.45, 0.45), (nose - 0.1 * L, 0.3, 0.2)]
for y, rr, up in marks:
    for s in (1, -1):
        x = s * (section(y)[0] + 0.03)
        zc = section(y)[2] + up * H
        pts = [(x, y - s * rr, zc - rr), (x, y + s * rr, zc - rr), (x, y + s * rr, zc + rr), (x, y - s * rr, zc + rr)]
        decal(bm, uv, pts, ROUNDEL, 2)
band(bm, nose - 0.057 * L, nose - 0.047 * L, 36, 144, 0)  # the windshield's front panels
if KIND == "kc46":
    band(bm, T["wing_y"] - T["root"], T["pivot"][1] + 3.2, -91.2, -88.8, 1, 8, 0.05)  # the yellow belly line
obj("paint", bm, ["window", "yellow", "decal" if KIND == "kc46" else "star"], body)
# The boom operator's camera fairing on the belly before the hinge: a grey pod, its dark window band aft and down
# (boom_outside_3); the Re'em's at the same place (inferred).
bm = bmesh.new()
yc = T["pivot"][1] + 2.6
rz = section(yc)
lathe(bm, [(yc + 1.0, 0.05, 0.04, 0), (yc + 0.5, 0.5, 0.32, 0), (yc - 0.5, 0.5, 0.36, 0),
           (yc - 0.9, 0.3, 0.22, 0)], 16, caps=(0, 1), sq=3.0)
obj("camera_fairing", bm, ["grey", "glass"], body, (0, 0, rz[2] - rz[1] + 0.05))
bm = bmesh.new()  # the windows: a dark band round its aft lower face
lathe(bm, [(yc - 0.52, 0.53, 0.38, 0.0), (yc - 0.86, 0.33, 0.25, 0.0)], 16, sq=3.0)
for f in list(bm.faces):
    if f.calc_center_median().z > -0.05:  # only the lower half
        bm.faces.remove(f)
obj("camera_windows", bm, "glass", body, (0, 0, rz[2] - rz[1] + 0.05))
# The antennas: blades on the spine and the belly (photographs; places inferred).
for y, up in ((nose - 0.25 * L, 1), (0.0, 1), (-6.0, 1), (nose - 0.3 * L, -1), (-9.0, -1), (-3.0, -1),
              (nose - 0.2 * L - 2.5, -1)):
    rx, rz, zc = section(y)
    z = zc + up * (rz - 0.02)
    bm = bmesh.new()
    plate(bm, ((0.0, y + 0.25, z), 0.55), ((0.0, y - 0.05, z + up * 0.4), 0.3), 0.14, 0.12, "z")
    obj("antenna", bm, "dark", body)
# The tail number on the fin, black (the Re'em's photographs).
if "tail_no" in T:
    height, rc, tc, sweep, y = T["fin"]
    for s in (1, -1):
        h_at = 0.3 * height
        y_at = y - h_at * math.tan(math.radians(sweep)) - 0.45 * (rc + (tc - rc) * 0.3)
        c = rc + (tc - rc) * 0.3  # the chord there; the text on the fin's thickest line, 3 cm off it (plate)
        half = (0.11 + (0.09 - 0.11) * 0.3) * c / 2
        bpy.ops.object.text_add(location=(s * (half + 0.03), y_at, 0.85 * H + h_at))
        t = bpy.context.object
        t.data.body = T["tail_no"]
        t.data.size = 0.9
        t.data.align_x = "CENTER"
        t.rotation_euler = (math.radians(90), 0, math.radians(90 * s))  # its face outward
        bpy.ops.object.convert(target="MESH")
        t.name = "tail_number"
        t.data.materials.append(material("black"))
        t.parent = body

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
        plate(bm, ((s * ex, le + 0.6, z + er * 0.7), 0.95 * el), ((s * ex, le - 0.6, z + er + 0.7), 0.85 * el),
              0.16, 0.12, "z")  # the pylon: from the nacelle's top back under the wing (photographs)
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
def cube(bm, centre, size, k):
    """A box `size` (x, y, z) at `centre`, material index k."""
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]:
        v.co = (centre[0] + v.co.x * size[0], centre[1] + v.co.y * size[1], centre[2] + v.co.z * size[2])
    for f in {f for v in r["verts"] for f in v.link_faces}:
        f.material_index = k


# The boom (boom_outside_3): a rounded square tube with its panel lines (boom_image); the root a wider box in the
# hinge's opening; its end a wider open shroud, dark inside, that the telescope runs out of; the ruddevators on the
# shroud.
bm = bmesh.new()
lathe(bm, [(0.9, 0.12, 0.12, 0.1), (0.6, 0.36, 0.4, 0.05), (-0.5, 0.36, 0.38, 0.0), (-1.4, 0.26, 0.28, 0),
           (-(BOOM_LEN - 2.3), 0.26, 0.28, 0), (-(BOOM_LEN - 1.7), 0.37, 0.37, 0), (-BOOM_LEN, 0.38, 0.38, 0),
           (-BOOM_LEN, 0.31, 0.31, 0), (-(BOOM_LEN - 0.4), 0.3, 0.3, 0)], 16,
      [0] * 7 + [1], (0, 1), sq=4.0, vspan=-(BOOM_LEN + 0.9))  # the shroud's inside dark
boom = obj("boom", bm, ["boom", "dark"], pivot)
for s, side in ((1, "r"), (-1, "l")):  # the ruddevators: a V on the shroud, swept, their tips toward the tanker
    bm = bmesh.new()
    plate(bm, ((s * 0.3, -BOOM_LEN + 1.75, 0.0), 1.35), ((s * 1.95, -BOOM_LEN + 1.35, 0.0), 0.85), 0.1, 0.07)
    o = obj("ruddevator_" + side, bm, "rudder", boom)
    o.rotation_euler = (0, -s * math.radians(35), 0)
# The telescope: dark, its range bands toward the nozzle (telescope_image); then the nozzle assembly: the pale green
# housing, a dark ring, the machined aluminium nozzle stepping down to its tip, its latches and its light
# (boom_outside_3; sizes by eye).
bm = bmesh.new()
lathe(bm, [(0.0, 0.15, 0.15, 0), (-TELE_LEN, 0.15, 0.15, 0)], 16, sq=3.0)
inner = obj("boom_inner", bm, "telescope", boom, (0, -BOOM_LEN + INNER_LEN - 0.2, 0))
y0 = -TELE_LEN
bm = bmesh.new()
lathe(bm, [(y0 + 0.02, 0.17, 0.17, 0), (y0 - 0.1, 0.21, 0.22, 0), (y0 - 0.72, 0.21, 0.22, 0)], 16, sq=3.5)
NOZ = [(0.72, 0.17, 1), (0.86, 0.17, 1), (0.86, 0.19, 3), (0.94, 0.19, 3), (0.94, 0.2, 2), (1.36, 0.2, 2),
       (1.4, 0.16, 2), (1.56, 0.15, 2), (1.6, 0.12, 2), (1.72, 0.12, 2), (NOZZLE_LEN, 0.08, 2)]
lathe(bm, [(y0 - d, r, r, 0) for d, r, _ in NOZ], 20, [k for _, _, k in NOZ[1:]], (1, 3))
cube(bm, (0.0, y0 - 0.4, 0.25), (0.14, 0.5, 0.08), 0)  # the housing's top fitting
cube(bm, (0.0, y0 - 0.12, 0.3), (0.06, 0.06, 0.04), 4)  # the nozzle's light (inferred)
for s in (1, -1):
    cube(bm, (s * 0.15, y0 - 1.5, 0.0), (0.06, 0.2, 0.07), 3)  # the toggle latches
obj("nozzle_assembly", bm, ["collar", "ring", "nozzle", "dark", "lamp"], inner)
empty("nozzle", inner, (0, -INNER_LEN - 0.3, 0))

# The pilot director lights: two rows on the belly behind the nose gear, left elevation, right telescope.
empty("pdl_l", body, (-0.8, nose - 0.2 * L, -0.98 * H))
empty("pdl_r", body, (0.8, nose - 0.2 * L, -0.98 * H))

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
print("wrote", OUT)
