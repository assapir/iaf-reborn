# Shared Blender helpers for adding a plane (docs/adding-a-plane.md): rigging a downloaded model for the game, its
# skin and markings, and modelling / rendering a cockpit panel with the game's cockpit camera. Plane-specific data
# lives in the plane's own scripts (e.g. tools/f35i/rig.py, tools/f35i/cockpit3d.py), which import this:
#
#   sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "plane")); import kit
#
# Coordinates are Blender's (Z up, nose +Y, metres); the glTF export turns them into the game's (+Y up, nose -Z).
import json
import math
import os

import bmesh
import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Matrix, Vector


def scene():
    return bpy.context.scene


def deselect():
    for x in bpy.context.selected_objects:
        x.select_set(False)


# --- import and cut a model ----------------------------------------------------------------------------------

def normalise(src, length, nose_minus_y=True):
    """Import a glTF, flatten its hierarchy and bake every mesh to world coordinates: `length` m long, nose +Y,
    wheels on z = 0, centred. Returns {mesh name without "Object_": object}."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in scene().objects if o.type == 'MESH']
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in scene().objects if o.type != 'MESH']:
        bpy.data.objects.remove(o)
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    mn, mx = Vector(map(min, *pts)), Vector(map(max, *pts))
    k = length / (mx.y - mn.y)
    turn = Matrix.Rotation(math.pi, 4, 'Z') if nose_minus_y else Matrix.Identity(4)
    m = Matrix.Scale(k, 4) @ turn @ Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
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
        deselect()
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
    deselect()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def bake_transforms(objs):
    """Apply object transforms so the meshes are in world coordinates (primitives keep theirs on the object)."""
    for o in objs:
        deselect()
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def decimate(o, ratio):
    d = o.modifiers.new("dec", 'DECIMATE')
    d.ratio = ratio
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="dec")


# --- materials and images ------------------------------------------------------------------------------------

def material(name, colour, metallic=0.0, roughness=0.5, image=None, clip=False, grain=0.0, holdout=False, alpha=None):
    """A Principled material; `image` drives the colour (and with `clip` the alpha cutout); `grain` a fine paint
    bump; `holdout` a transparent hole in renders; `alpha` blended glass."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    if holdout:
        nt.nodes.clear()
        nt.links.new(nt.nodes.new("ShaderNodeHoldout").outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
        return m
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*colour, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    if alpha is not None:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = 'BLEND'
    if image is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        if clip:
            nt.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
            m.blend_method = 'CLIP'
        nt.nodes.active = tex
    if grain:
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 900.0
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = grain
        nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def image(name, rgba):
    """A packed image from an (h, w, 4) float array (rows top to bottom)."""
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).ravel().astype(np.float32))
    img.pack()
    return img


