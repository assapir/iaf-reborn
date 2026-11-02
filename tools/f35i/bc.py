# The F-35I's cockpit-view model (f35i_bc.gltf, docs/views.md §4.3 "Own jet in the cockpit views"): what the pilot
# sees of the own jet when looking aside or back. Built from the rigged model (tools/f35i/rig.py's f35i.gltf): the
# airframe aft of the eye (wings, spine, tails), without the canopy glass, pilot, gear and pylons; the canopy's rear
# frame arch and its side rails behind the eye (the panel, tools/f35i/cockpit3d.py, has them ahead of it), their own
# object f35i_bc_frame, which the 3D cockpit hides (it has its own, terrain_view.gd); and the fuselage ahead of the
# eye, its own object f35i_bc_nose, seen over the glareshield in both cockpits. Same frame as f35i.gltf, so the game
# moves it by the descriptor's eye like the originals' *_bc.x.
#
#   blender -b --python tools/f35i/bc.py -- game/extra/planes/f35i
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plane"))
import kit  # noqa: E402

DIR = sys.argv[sys.argv.index("--") + 1]
CUT = 0.10  # model m behind the eye: the cut (the panel art shows everything ahead of the eye)
PRESENT_SCALE = 2.0
NOSE_SKIN = "skin_37"  # f35i.gltf's outer skin ahead of the eye (its cockpit is skin_36 / 43 / 45)
# The nose starts NOSE_FROM m ahead of the eye, past the panel: behind it the airframe's deck lies under the panel and
# its sides under the sills (unseen from the eye; below the 2D panel strip the view shows the ground, as before).
NOSE_FROM = 0.85


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    eye_g = json.load(open(os.path.join(DIR, "aircraft.json")))["eye"]  # glTF frame: +Y up, -Z nose
    eye = Vector((eye_g[0], -eye_g[2], eye_g[1]))  # Blender: Z up, +Y nose
    bpy.ops.import_scene.gltf(filepath=os.path.join(DIR, "f35i.gltf"))
    drop = ("canopy", "pilot", "Ldg", "Wheels", "Pylon")
    meshes = []
    for o in list(kit.scene().objects):
        if o.type == 'MESH' and not o.name.startswith(drop):
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
            meshes.append(o)
    for o in list(kit.scene().objects):
        if o not in meshes:
            bpy.data.objects.remove(o)
    kit.bake_transforms(meshes)
    body = kit.join(meshes, "f35i_bc")
    kit.bake_transforms([body])
    # Cut at the plane CUT behind the eye and keep the aft part; inside the canopy's reach (around the seat) keep
    # only what is below the sill, so the downloaded model's cockpit tub does not wrap the eye.
    ycut = eye.y - CUT
    kit.bisect([body], lambda c: True, (0, ycut, 0), (0, 1, 0))
    # Ours: the fuselage ahead of the cut, its nose seen over the glareshield, a separate object. Only the outer
    # skin: the downloaded model's own cockpit (panel, HUD, seat) goes, and so do the parts under the nose and on its
    # sides the eye never sees (EOTS window, lights, the nose number), one material, one draw call. Drawn at twice its
    # distance like the whole model, it stays behind the 3D cockpit's parts (the 2D panel art covers it likewise).
    nose = kit.extract([body], lambda c: c.y > ycut, "f35i_bc_nose")
    kit.bisect([nose], lambda c: True, (0, eye.y + NOSE_FROM, 0), (0, 1, 0))
    bm = bmesh.new()
    bm.from_mesh(nose.data)
    mats = [m.name for m in nose.data.materials]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if mats[f.material_index] != NOSE_SKIN
                               or f.calc_center_median().y < eye.y + NOSE_FROM], context='FACES')
    bm.to_mesh(nose.data)
    bm.free()
    # Its own copy of the paint, one-sided: from the eye, inside the hull, its inner faces would show below the 2D
    # panel strip when looking down.
    skin = nose.data.materials[mats.index(NOSE_SKIN)].copy()
    skin.name = NOSE_SKIN + "_nose"
    skin.use_backface_culling = True
    nose.data.materials.clear()
    nose.data.materials.append(skin)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    gone = [f for f in bm.faces if f.calc_center_median().y > ycut
            or (abs(f.calc_center_median().x) < 0.30 and f.calc_center_median().y > eye.y - 0.8
                and f.calc_center_median().z > eye.z - 0.15)]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(body.data)
    bm.free()

    # Ours: the canopy's rear frame arch and the side rails behind the eye (the seat's head box, right behind the
    # eye, would fill the view: the camera stays at the eye when the head turns). The rails lie on the airframe's
    # sills, as the panel's (cockpit3d.py RAIL, which also has the arch for the 3D cockpit).
    dark = kit.material("bc_frame", (0.055, 0.057, 0.062), roughness=0.5)
    for s in (-1, 1):
        rail = [eye + Vector(p)
                for p in ((s * 0.47, -CUT + 0.05, -0.36), (s * 0.46, -0.6, -0.35), (s * 0.42, -1.1, -0.32))]
        kit.sweep(f"rail{s}", dark, kit.rounded_rect(0.085, 0.060, 0.022), [tuple(p) for p in rail])
    # The arch: the canopy's rear frame, over the head box from rail to rail.
    arch = []
    for a in np.linspace(-math.pi / 2, math.pi / 2, 25):
        arch.append(tuple(eye + Vector((0.46 * math.sin(a), -0.75 - 0.05 * math.cos(a), -0.34 + 0.55 * math.cos(a)))))
    kit.sweep("arch", dark, kit.rounded_rect(0.07, 0.05, 0.018), arch)
    # Modelled in real metres around the eye, like the panel art; the game draws the jet at the Present scale (2.0,
    # docs/adding-a-plane.md §2), so they shrink by half about the eye to come out real size.
    parts = [o for o in kit.scene().objects if o.type == 'MESH' and o not in (body, nose)]
    k = Matrix.Translation(eye) @ Matrix.Scale(1.0 / PRESENT_SCALE, 4) @ Matrix.Translation(-eye)
    for o in parts:
        o.matrix_world = k @ o.matrix_world
    kit.bake_transforms(parts)
    frame = kit.join(parts, "f35i_bc_frame")
    for o in kit.scene().objects:
        o.select_set(o in (body, frame, nose))
    bpy.ops.export_scene.gltf(filepath=os.path.join(DIR, "f35i_bc.gltf"), export_format='GLTF_SEPARATE',
                              export_yup=True, use_selection=True, export_apply=True, export_texture_dir="textures")
    print(*(f"{o.name} {sum(len(p.vertices) - 2 for p in o.data.polygons)}" for o in (body, frame, nose)))


main()
