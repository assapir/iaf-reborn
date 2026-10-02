# Rig the andertan "Lockheed Martin F35 Lightning II" model (Sketchfab, CC BY 4.0) for the game
# (docs/adding-a-plane.md §2, docs/f35i.md): real size, the game's frame, the moving parts cut out and
# named from PART_NAMES with their hinge helpers, the nozzle / gun / station / eye / wheel-height
# points, blended canopy glass, a decimated nozzle interior. Writes a glTF (+ .bin + textures).
#
#   blender -b --python tools/f35i/rig.py -- <sketchfab scene.gltf> <out dir>
#
# Coordinates below are Blender's (Z up, nose +Y, metres) after the normalisation; the glTF export
# turns them into the game's (+Y up, nose -Z).
import math
import sys

import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

SRC, OUT = sys.argv[sys.argv.index("--") + 1:][:2]
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
# The IAF skin: our own textures replace every texture of the download (they were photographs of real
# jets, some with photographers' watermarks; docs/f35i.md §2).
SKIN_GREY = np.array([0.37, 0.39, 0.41])  # F-35 low-observable grey, matte (sRGB, before the baked shading)
TAIL_NUMBER = "937"  # 116 Sqn "Lions of the South" (F-35I tails run 901-9xx)
# Low-visibility markings as on the IAF's F-35Is (photos, docs/f35i.md §5): a dark grey Magen David on a lighter
# grey disc, dark grey numbers, a subdued squadron badge.
STAR_GREY = np.array([0.17, 0.18, 0.19])
DISC_GREY = np.array([0.46, 0.48, 0.50])
NUMBER_GREY = (0.16, 0.17, 0.18)
LENGTH = 15.67  # m (Lockheed Martin)
# The aircraft origin (≈ centre of gravity) in the normalised model: the game's rig position.
ORIGIN = Vector((0.0, -1.0, 1.85))


def normalise():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.context.scene.objects if o.type != 'MESH']:
        bpy.data.objects.remove(o)
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    mn = Vector(map(min, *pts))
    mx = Vector(map(max, *pts))
    k = LENGTH / (mx.y - mn.y)
    # Sketchfab's nose points -Y: turn it to +Y, wheels on z = 0, centred.
    m = Matrix.Scale(k, 4) @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    for o in meshes:
        o.data.transform(m @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    return {o.name.removeprefix("Object_"): o for o in meshes}


def bisect(objs, region, co, no):
    """Cut the faces of `objs` whose centre passes `region` with the plane (co, no)."""
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        faces = [f for f in bm.faces if region(f.calc_center_median())]
        if faces:
            geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
        bm.to_mesh(o.data)
        bm.free()


def extract(objs, test, name):
    """A new object of the faces of `objs` whose centre passes `test` (removed from `objs`)."""
    parts = []
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        sel = [f for f in bm.faces if test(f.calc_center_median())]
        if not sel:
            bm.free()
            continue
        for f in bm.faces:
            f.select = f in sel
        bm.to_mesh(o.data)
        bm.free()
        bpy.context.view_layer.objects.active = o
        for x in bpy.context.selected_objects:
            x.select_set(False)
        o.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.separate(type='SELECTED')
        bpy.ops.object.mode_set(mode='OBJECT')
        parts += [x for x in bpy.context.selected_objects if x is not o]
    return join(parts, name)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        raise SystemExit(f"no geometry for {name}")
    for x in bpy.context.selected_objects:
        x.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def _mat(name, colour, metallic=0.0, roughness=0.5, image=None, clip=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if image is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if clip:
            mat.node_tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.blend_method = 'CLIP'
        mat.node_tree.nodes.active = tex
    return mat


def _image(name, rgba):
    """A packed image from an (h, w, 4) float array (rows top to bottom)."""
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).ravel().astype(np.float32))
    img.pack()
    return img


def _smooth(edge, x):
    return np.clip((x - edge[0]) / (edge[1] - edge[0]), 0.0, 1.0)


def roundel(n=512):
    """The IAF roundel, low-visibility: a dark grey Magen David (two triangle outlines) on a grey disc."""
    ys, xs = np.mgrid[0:n, 0:n]
    px = (xs + 0.5) / n * 2 - 1
    py = 1 - (ys + 0.5) / n * 2
    aa = 2.0 / n
    r = np.hypot(px, py)
    disc = _smooth((1.0, 1.0 - aa), r)
    big_r, width = 0.78, 0.13  # circumradius, stroke (of the disc radius)

    def triangle(rot):
        # Signed distance inside an equilateral triangle of circumradius big_r (inradius big_r / 2).
        d = np.full(px.shape, np.inf)
        for k in range(3):
            a = rot + k * 2 * math.pi / 3
            d = np.minimum(d, big_r / 2 - (px * math.cos(a) + py * math.sin(a)))
        return d

    star = np.zeros_like(px)
    for rot in (-math.pi / 2, math.pi / 2):
        d = triangle(rot)
        star = np.maximum(star, _smooth((-aa, aa), d) * _smooth((width + aa, width - aa), d))
    rgb = DISC_GREY * (1 - star[..., None]) + STAR_GREY * star[..., None]
    return np.dstack([rgb, disc])