def low_vis(path, dark=0.15, span=0.45):
    """An emblem (RGBA file) in low-visibility greys: luminance mapped to dark .. dark + span, alpha kept."""
    src = bpy.data.images.load(path)
    w, h = src.size
    px = np.array(src.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    g = dark + span * (px[..., :3] @ np.array([0.30, 0.59, 0.11]))
    return np.dstack([g, g * 1.02, g * 1.05, px[..., 3]])


def _ramp(edge, x):
    return np.clip((x - edge[0]) / (edge[1] - edge[0]), 0.0, 1.0)


def roundel(star_rgb, disc_rgb, n=512, big_r=0.78, width=0.13):
    """The IAF roundel as an RGBA array: a Magen David (two triangle outlines, circumradius `big_r`, stroke `width`
    of the disc radius) in `star_rgb` on a disc of `disc_rgb`."""
    ys, xs = np.mgrid[0:n, 0:n]
    px = (xs + 0.5) / n * 2 - 1
    py = 1 - (ys + 0.5) / n * 2
    aa = 2.0 / n
    disc = _ramp((1.0, 1.0 - aa), np.hypot(px, py))
    star = np.zeros_like(px, dtype=np.float64)
    for rot in (-math.pi / 2, math.pi / 2):
        d = np.full(px.shape, np.inf)
        for k in range(3):
            a = rot + k * 2 * math.pi / 3
            d = np.minimum(d, big_r / 2 - (px * math.cos(a) + py * math.sin(a)))
        star = np.maximum(star, _ramp((-aa, aa), d) * _ramp((width + aa, width - aa), d))
    rgb = np.array(disc_rgb) * (1 - star[..., None]) + np.array(star_rgb) * star[..., None]
    return np.dstack([rgb, disc])


# --- skin: our textures with baked ambient occlusion ---------------------------------------------------------

def bake_skin(objs_sizes, colour, no_ao=(), keep_prefixes=("skin_",)):
    """Every object of {object: texture size} gets a fresh UV atlas and an image of `colour` shaded by ambient
    occlusion baked from the model (coincident twin surfaces hidden while baking; `no_ao`: thin parts left
    unshaded); any other material still showing a downloaded image becomes plain `colour` (so no download image
    is exported)."""
    sc = scene()
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 96
    sc.render.bake.margin = 8
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake")
    sc.world.light_settings.distance = 0.6
    col = np.array(colour)

    def box(o):
        vs = [v.co for v in o.data.vertices]
        return Vector(map(min, *vs)), Vector(map(max, *vs))

    meshes = [o for o in sc.objects if o.type == 'MESH']
    for o, size in objs_sizes.items():
        deselect()
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        o.data.uv_layers.new(name="UVMap")
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
        bpy.ops.object.mode_set(mode='OBJECT')
        name = "skin_" + o.name.removeprefix("Object_")
        img = bpy.data.images.new(name, size, size)
        o.data.materials.clear()
        o.data.materials.append(material(name, tuple(col), metallic=0.15, roughness=0.55, image=img))
        a, b = box(o)
        twins = [x for x in meshes if x is not o and (box(x)[0] - a).length < 0.02 and (box(x)[1] - b).length < 0.02]
        for x in twins:
            x.hide_render = True
        if o in no_ao:
            ao = np.ones((size, size))
        else:
            bpy.ops.object.bake(type='AO')
            ao = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)[..., 0]
        for x in twins:
            x.hide_render = False
        rgb = np.clip(col[None, None, :] * (0.5 + 0.5 * ao)[..., None], 0, 1)
        img.pixels.foreach_set(np.dstack([rgb, np.ones((size, size))]).astype(np.float32).ravel())
        img.pack()
    plain = material("skin_plain", tuple(col * 0.85), metallic=0.15, roughness=0.55)
    for o in [o for o in sc.objects if o.type == 'MESH']:
        for i, m in enumerate(o.data.materials):
            if m and m.use_nodes and any(nd.type == 'TEX_IMAGE' and nd.image and not nd.image.name.startswith(keep_prefixes)
                                         for nd in m.node_tree.nodes):
                o.data.materials[i] = plain
    eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in eng else 'BLENDER_EEVEE'


# --- decals --------------------------------------------------------------------------------------------------

def _hit(origin, direction):
    dg = bpy.context.evaluated_depsgraph_get()
    ok, loc, nor, *_ = scene().ray_cast(dg, Vector(origin), Vector(direction).normalized())
    if not ok:
        raise SystemExit(f"decal ray {origin} -> {direction} hit nothing")
    nor = Vector(nor)
    if nor.dot(Vector(direction)) > 0:
        nor = -nor
    return loc, nor.normalized()


def decal(name, mat, origin, direction, w, h, right, grid=8):
    """`mat` on the first surface hit from `origin` along `direction`, its image's x along `right`: an N x N grid
    whose vertices are each projected onto the skin (it follows curved panels), 8 mm off it."""
    loc, n = _hit(origin, direction)
    r = (Vector(right) - n * n.dot(Vector(right))).normalized()
    up = n.cross(r)
    dg = bpy.context.evaluated_depsgraph_get()
    vs, uvs = [], []
    for j in range(grid + 1):
        for i in range(grid + 1):
            u, v = i / grid, j / grid
            p = loc + r * (u - 0.5) * w + up * (v - 0.5) * h
            ok, hit, hn, *_ = scene().ray_cast(dg, p + n * 0.4, -n, distance=0.8)
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
    scene().collection.objects.link(o)
    return o


def text_decal(name, body, mat, origin, direction, height, right):
    """Text (Blender's built-in font) as a flat mesh on the surface hit from `origin`."""
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
    o.data.transform(Matrix.Translation(loc + n * 0.014) @ Matrix((r, up, n)).transposed().to_4x4())
    o.matrix_world = Matrix.Identity(4)
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o


# --- the game's frame: root, parts, helpers, export ------------------------------------------------------------

class Rig:
    """The model as the game reads it (docs/adding-a-plane.md §2): one root (the body) at `origin`, each moving part
    a child with its origin on its hinge, the `<part>1/2` hinge helpers and the named points as empties."""

    def __init__(self, root, parts, origin):
        self.root, self.parts, self.origin = root, parts, Vector(origin)
        shift = Matrix.Translation(-self.origin)
        for o in [root, *parts.values()]:
            o.data.transform(shift)

    def place(self, name, pivot):
        o = self.parts[name]
        p = Vector(pivot) - self.origin
        o.data.transform(Matrix.Translation(-p))
        o.location = p
        o.parent = self.root

    def place_centre(self, name):
        """A part that does not turn (doors, crew): its origin on its own centre."""
        vs = [v.co for v in self.parts[name].data.vertices]  # (bound_box is stale after data.transform)
        self.place(name, (Vector(map(min, *vs)) + Vector(map(max, *vs))) / 2 + self.origin)

    def empty(self, name, p):
        e = bpy.data.objects.new(name, None)
        scene().collection.objects.link(e)
        e.location = Vector(p) - self.origin
        e.parent = self.root
        e.empty_display_size = 0.05

    def hinge(self, name, pivot, axis):
        """`<name>1` / `<name>2` on the hinge line, ordered so the game's axis (nearer -> farther from the origin)
        is `axis`."""
        d = Vector(axis).normalized()
        q = Vector(pivot) - self.origin
        t = max(0.0, -q.dot(d) + 0.05)  # along the line the distance to the origin grows past t = -q·d
        self.empty(name + "1", Vector(pivot) + d * t)
        self.empty(name + "2", Vector(pivot) + d * (t + 1.0))

    def part(self, name, pivot, axis):
        self.place(name, pivot)
        self.hinge(name, pivot, axis)

    def export(self, path):
        for o in scene().objects:
            o.select_set(o is self.root or o.parent is self.root)
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLTF_SEPARATE', export_yup=True, use_selection=True,
                                  export_apply=True, export_texture_dir="textures")
        return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in scene().objects if o.type == 'MESH')


def pilot(eye, colour=(0.25, 0.27, 0.2), helmet=None, head_r=0.16):
    """A stand-in pilot (helmet + torso) for a model without one: ejection throws one seat per pilot part."""
    eye = Vector(eye)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=head_r, location=eye + Vector((0, 0, 0.02)))
    head = bpy.context.active_object
    bpy.ops.mesh.primitive_cube_add(size=1, location=eye + Vector((0, -0.1, -0.35)))
    torso = bpy.context.active_object
    torso.scale = (0.45, 0.3, 0.55)
    bake_transforms([head, torso])
    suit = material("pilot", colour)
    torso.data.materials.append(suit)
    head.data.materials.append(material("helmet", helmet, roughness=0.35) if helmet else suit)
    return join([head, torso], "pilot")


# --- cockpit panels: modelled in metres around the eye, rendered with the game's cockpit camera ---------------

def box(name, centre, size, m, rot=(0, 0, 0), bevel=0.004):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre, rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        b = o.modifiers.new("bevel", 'BEVEL')
        b.width = bevel
        b.segments = 3
        b.limit_method = 'ANGLE'
    o.data.materials.append(m)
    return o