def retexture(m):
    """Every textured / skin material of the download -> ours: F-35 grey with ambient occlusion baked from
    the model's own geometry (a fresh UV atlas per object), dark metal for the nozzle and the engine face."""
    sc = bpy.context.scene
    metal = _mat("nozzle_metal", (0.10, 0.10, 0.11), metallic=0.85, roughness=0.35)
    for k in ("50", "51", "52", "53"):
        m[k].data.materials.clear()
        m[k].data.materials.append(metal)
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
    sc.render.bake.margin = 8
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = 0.6
    def box(o):
        vs = [v.co for v in o.data.vertices]
        return Vector(map(min, *vs)), Vector(map(max, *vs))

    meshes = [o for o in sc.objects if o.type == 'MESH']
    for k, size in (("38", 2048), ("40", 2048), ("42", 2048), ("37", 2048), ("43", 2048), ("45", 2048),
                    ("29", 1024), ("30", 1024), ("41", 1024), ("48", 1024), ("49", 1024), ("36", 1024)):
        o = m[k]
        for x in bpy.context.selected_objects:
            x.select_set(False)
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
        bpy.ops.object.mode_set(mode='OBJECT')
        img = bpy.data.images.new(f"skin_{k}", size, size)
        mat = _mat(f"skin_{k}", tuple(SKIN_GREY), metallic=0.15, roughness=0.55, image=img)
        o.data.materials.clear()
        o.data.materials.append(mat)
        # The download stacks coincident copies of some surfaces (both fins are 48 + 49): hide an object's
        # twins while baking it, or each blacks the other out.
        a, b = box(o)
        twins = [x for x in meshes if x is not o and (box(x)[0] - a).length < 0.02 and (box(x)[1] - b).length < 0.02]
        for x in twins:
            x.hide_render = True
        if k in ("48", "49"):
            ao = np.full((size, size), 1.0)  # the thin fins: AO rays hit the opposite face, so no bake
        else:
            bpy.ops.object.bake(type='AO')
            ao = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)[..., 0]
        for x in twins:
            x.hide_render = False
        shade = 0.5 + 0.5 * ao
        rgb = np.clip(SKIN_GREY[None, None, :] * shade[..., None], 0, 1)
        img.pixels.foreach_set(np.dstack([rgb, np.ones((size, size))]).astype(np.float32).ravel())
        img.pack()
    # Anything else still textured with a downloaded image: plain skin grey (no download image is exported).
    plain = _mat("skin_plain", tuple(SKIN_GREY * 0.85), metallic=0.15, roughness=0.55)
    for o in [o for o in sc.objects if o.type == 'MESH']:
        for i, mat in enumerate(o.data.materials):
            if mat and mat.use_nodes and any(nd.type == 'TEX_IMAGE' and nd.image and not nd.image.name.startswith("skin_")
                                             for nd in mat.node_tree.nodes):
                o.data.materials[i] = plain
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'


def _hit(origin, direction):
    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    ok, loc, nor, _i, _o, _m = sc.ray_cast(dg, Vector(origin), Vector(direction).normalized())
    if not ok:
        raise SystemExit(f"decal ray {origin} -> {direction} hit nothing")
    nor = Vector(nor)
    if nor.dot(Vector(direction)) > 0:
        nor = -nor
    return loc, nor.normalized()


def decal(name, mat, origin, direction, w, h, right, grid=8):
    """`mat` on the first surface hit from `origin` along `direction`, its image's x along `right`: an
    N x N grid whose vertices are each projected onto the skin (so it follows curved panels), 8 mm off it."""
    loc, n = _hit(origin, direction)
    r = (Vector(right) - n * n.dot(Vector(right))).normalized()
    up = n.cross(r)
    sc = bpy.context.scene
    dg = bpy.context.evaluated_depsgraph_get()
    vs, uvs = [], []
    for j in range(grid + 1):
        for i in range(grid + 1):
            u, v = i / grid, j / grid
            p = loc + r * (u - 0.5) * w + up * (v - 0.5) * h
            ok, hit, hn, *_ = sc.ray_cast(dg, p + n * 0.4, -n, distance=0.8)
            if ok:
                hn = Vector(hn) if Vector(hn).dot(n) > 0 else -Vector(hn)
                p = Vector(hit) + hn.normalized() * 0.008
            else:
                p = p + n * 0.008
            vs.append(p)
            uvs.append((u, v))
    faces = [(j * (grid + 1) + i, j * (grid + 1) + i + 1, (j + 1) * (grid + 1) + i + 1, (j + 1) * (grid + 1) + i)
             for j in range(grid) for i in range(grid)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(vs, [], faces)
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[me.loops[li].vertex_index]
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    return o


def text_decal(name, body, mat, origin, direction, height, right):
    """Block digits (Blender's built-in font) as a flat mesh on the surface hit from `origin`."""
    loc, n = _hit(origin, direction)
    r = (Vector(right) - n * n.dot(Vector(right))).normalized()
    up = n.cross(r)
    bpy.ops.object.text_add()
    t = bpy.context.active_object
    t.data.body = body
    t.data.align_x = 'CENTER'
    t.data.align_y = 'CENTER'
    t.data.size = height
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.active_object
    o.name = name
    basis = Matrix((r, up, n)).transposed().to_4x4()
    o.data.transform(Matrix.Translation(loc + n * 0.014) @ basis)
    o.matrix_world = Matrix.Identity(4)
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o


def markings():
    """IAF markings: roundels on the upper left / lower right wing and both sides of the fuselage, the tail
    number and the 116 Sqn badge on both fins (outer faces)."""
    rnd = _mat("iaf_roundel", (1, 1, 1), metallic=0.15, roughness=0.75, image=_image("iaf_roundel", roundel()), clip=True)
    # The 116 Sqn badge in low-visibility greys (its luminance mapped to dark .. mid grey), alpha kept.
    src = bpy.data.images.load(os.path.join(ASSETS, "sqn116.png"))
    w, h = src.size
    px = np.array(src.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    lum = px[..., :3] @ np.array([0.30, 0.59, 0.11])
    grey = 0.15 + 0.45 * lum
    badge = _mat("sqn116", (1, 1, 1), metallic=0.15, roughness=0.75,
                 image=_image("sqn116_lowvis", np.dstack([grey, grey * 1.02, grey * 1.05, px[..., 3]])), clip=True)
    number = _mat("tail_number", NUMBER_GREY, metallic=0.15, roughness=0.75)
    decal("roundel_wing_upper_left", rnd, (-3.6, -2.7, 10), (0, 0, -1), 0.8, 0.8, (0, 1, 0))
    decal("roundel_wing_lower_right", rnd, (3.6, -2.7, -10), (0, 0, 1), 0.8, 0.8, (0, -1, 0))
    for s in (1, -1):
        # The big roundel on the intake under the canopy, the full number on the nose, the last two digits
        # at the fin tip, the badge on the fin.
        decal(f"roundel_side_{s}", rnd, (8 * s, 2.3, 1.95), (-s, 0, 0), 0.8, 0.8, (0, s, 0))
        text_decal(f"nose_number_{s}", TAIL_NUMBER, number, (8 * s, 5.55, 2.3), (-s, 0, 0), 0.3, (0, s, 0))
        text_decal(f"fin_number_{s}", TAIL_NUMBER[-2:], number, (8 * s, -6.0, 4.15), (-s, 0, 0), 0.26, (0, s, 0))
        # Fins: canted outwards; rays from outside hit the outer faces (forward of the rudder hinge).
        decal(f"badge_{s}", badge, (8 * s, -5.5, 3.4), (-s, 0, 0), 0.7, 0.7, (0, s, 0))


def mirror(p):
    return Vector((-p.x, p.y, p.z))


def main():
    m = normalise()
    retexture(m)
    markings()
    skins = [m[k] for k in ("38", "40", "42", "29", "30", "41")]

    # Flaperons: aft of the y = -3.73 panel line, from the wing root (x 2.2) to x 4.38.
    wing = lambda c: abs(c.x) > 2.0 and c.y < -3.0 and 1.9 < c.z < 2.45
    bisect(skins, wing, (0, -3.73, 0), (0, 1, 0))
    for s in (1, -1):
        bisect(skins, wing, (4.38 * s, 0, 0), (1, 0, 0))
    flap = lambda s: (lambda c: 2.2 < c.x * s < 4.38 and -4.6 < c.y < -3.73 and 1.9 < c.z < 2.45)
    ail = {"AilerR": extract(skins, flap(1), "AilerR"), "AilerL": extract(skins, flap(-1), "AilerL")}

    # Stabilators (all-moving): outboard of x 1.02, aft of the swept leading edge (root (1.73, -5.0), tip
    # (3.66, -6.3)).
    stab_zone = lambda c: abs(c.x) > 0.9 and c.y < -4.5 and 2.1 < c.z < 2.45
    le_no = Vector((1.3, 1.93, 0)).normalized()  # horizontal normal of the leading edge line, pointing forward
    for s in (1, -1):
        bisect(skins, stab_zone, (1.02 * s, 0, 0), (1, 0, 0))
        bisect(skins, stab_zone, (1.73 * s, -5.0, 0), (le_no.x * s, le_no.y, 0))
    bisect(skins, stab_zone, (0, -5.0, 0), (0, 1, 0))  # inboard of x 1.73 the edge kinks back: stay aft of -5.0
    aft_of_le = lambda c, s: (Vector((c.x * s, c.y, 0)) - Vector((1.73, -5.0, 0))).dot(le_no) < 1e-4
    stab = lambda s: (lambda c: c.x * s > 1.02 and c.y < -5.0 and 2.1 < c.z < 2.45 and aft_of_le(c, s))
    elev = {"ElevaR": extract(skins, stab(1), "ElevaR"), "ElevaL": extract(skins, stab(-1), "ElevaL")}

    # Rudders: aft of the fins' hinge line (root (1.52, -5.55, 2.4) to tip (2.29, -6.8, 4.46)).
    fins = [m["48"], m["49"]]
    rud = {}
    for s, name in ((1, "Rudde"), (-1, "RuddeL")):
        a, b = Vector((1.52 * s, -5.55, 2.40)), Vector((2.29 * s, -6.80, 4.46))
        le, te = Vector((1.50 * s, -3.81, 2.34)), Vector((1.52 * s, -6.07, 2.40))
        n = (b - a).cross(te - le).normalized()  # ~ the fin's normal
        cut = (b - a).cross(n).normalized()
        if cut.dot(Vector((0, -1, 0))) < 0:
            cut = -cut  # points aft
        side = lambda c, s=s: c.x * s > 0 and c.z > 2.3
        bisect(fins, side, a, cut)
        rud[name] = (extract(fins, lambda c, s=s, a=a, cut=cut: c.x * s > 0 and c.z > 2.3 and (c - a).dot(cut) > 1e-4, name), a, b)

    # Gear: main legs (wheel, strut, brace, hub), the doors (static, hidden once up), the nose leg.
    main_l = [m[k] for k in ("18", "19", "20")]
    main_r = [m[k] for k in ("66", "67", "68", "70", "72", "74", "75", "77", "79", "81", "83", "85", "87", "89", "91")]
    ldg_l, ldg_r = join(main_l, "LdgL"), join(main_r, "LdgR")
    ldg_dr = join([m["64"], m["8"]], "LdgDr")
    nose_strut = extract([m["45"]], lambda c: 4.0 < c.y < 5.2 and c.z < 1.05 and abs(c.x) < 0.3, "nose_strut")
    ldg_f = join([m["44"], m["46"], m["47"], nose_strut], "LdgF")

    # Canopy: the bubble, its bow and the frame strip; tinted blended glass on the bubble.
    canopy = join([m["33"], m["34"], m["54"]], "canopy")
    glass = bpy.data.materials.new("canopy_glass")
    glass.use_nodes = True
    bsdf = glass.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.35, 0.30, 0.18, 1.0)
    bsdf.inputs["Alpha"].default_value = 0.4
    bsdf.inputs["Roughness"].default_value = 0.1
    glass.blend_method = 'BLEND'
    for i, mat in enumerate(canopy.data.materials):
        if mat and mat.name.startswith("Whitish_grey"):
            canopy.data.materials[i] = glass

    # Pilot (the model has none; ejection throws one seat per pilot part): helmet + torso.
    eye = Vector((0.0, 3.35, 2.85))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.14, location=eye + Vector((0, 0, 0.02)))
    head = bpy.context.active_object
    bpy.ops.mesh.primitive_cube_add(size=1, location=eye + Vector((0, -0.1, -0.35)))
    torso = bpy.context.active_object
    torso.scale = (0.45, 0.3, 0.55)
    for o in (head, torso):  # bake the primitives' transforms: every mesh here is in world coordinates
        for x in bpy.context.selected_objects:
            x.select_set(False)
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    suit = bpy.data.materials.new("pilot")
    suit.diffuse_color = (0.25, 0.27, 0.2, 1)
    suit.use_nodes = True
    suit.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.27, 0.2, 1)
    for o in (head, torso):
        o.data.materials.append(suit)
    pilot = join([head, torso], "pilot")

    # The nozzle interior is 38k of the 83k triangles: decimate it.
    noz = m["52"]
    dec = noz.modifiers.new("dec", 'DECIMATE')
    dec.ratio = 0.08
    bpy.context.view_layer.objects.active = noz
    bpy.ops.object.modifier_apply(modifier="dec")

    # Root = every remaining mesh (the body), origin at ORIGIN.
    parts = {**ail, **elev, "LdgL": ldg_l, "LdgR": ldg_r, "LdgF": ldg_f, "LdgDr": ldg_dr, "canopy": canopy, "pilot": pilot}
    parts.update({k: v[0] for k, v in rud.items()})
    rest = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name not in parts]
    root = join(rest, "f35i")
    shift = Matrix.Translation(-ORIGIN)
    for o in [root, *parts.values()]:
        o.data.transform(shift)

    def place(o, pivot):
        """Origin of part `o` on its hinge `pivot` (normalised coords), parented to the root."""
        p = pivot - ORIGIN
        o.data.transform(Matrix.Translation(-p))
        o.location = p
        o.parent = root

    def empty(name, p):
        e = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(e)
        e.location = p - ORIGIN
        e.parent = root
        e.empty_display_size = 0.05

    def hinge(name, pivot, axis):
        """`<name>1` / `<name>2` on the hinge line, ordered so the game's axis (nearer -> farther from
        the origin) is `axis`."""
        d = Vector(axis).normalized()
        q = pivot - ORIGIN
        # Along the line the distance to the origin grows once past t = -q·d: start there.
        t = max(0.0, -q.dot(d) + 0.05)
        empty(name + "1", pivot + d * t)
        empty(name + "2", pivot + d * (t + 1.0))

    for s, n in ((1, "AilerR"), (-1, "AilerL")):
        piv = Vector((2.27 * s, -3.73, 2.2))
        place(parts[n], piv)
        hinge(n, piv, (s, 0, 0))
    for s, n in ((1, "ElevaR"), (-1, "ElevaL")):
        piv = Vector((1.1 * s, -6.3, 2.27))
        place(parts[n], piv)
        hinge(n, piv, (s, 0, 0))
    for n, (o, a, b) in rud.items():
        place(o, a)
        hinge(n, a, b - a)
    # Gear legs fold forward (F-35A): the game turns LdgL by +g, LdgR and LdgF by -g (docs/aircraft.md §2.1);
    # a positive turn about +X swings a wheel below the hinge forward.
    for s, n, ax in ((-1, "LdgL", 1), (1, "LdgR", -1)):
        piv = Vector((2.05 * s, -2.16, 1.95))
        place(parts[n], piv)
        hinge(n, piv, (ax, 0, 0))
    place(parts["LdgF"], Vector((0.0, 4.55, 1.15)))
    hinge("LdgF", Vector((0.0, 4.55, 1.15)), (-1, 0, 0))
    for n in ("LdgDr", "canopy", "pilot"):
        o = parts[n]
        vs = [v.co for v in o.data.vertices]  # (bound_box is stale after data.transform)
        c = (Vector(map(min, *vs)) + Vector(map(max, *vs))) / 2
        place(o, c + ORIGIN)

    # Points: nozzle (radius 0.55 as the Y difference), gun (left shoulder), stations A..I, wheel height, eye.
    empty("EngineL", Vector((0.0, -6.24, 1.94)))
    empty("EngineL1", Vector((0.0, -6.24, 2.49)))
    empty("StationGun", Vector((-0.75, 1.5, 2.45)))
    stations = [(-4.6, -2.6, 2.0), (-3.4, -2.4, 2.0), (-2.4, -2.3, 2.0), (-0.75, -2.6, 1.35), (0.0, -0.5, 1.2),
                (0.75, -2.6, 1.35), (2.4, -2.3, 2.0), (3.4, -2.4, 2.0), (4.6, -2.6, 2.0)]
    for letter, p in zip("ABCDEFGHI", stations):
        empty("Station" + letter, Vector(p))
    empty("Height", Vector((0.0, ORIGIN.y, 0.0)))
    empty("Camera", eye)

    for o in bpy.context.scene.objects:
        o.select_set(o is root or o.parent is root)
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/f35i.gltf", export_format='GLTF_SEPARATE', export_yup=True,
                              use_selection=True, export_apply=True, export_texture_dir="textures")
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type == 'MESH')
    print("RIGGED", OUT, "triangles", tris, "parts", sorted(parts))


main()