def cyl(name, centre, r, depth, m, rot=(90, 0, 0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=centre,
                                        rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(m)
    bpy.ops.object.shade_smooth()
    return o


def arch(name, m, width, rise, y0, y1, z, thickness, steps=32):
    """An arched hood (a glareshield): across x in ±width/2, its top at z + rise·(1 − (2x/width)²) from y0 (rear,
    toward the pilot) to y1, `thickness` deep; smooth-shaded."""
    bm = bmesh.new()
    rows = []
    for zoff in (0.0, -thickness):
        for y in (y0, y1):
            rows.append([bm.verts.new((x, y, z + zoff + rise * (1 - (2 * x / width) ** 2)))
                         for x in np.linspace(-width / 2, width / 2, steps + 1)])
    top_r, top_f, bot_r, bot_f = rows
    for i in range(steps):
        for a, b in ((top_r, top_f), (bot_f, bot_r), (bot_r, top_r), (top_f, bot_f)):
            bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
    for row in (lambda r: r[0], lambda r: r[-1]):
        bm.faces.new((row(top_r), row(bot_r), row(bot_f), row(top_f)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    scene().collection.objects.link(o)
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    b = o.modifiers.new("bevel", 'BEVEL')
    b.width = 0.006
    b.segments = 3
    return o


# The game's cockpit camera (cockpit.gd focal_length / projection_centre; docs/cockpit.md "3D view").
FOCAL = 686.242  # px: 320 / tan 25 deg
LOOK_DOWN = 5.5  # deg below the nose
PANEL_W, PANEL_H, ART = 1920, 352, 4  # the panel strip, panel px, and art px per panel px


def cockpit_camera(centre_row):
    """The game's cockpit camera at the eye (the origin, looking +Y): its projection centre at panel x 960 and
    panel row `centre_row` (measure it in the game: cockpit.projection_centre() - panel_top(), for the cockpit's
    MainOffsetY)."""
    sc = scene()
    cam = bpy.data.objects.new("eye", bpy.data.cameras.new("eye"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.rotation_euler = Euler((math.radians(90 - LOOK_DOWN), 0, 0), 'XYZ')
    sc.render.resolution_x, sc.render.resolution_y = PANEL_W * ART, PANEL_H * ART  # (the projection uses the aspect)
    c = cam.data
    c.sensor_fit = 'HORIZONTAL'
    c.sensor_width = 36.0
    c.lens = FOCAL * 36.0 / PANEL_W
    c.clip_start = 0.01
    c.shift_y = -(PANEL_H / 2 - centre_row) / PANEL_W
    bpy.context.view_layer.update()  # matrix_world for world_to_camera_view
    return cam


def panel_px(cam, p):
    """A point (metres, eye frame) -> panel px."""
    v = world_to_camera_view(scene(), cam, Vector(p))
    return Vector((v.x * PANEL_W, (1 - v.y) * PANEL_H))


def render_panel(path, samples=128, sky=(0.55, 0.62, 0.75), sun_energy=3.0):
    """Render the panel strip: transparent where the world shows (holdouts too), Cycles, denoised."""
    sc = scene()
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    w = bpy.data.worlds.new("sky")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (*sky, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = sun_energy
    sun.data.angle = math.radians(4)
    sun.rotation_euler = Euler((math.radians(-35), math.radians(15), 0), 'XYZ')  # from above, behind
    sc.collection.objects.link(sun)
    sc.render.filepath = path
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    bpy.ops.render.render(write_still=True)


# The F-16's lamps and gear lever in its converted lights bitmap (cockpits/f16 lights4: [LIGHTnnn] Left, Top,
# Right, Bottom of frame 0). A cockpit borrows them with "Shared": "f16" (never committed) and places them itself.
F16_LAMPS = {"LIGHT000": (21, 0, 74, 53), "LIGHT001": (21, 106, 62, 148), "LIGHT003": (0, 258, 18, 263),
             "LIGHT004": (0, 268, 21, 273), "LIGHT005": (21, 255, 43, 260), "LIGHT006": (43, 230, 60, 235),
             "LIGHT008": (21, 220, 33, 225), "LIGHT009": (0, 0, 21, 86), "SLIGHT000": (43, 190, 55, 201),
             "SLIGHT001": (21, 190, 32, 200), "SLIGHT002": (32, 190, 42, 200), "SLIGHT003": (21, 230, 43, 235)}
F16_LIGHTSON = {"FileName": "Lights4.bmp", "Height": 278.0, "Width": 74.0,
                "NightRScale": 1.0, "NightGScale": 1.0, "NightBScale": 2.0}


def lamp_sections(centres):
    """[LIGHTnnn] / [SLIGHTnnn] / [LIGHTSON] for the F-16's lamps centred on panel px `centres` {key: (x, y)};
    lamps not given are off."""
    sec = {"LIGHTSON": dict(F16_LIGHTSON)}
    for key in ["LIGHT%03d" % i for i in range(10)] + ["SLIGHT%03d" % i for i in range(4)]:
        if key not in centres or key not in F16_LAMPS:
            sec[key] = {"Active": 0.0}
            continue
        l, t, r, b = F16_LAMPS[key]
        c = centres[key]
        e = {"Active": 1.0, "Left": float(l), "Top": float(t), "Right": float(r), "Bottom": float(b),
             "OffsetX": round(c[0] - (r - l) / 2, 1), "OffsetY": round(c[1] - (b - t) / 2, 1)}
        if key == "LIGHT001":
            e["Blink"] = 1.0
        if key == "LIGHT009":
            e.update({"AnimFrames": 3.0, "AnimTime": 100.0})
        sec[key] = e
    return sec


def portals(x0, x1, y_top, pages):
    """[MFD] Portals: the MFD pages edge to edge across x0..x1 from row y_top, as one display (an MFD node is 164 px:
    its 132 px page and 16 px transparent bezels, which overlap the neighbours)."""
    k = round((x1 - x0) / (len(pages) * 132.0), 4)
    return [[round(x0 + i * 132 * k, 2), round(y_top, 2), k, p] for i, p in enumerate(pages)], k


def update_cockpit_json(path, sections, hud_rows=None, main_offset_y=None):
    """Merge `sections` into the cockpit.json at `path` (lamp sections replaced as a whole)."""
    c = json.load(open(path))
    for k in [k for k in c if k.startswith(("LIGHT", "SLIGHT"))]:
        del c[k]
    c.update(sections)
    if hud_rows:
        c["HUD"].update(hud_rows)
    if main_offset_y is not None:
        c["PANEL"]["MainOffsetY"] = float(main_offset_y)
    json.dump(c, open(path, "w"), indent=1)


# --- arming screen front view --------------------------------------------------------------------------------

# The arming art's look (menu bmp/arm/jets): a shaded front view in greens, dark green shadows to pale highlights.
ARM_DARK, ARM_LIGHT = (0.03, 0.08, 0.02), (0.42, 0.7, 0.36)
ARM_SIZE = (454, 357)  # the arming art, menu px (the converted art is x4)


def arm_front_view(gltf, out_png, px_per_m, centre, art=4, samples=64, mirror=True):
    """The plane's glTF (gear down, its rest pose) rendered from the front, orthographic, in the arming art's greens,
    transparent around it: `px_per_m` menu px per metre, the aircraft origin at menu px `centre`. Returns the
    projected points {empty name: (x, y) menu px} (its Station* empties: where the leader lines end). `mirror`: as
    the original's arming art, which puts station A (the left wing) on the image's left."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=gltf)
    sc = scene()
    w, h = ARM_SIZE
    sc.render.resolution_x, sc.render.resolution_y = w * art, h * art
    cam = bpy.data.objects.new("front", bpy.data.cameras.new("front"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = w / px_per_m
    cam.location = (0, 40, 0)
    cam.rotation_euler = Euler((math.radians(90), 0, math.radians(180)), 'XYZ')  # looking -Y (at the nose)
    cam.data.shift_x = (centre[0] - w / 2) / w * -1
    cam.data.shift_y = (centre[1] - h / 2) / w
    cam.data.clip_end = 100
    bpy.context.view_layer.update()
    pts = {}
    for o in sc.objects:
        if o.type == 'EMPTY' and o.name.startswith("Station"):
            v = world_to_camera_view(sc, cam, o.matrix_world.translation)
            x = v.x * w
            pts[o.name] = (round(w - x if mirror else x, 1), round((1 - v.y) * h, 1))
    eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in eng else 'BLENDER_EEVEE'
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    wd = bpy.data.worlds.new("w")
    sc.world = wd
    wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    sun = bpy.data.objects.new("key", bpy.data.lights.new("key", 'SUN'))
    sun.data.energy = 4.0
    sun.rotation_euler = Euler((math.radians(-55), math.radians(-30), math.radians(160)), 'XYZ')  # upper left, front
    sc.collection.objects.link(sun)
    tmp = out_png + ".raw.png"
    sc.render.filepath = tmp
    sc.render.image_settings.color_mode = 'RGBA'
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h * art, w * art, 4)[::-1]
    lum = np.clip((px[..., :3] @ np.array([0.30, 0.59, 0.11])) * 2.0, 0, 1) ** 1.1
    rgb = np.array(ARM_DARK) * (1 - lum[..., None]) + np.array(ARM_LIGHT) * lum[..., None]
    if mirror:
        rgb, px = rgb[:, ::-1], px[:, ::-1]
    save = bpy.data.images.new("arm_front", w * art, h * art, alpha=True)
    save.pixels.foreach_set(np.ascontiguousarray(np.dstack([rgb, px[..., 3]])[::-1]).astype(np.float32).ravel())
    save.filepath_raw = out_png
    save.file_format = 'PNG'
    save.save()
    os.remove(tmp)
    return pts
